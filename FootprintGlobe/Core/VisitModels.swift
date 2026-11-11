import Foundation

enum VisitStatus: String, Codable, Hashable {
    /// 去过了
    case visited
    /// 想去（愿望单）
    case wishlist
}

/// 一条「到访」记录。以地级市为最小单位。
///
/// 除了「第一次到访时间」，M1-V1 起还能挂三样东西，都跟着记录一起存：
/// - `note`   故事 / 备注（自由文字）
/// - `tags`   标签（#出差 #独自旅行 …，预设 + 自定义）
/// - `photos` 最多 3 张照片的文件名（图片本体存在沙盒 `photos/` 目录里）
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
    /// 标签（不带 # 前缀，界面自己加）
    var tags: [String]
    /// 心情星级 0–5，0 表示没打分
    var rating: Int
    /// 照片文件名（不含路径），最多 `Theme.Layout.maxPhotosPerCity` 张
    var photos: [String]

    var id: String { code }

    // MARK: - 手写解码：老版本存档没有 tags/rating/photos，要能继续读

    private enum CodingKeys: String, CodingKey {
        case code, cityName, provinceCode, status, firstSeen, lastSeen
        case dayCount, sampleCount, isManual, note, tags, rating, photos
    }

    init(code: String, cityName: String, provinceCode: String, status: VisitStatus,
         firstSeen: Date, lastSeen: Date, dayCount: Int, sampleCount: Int,
         isManual: Bool, note: String, tags: [String] = [], rating: Int = 0,
         photos: [String] = []) {
        self.code = code
        self.cityName = cityName
        self.provinceCode = provinceCode
        self.status = status
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.dayCount = dayCount
        self.sampleCount = sampleCount
        self.isManual = isManual
        self.note = note
        self.tags = tags
        self.rating = rating
        self.photos = photos
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        cityName = try c.decode(String.self, forKey: .cityName)
        provinceCode = try c.decode(String.self, forKey: .provinceCode)
        status = try c.decode(VisitStatus.self, forKey: .status)
        firstSeen = try c.decode(Date.self, forKey: .firstSeen)
        lastSeen = try c.decode(Date.self, forKey: .lastSeen)
        dayCount = try c.decode(Int.self, forKey: .dayCount)
        sampleCount = try c.decode(Int.self, forKey: .sampleCount)
        isManual = try c.decode(Bool.self, forKey: .isManual)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        rating = try c.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        photos = try c.decodeIfPresent([String].self, forKey: .photos) ?? []
    }

    // MARK: - 展示

    var dayText: String { dayCount > 1 ? "\(dayCount) 天" : "1 天" }

    /// 「第一次去」的展示文案（`firstSeen` 就是第一次到访的时间，手动添加时可改）
    var firstVisitText: String {
        firstSeen.formatted(.dateTime.year().month().day())
    }

    var firstVisitYear: String {
        firstSeen.formatted(.dateTime.year())
    }

    var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasNote: Bool { !trimmedNote.isEmpty }

    /// 记录来源：自动（定位）还是手动补记
    var sourceText: String { isManual ? "手动记录" : "定位记录" }

    var photoCount: Int { photos.count }

    var hasPhotos: Bool { !photos.isEmpty }

    var ratingStars: String {
        guard rating > 0 else { return "" }
        return String(repeating: "★", count: min(5, rating))
            + String(repeating: "☆", count: max(0, 5 - rating))
    }

    /// 标签展示用的一行字：`#出差 #独自旅行`
    var tagLine: String {
        tags.map { "#" + $0 }.joined(separator: " ")
    }

    /// 详情里那行小字：首次 + 天数 + 采样 + 来源
    var summaryText: String {
        var parts = ["首次 \(firstVisitText)"]
        if !isManual { parts.append("到访 \(dayText)") }
        if sampleCount > 0 { parts.append("\(sampleCount) 次采样") }
        parts.append(sourceText)
        return parts.joined(separator: " · ")
    }
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

/// 标签预设。用户也可以自己打标签，这里只是常用的一键选择。
enum TagCatalog {
    static let presets = [
        "出差", "独自旅行", "和家人", "和朋友", "蜜月", "徒步",
        "美食", "看展", "演唱会", "中转", "回家", "常住"
    ]

    /// 过滤用户输入：去空白、去 #、去重、限长
    static func normalize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix("#") { text.removeFirst() }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return String(text.prefix(8))
    }
}
