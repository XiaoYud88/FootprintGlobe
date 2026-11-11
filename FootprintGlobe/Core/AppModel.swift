import SwiftUI
import Combine
import CoreLocation

enum DetailLevel {
    /// 只区分国家（整个中国轮廓）
    case country
    /// 省轮廓 + 去过的省高亮
    case province
    /// 市轮廓 + 城市名 + 去过的市高亮
    case city
}

/// 全局状态：相机（地球/中国平面图的连续缩放）、定位、到访数据。
@MainActor
final class AppModel: ObservableObject {
    // MARK: 相机
    /// 0 ... 8。`zoom < 1.5` 显示自绘 3D 地球，`>= 1.5` 显示中国平面图。
    @Published var zoom: Double = 0
    /// 当前视角中心（GCJ-02）
    @Published var center = GeoCoord.chinaCenter
    /// 我的位置（GCJ-02），没定位到时为 nil
    @Published var focus: GeoCoord?
    /// 当前所在城市
    @Published var currentCity: Region?
    /// 跟随定位
    @Published var autoFollow = true
    /// 轻提示
    @Published var toast: String?

    // MARK: 数据
    let boundary = BoundaryStore.shared
    let visits: VisitStore
    let tracker: VisitTracker
    let location = LocationService()

    private var cancellables = Set<AnyCancellable>()
    private var started = false

    init() {
        let store = VisitStore()
        self.visits = store
        self.tracker = VisitTracker(boundary: BoundaryStore.shared, visits: store)

        // 把 VisitStore 的变化转发出去，视图只订阅 AppModel 就够了
        store.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        tracker.onUnlock = { [weak self] region in
            self?.showToast("新解锁 · \(region.name)")
        }
    }

    // MARK: - 生命周期

    func start() {
        guard !started else { return }
        started = true
        location.onUpdate = { [weak self] location in
            Task { @MainActor in self?.handle(location) }
        }
        location.start()
        tracker.begin()
    }

    private func handle(_ location: CLLocation) {
        let gcj = GeoMath.wgs84ToGcj02(GeoCoord(location.coordinate))
        focus = gcj
        currentCity = boundary.city(containing: gcj)
        if autoFollow {
            center = gcj
        }
        tracker.ingest(location)
    }

    // MARK: - 相机

    static let globeThreshold = 1.5
    static let maxZoom = 8.0

    var isGlobe: Bool { zoom < Self.globeThreshold }

    /// 屏幕宽度对应的经度跨度
    var lonSpan: Double { 200.0 / pow(2, zoom) }

    var globeRadiusFactor: Double {
        0.34 + 0.20 * min(zoom, Self.globeThreshold) / Self.globeThreshold
    }

    var detail: DetailLevel {
        if isGlobe { return .country }
        if lonSpan > 45 { return .country }
        if lonSpan > 8 { return .province }
        return .city
    }

    func setZoom(_ value: Double) {
        zoom = min(max(value, 0), Self.maxZoom)
    }

    func magnify(from base: Double, scale: CGFloat) {
        let delta = log2(max(0.05, Double(scale)))
        setZoom(base + delta)
    }

    func pan(dx: CGFloat, dy: CGFloat, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        autoFollow = false
        if isGlobe {
            let radius = Double(min(size.width, size.height)) * globeRadiusFactor
            guard radius > 1 else { return }
            let degPerPoint = 110.0 / radius
            var lon = center.lon - Double(dx) * degPerPoint
            let lat = min(max(center.lat + Double(dy) * degPerPoint, -75), 75)
            lon = ((lon + 180).truncatingRemainder(dividingBy: 360) + 360)
                .truncatingRemainder(dividingBy: 360) - 180
            center = GeoCoord(lon: lon, lat: lat)
        } else {
            let pointsPerDegree = Double(size.width) / lonSpan
            guard pointsPerDegree > 0 else { return }
            let pointsPerLatDegree = pointsPerDegree / max(0.25, cos(center.lat * .pi / 180))
            let lon = min(max(center.lon - Double(dx) / pointsPerDegree, 73), 136)
            let lat = min(max(center.lat + Double(dy) / pointsPerLatDegree, 3), 54)
            center = GeoCoord(lon: lon, lat: lat)
        }
    }

    func enterChina() {
        if let focus {
            center = focus
        }
        setZoom(max(zoom, 2.2))
    }

    func backToGlobe() {
        if let focus {
            center = focus
        }
        setZoom(0)
    }

    func focusOnMe() {
        autoFollow = true
        location.refreshNow()
        if let focus {
            center = focus
        }
        if zoom < 1 { setZoom(0) }
    }

    // MARK: - 手动操作

    func toggle(_ region: Region) {
        visits.toggle(code: region.code, region: region)
    }

    @discardableResult
    func markVisited(_ region: Region) -> Visit {
        visits.markVisited(region, manual: true)
    }

    func confirmPending(_ code: String) {
        guard let pending = visits.pendings[code] else { return }
        if let region = boundary.city(code: code) {
            visits.markVisited(region, manual: true)
        } else {
            visits.confirmPending(code: code)
        }
        visits.discardPending(code: pending.code)
        showToast("已加入 · \(pending.cityName)")
    }

    func discardPending(_ code: String) {
        visits.discardPending(code: code)
    }

    func showToast(_ text: String) {
        toast = text
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if self?.toast == text { self?.toast = nil }
        }
    }

    // MARK: - 统计

    var visitedCodes: Set<String> { visits.visitedCodes }
    var visitedProvinceCodes: Set<String> { visits.visitedProvinceCodes }
    var pendingCodes: Set<String> { visits.pendingCodes }

    var cityProgress: Double {
        boundary.cityCount > 0 ? Double(visits.cityCount) / Double(boundary.cityCount) : 0
    }

    var progressText: String { "\(visits.cityCount) / \(boundary.cityCount)" }

    var visitedCities: [Region] {
        visits.visitedCodes.compactMap { boundary.city(code: $0) }
    }

    var currentCityName: String {
        currentCity?.name ?? "未定位到城市"
    }
}
