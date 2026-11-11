import Foundation

enum VisitStatus: String, Codable, Hashable {
    /// 去过了
    case visited
    /// 想去（愿望单，M1 主要用，M0 已可手动标记）
    case wishlist
}

/// 一条「到访」记录。以地级市为最小单位。
struct Visit: Identifiable, Codable, Hashable {
    var code: String
    var cityName: String
    var provinceCode: String
    var status: VisitStatus
    var firstSeen: Date
    var lastSeen: Date
    /// 独立到访天数（按自然日去重）
    var dayCount: Int
    /// 定位采样命中次数
    var sampleCount: Int
    /// 是否手动添加
    var isManual: Bool
    var note: String

    var id: String { code }

    var dayText: String { dayCount > 1 ? "\(dayCount) 天" : "1 天" }
}

/// 待确认的候选到访：只进了城还不够，要「隔一段时间还在同一个城市」才转正。
struct PendingVisit: Identifiable, Codable, Hashable {
    var code: String
    var cityName: String
    var provinceCode: String
    var firstSeen: Date
    var lastSeen: Date
    var sampleCount: Int
    var lastLon: Double
    var lastLat: Double

    var id: String { code }

    var spanHours: Double {
        lastSeen.timeIntervalSince(firstSeen) / 3600
    }

    var dominantCoord: GeoCoord { GeoCoord(lon: lastLon, lat: lastLat) }
}
