import Foundation
import CoreLocation

// MARK: - 出行方式

/// 一段行程用什么走的。地球上会按这个画不同的东西：
/// 飞机在高空飞、高铁沿地面跑、徒步只有小小的一个点。
enum TransportMode: String, Codable, CaseIterable, Identifiable {
    case plane
    case highSpeed
    case train
    case car
    case ship
    case walk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plane: return "飞机"
        case .highSpeed: return "高铁"
        case .train: return "火车"
        case .car: return "汽车"
        case .ship: return "船"
        case .walk: return "徒步"
        }
    }

    var symbol: String {
        switch self {
        case .plane: return "airplane"
        case .highSpeed: return "tram.fill"
        case .train: return "train.side.front.car"
        case .car: return "car.fill"
        case .ship: return "ferry.fill"
        case .walk: return "figure.walk"
        }
    }

    /// 离地高度（球半径的比例）：飞机看着明显「浮」在球面上，这是立体感的主要来源
    var altitude: Double {
        switch self {
        case .plane: return 0.075
        case .highSpeed: return 0.022
        case .train: return 0.020
        case .car: return 0.016
        case .ship: return 0.012
        case .walk: return 0.009
        }
    }

    /// 走完一整趟用多少秒（越慢的工具走得越久，但都控制在 12–30 秒，不然看着像静止）
    var duration: Double {
        switch self {
        case .plane: return 14
        case .highSpeed: return 18
        case .train: return 22
        case .car: return 24
        case .ship: return 28
        case .walk: return 30
        }
    }

    /// 图标相对球半径的大小
    var iconScale: Double {
        switch self {
        case .plane: return 0.052
        case .highSpeed: return 0.040
        case .train: return 0.038
        case .car: return 0.034
        case .ship: return 0.036
        case .walk: return 0.026
        }
    }

    /// 轨迹线用实线还是虚线（地面交通画实线，飞机画虚线更像航图）
    var dashed: Bool {
        switch self {
        case .plane: return true
        default: return false
        }
    }

    /// 图标要不要跟着行进方向转（飞机、船头朝前才像在飞；车和火车横着看更清楚）
    var turns: Bool {
        switch self {
        case .plane, .ship: return true
        default: return false
        }
    }
}

// MARK: - 一段行程

struct TripLeg: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// 出发城市 code（Region.code）
    var fromCode: String
    /// 到达城市 code
    var toCode: String
    var mode: TransportMode = .plane
    var date: Date = Date()
    var note: String = ""
    /// 是否显示在地球上（最多 10 条，由 TripStore 保证）
    var showcased: Bool = true
}

// MARK: - 家 + 行程的存储

/// 家和行程都存在 `travel.json` 里。和足迹数据分开存，损坏了也不会影响记录本身。
@MainActor
final class TripStore: ObservableObject {
    @Published private(set) var homeCode: String?
    @Published private(set) var legs: [TripLeg] = []

    /// 地球上同时显示的线路上限
    static let maxShowcase = 10

    private let fileURL: URL

    private struct Snapshot: Codable {
        var homeCode: String?
        var legs: [TripLeg]
    }

    init() {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FootprintGlobe", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("travel.json")
        load()
    }

    // MARK: 家

    func setHome(_ code: String?) {
        guard homeCode != code else { return }
        homeCode = code
        save()
    }

    func isHome(_ code: String) -> Bool { homeCode == code }

    // MARK: 行程

    /// 正在地球上显示的那几条（最多 10 条）
    var showcasedLegs: [TripLeg] {
        Array(legs.filter { $0.showcased }.prefix(Self.maxShowcase))
    }

    var showcasedCount: Int { legs.filter { $0.showcased }.count }

