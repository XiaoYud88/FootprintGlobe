import Foundation
import CoreLocation
import OSLog

/// 停留确认状态机。
///
/// 核心规则（防误判）：
/// 1. 定位点先按 GCJ-02 落到某个地级市，没落进去（在境外/海上/数据空洞）就直接忽略；
/// 2. 进城只生成「候选」，不写记录；
/// 3. 候选要满足「至少 2 次独立采样」且「时间跨度 ≥ 停留阈值（默认 3 小时）」才转正；
/// 4. 离开该市时，若候选仍未达标，按「路过」丢弃（高铁/开车经过就进不了名单）；
/// 5. 同一城市已经在名单里，只更新最后到访时间与天数，不再重复记录。
@MainActor
final class VisitTracker {
    struct Config: Equatable, Codable {
        /// 判定「真的待在这里」所需的最短停留时长（小时）
        var dwellHours: Double = 3
        /// 最少独立采样次数
        var minSamples: Int = 2
        /// 平均速度超过这个值视为「在赶路」，不作为到访证据
        var maxTravelSpeedKmh: Double = 120
        /// 速度很快且停留很短，直接判为路过
        var fastSpeedKmh: Double = 70
        var fastPassMaxHours: Double = 0.5
        /// 候选超过这个天数没被确认就自动清掉
        var pendingExpireDays: Double = 14
    }

    var config = Config() {
        didSet { saveConfig() }
    }

    private let boundary: BoundaryStore
    private let store: VisitStore
    private let log = Logger(subsystem: "com.personal.footprintglobe", category: "tracker")

    private var lastSample: (coord: GeoCoord, date: Date)?

    /// 最近一次「确认成功」的城市，供 UI 弹提示
    var onUnlock: ((Region) -> Void)?

    /// 新的待确认到访（已经待了一会儿但还没达标），用于本地通知
    var onNewPending: ((Region) -> Void)?

    /// 同一次停留只提醒一次，避免每次采样都弹
    private var notifiedPendings: Set<String> = []

    private static let configKey = "tracker.config"

    init(boundary: BoundaryStore, visits: VisitStore) {
        self.boundary = boundary
        self.store = visits
        loadConfig()
    }

    func begin() {
        expireOutdatedPendings()
    }

    /// 喂一个定位点。内部自己做坐标系转换与过滤。
    func ingest(_ location: CLLocation, date: Date = Date()) {
        // 精度太差（>500m）的定位不要，避免把边界判歪
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 500 else {
            log.debug("skip low accuracy \(location.horizontalAccuracy)")
            return
        }

        let gcj = GeoMath.wgs84ToGcj02(GeoCoord(location.coordinate))
        guard let city = boundary.city(containing: gcj) else {
            lastSample = (gcj, date)
            return
        }

        let speedKmh = estimatedSpeed(to: gcj, at: date, reported: location.speed)
        lastSample = (gcj, date)

        // 已在名单里：只更新统计
        if store.isVisited(city.code) {
            store.touch(city, at: date)
            return
        }

        // 换了城市：先把上一个候选结掉
        for open in store.pendingList where open.code != city.code {
            finishOtherPending(open, at: date)
        }

        let pending = store.upsertPending(city, coord: gcj, at: date)

        if qualifies(pending) {
            confirm(city, at: date)
            return
        }

        // 已经待了一会儿（≥1 小时、≥2 次采样）但还没到 3 小时：推一条「要记录吗」
        if pending.sampleCount >= 2, pending.spanHours >= 1,
           !notifiedPendings.contains(city.code) {
            notifiedPendings.insert(city.code)
            onNewPending?(city)
        }

        // 高速通过 + 停留过短：直接判为路过
        if speedKmh > config.fastSpeedKmh, pending.spanHours < config.fastPassMaxHours, pending.sampleCount > 1 {
            log.debug("pass-by \(city.name) speed=\(speedKmh)")
            store.discardPending(code: city.code)
        }
    }

    /// 手动确认一个候选
    func confirmManually(code: String, at date: Date = Date()) {
        guard let pending = store.pendings[code] else { return }
        if let region = boundary.city(code: pending.code) {
            store.markVisited(region, manual: true, at: date)
        } else {
            store.confirmPending(code: code, at: date)
        }
        store.discardPending(code: code)
    }

    // MARK: - 判定细节

    private func qualifies(_ pending: PendingVisit) -> Bool {
        pending.sampleCount >= config.minSamples && pending.spanHours >= config.dwellHours
    }

    private func finishOtherPending(_ pending: PendingVisit, at date: Date) {
        if qualifies(pending), let region = boundary.city(code: pending.code) {
            confirm(region, at: date)
        } else {
            log.debug("drop pending \(pending.cityName) span=\(pending.spanHours)h samples=\(pending.sampleCount)")
            store.discardPending(code: pending.code)
        }
    }

    private func confirm(_ region: Region, at date: Date) {
        store.confirmPending(code: region.code, at: date)
        log.info("confirmed visit: \(region.name)")
        onUnlock?(region)
    }

    private func estimatedSpeed(to coord: GeoCoord, at date: Date, reported: Double) -> Double {
        if let last = lastSample {
            let dt = date.timeIntervalSince(last.date)
            if dt > 120 {
                return GeoMath.kilometers(last.coord, coord) / (dt / 3600)
            }
        }
        return reported >= 0 ? reported * 3.6 : 0
    }

    private func expireOutdatedPendings() {
        let limit = config.pendingExpireDays * 24 * 3600
        let now = Date()
        for pending in store.pendingList where now.timeIntervalSince(pending.lastSeen) > limit {
            store.discardPending(code: pending.code)
        }
    }

    // MARK: - 配置持久化

    private func loadConfig() {
        guard let data = UserDefaults.standard.data(forKey: Self.configKey),
              let decoded = try? JSONDecoder().decode(Config.self, from: data) else { return }
        config = decoded
    }

    private func saveConfig() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: Self.configKey)
    }
}