    @discardableResult
    func add(_ leg: TripLeg) -> Bool {
        guard leg.fromCode != leg.toCode else { return false }
        // 同一条线路同一种交通只留一条，避免地球上一模一样的线叠在一起
        if legs.contains(where: { $0.fromCode == leg.fromCode
            && $0.toCode == leg.toCode && $0.mode == leg.mode }) { return false }
        var newLeg = leg
        if showcasedCount >= Self.maxShowcase { newLeg.showcased = false }
        legs.insert(newLeg, at: 0)
        save()
        return true
    }

    func remove(_ id: UUID) {
        legs.removeAll { $0.id == id }
        save()
    }

    func toggleShowcase(_ id: UUID) {
        guard let index = legs.firstIndex(where: { $0.id == id }) else { return }
        if legs[index].showcased {
            legs[index].showcased = false
        } else {
            // 已经满 10 条时，把最早那条换下来（旧的不显示，新的顶上去）
            if showcasedCount >= Self.maxShowcase,
               let first = legs.firstIndex(where: { $0.showcased }) {
                legs[first].showcased = false
            }
            legs[index].showcased = true
        }
        save()
    }

    func updateNote(_ id: UUID, note: String) {
        guard let index = legs.firstIndex(where: { $0.id == id }) else { return }
        legs[index].note = note
        save()
    }

    var hasLegs: Bool { !legs.isEmpty }

    // MARK: 备份 / 恢复

    /// 备份用：把家和行程一起导出成一段 JSON
    func exportData() -> Data? {
        let snapshot = Snapshot(homeCode: homeCode, legs: legs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(snapshot)
    }

    /// 恢复用：拿备份包里的 travel.json 整段覆盖本地，成功返回 true
    @discardableResult
    func importData(_ data: Data) -> Bool {
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return false }
        homeCode = snapshot.homeCode
        legs = snapshot.legs
        save()
        return true
    }

    // MARK: 落盘

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        homeCode = snapshot.homeCode
        legs = snapshot.legs
    }

    private func save() {
        let snapshot = Snapshot(homeCode: homeCode, legs: legs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - 大圆航线

/// 球面上两点之间的最短路径。飞机、船走的就是这条线，画在球上是一条弧，比直线好看得多。
enum GreatCircle {
    /// 返回从 a 到 b、走过 t（0…1）之后的位置
    static func point(from a: GeoCoord, to b: GeoCoord, t: Double) -> GeoCoord {
        let (x1, y1, z1) = vector(a)
        let (x2, y2, z2) = vector(b)
        let dot = min(1, max(-1, x1 * x2 + y1 * y2 + z1 * z2))
        let omega = acos(dot)
        if omega < 0.0001 { return a }
        let sinOmega = sin(omega)
        guard sinOmega > 0.000001 else { return a }
        let k1 = sin((1 - t) * omega) / sinOmega
        let k2 = sin(t * omega) / sinOmega
        let x = x1 * k1 + x2 * k2
        let y = y1 * k1 + y2 * k2
        let z = z1 * k1 + z2 * k2
        let norm = sqrt(x * x + y * y + z * z)
        guard norm > 0 else { return a }
        let lat = asin(z / norm) * 180 / .pi
        let lon = atan2(y, x) * 180 / .pi
        return GeoCoord(lon: lon, lat: lat)
    }

    /// 两点之间的球面距离（公里）
    static func distanceKm(_ a: GeoCoord, _ b: GeoCoord) -> Double {
        let (x1, y1, z1) = vector(a)
        let (x2, y2, z2) = vector(b)
        let dot = min(1, max(-1, x1 * x2 + y1 * y2 + z1 * z2))
        return acos(dot) * 6_371.0088
    }

    /// 沿途采样，用来画弧线
    static func samples(from a: GeoCoord, to b: GeoCoord, count: Int) -> [GeoCoord] {
        guard count > 1 else { return [a, b] }
        return (0...count).map { point(from: a, to: b, t: Double($0) / Double(count)) }
    }

    private static func vector(_ p: GeoCoord) -> (Double, Double, Double) {
        let lon = p.lon * .pi / 180
        let lat = p.lat * .pi / 180
        return (cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
    }
}
