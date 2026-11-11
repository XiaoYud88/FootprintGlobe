import Foundation

/// 一座「极值城市」：最北 / 最南 / 最东 / 最西。
struct ExtremeCity {
    let region: Region
    let visit: Visit
}

/// 省份进度的一行：点亮了几个 / 一共几个。
struct ProvinceProgress: Identifiable {
    let region: Region
    let visited: Int
    let total: Int

    var id: String { region.code }
    var ratio: Double { total > 0 ? Double(visited) / Double(total) : 0 }
    var isFull: Bool { total > 0 && visited == total }
}

/// 一次汇总出来的统计快照。护照页 / 设置页 / 徽章判定都读同一份，避免各处各算一遍。
struct TravelStats {
    var cityCount = 0
    var provinceCount = 0
    var storyCount = 0
    var photoCount = 0
    var tagCount = 0
    var ratedCount = 0
    var wishCount = 0
    var pendingCount = 0

    var north: ExtremeCity?
    var south: ExtremeCity?
    var east: ExtremeCity?
    var west: ExtremeCity?

    var areaKm2: Double = 0
    var totalAreaKm2: Double = 0

    var totalCityCount = 0
    var totalProvinceCount = 0

    /// 已经「全省点亮」的省（该省所有城市都去过）
    var fullProvinces: [Region] = []
    /// 按点亮比例排好序的省，护照页直接展示
    var provinceProgress: [ProvinceProgress] = []

    var earliestYear: Int?
    var latestYear: Int?

    var japanCount = 0
    var chinaCount = 0
    var hasAntarctica = false
    var hasArctic = false

    var areaRatio: Double { totalAreaKm2 > 0 ? min(1, areaKm2 / totalAreaKm2) : 0 }
    var cityRatio: Double {
        totalCityCount > 0 ? Double(cityCount) / Double(totalCityCount) : 0
    }
    var provinceRatio: Double {
        totalProvinceCount > 0 ? Double(provinceCount) / Double(totalProvinceCount) : 0
    }
    var yearSpan: Int {
        guard let a = earliestYear, let b = latestYear else { return 0 }
        return max(0, b - a)
    }

    var areaText: String {
        if areaKm2 >= 10_000 {
            return String(format: "%.1f 万 km²", areaKm2 / 10_000)
        }
        return String(format: "%.0f km²", areaKm2)
    }

    var areaRatioText: String {
        String(format: "%.1f%%", areaRatio * 100)
    }

    @MainActor
    static func make(boundary: BoundaryStore, store: VisitStore) -> TravelStats {
        var stats = TravelStats()
        stats.totalCityCount = boundary.cities.count
        stats.totalProvinceCount = boundary.provinces.count
        stats.wishCount = store.wishlistCodes.count
        stats.pendingCount = store.pendings.count

        var provinceHits: [String: Int] = [:]
        var visitedCities = 0

        for visit in store.visits.values where visit.status == .visited {
            visitedCities += 1
            provinceHits[visit.provinceCode, default: 0] += 1
            if visit.hasNote { stats.storyCount += 1 }
            stats.photoCount += visit.photoCount
            if !visit.tags.isEmpty { stats.tagCount += 1 }
            if visit.rating > 0 { stats.ratedCount += 1 }
            if visit.provinceCode == "JP" { stats.japanCount += 1 }
            else if visit.provinceCode == "AQ" || visit.code == "AQ" { stats.hasAntarctica = true }
            else if visit.provinceCode == "AR" || visit.code == "AR-POLE" { stats.hasArctic = true }
            else { stats.chinaCount += 1 }

            let year = Calendar.current.component(.year, from: visit.firstSeen)
            stats.earliestYear = min(stats.earliestYear ?? year, year)
            stats.latestYear = max(stats.latestYear ?? year, year)

            guard let region = boundary.city(code: visit.code) else { continue }
            let city = ExtremeCity(region: region, visit: visit)
            if stats.north == nil || region.center.lat > stats.north!.region.center.lat { stats.north = city }
            if stats.south == nil || region.center.lat < stats.south!.region.center.lat { stats.south = city }
            if stats.east == nil || region.center.lon > stats.east!.region.center.lon { stats.east = city }
            if stats.west == nil || region.center.lon < stats.west!.region.center.lon { stats.west = city }
        }

        stats.cityCount = visitedCities
        stats.provinceCount = provinceHits.count

        // 面积：只对去过的城市求和（面积有缓存，不会每次重算多边形）
        // 南极、北极不进分子：南极一块就 1200 万 km²，比「中国 + 日本」的分母还大，
        // 一旦去了南极占比会直接跳成 100%，反而看不出真实覆盖度。极地在护照页单独展示。
        var area = 0.0
        for code in store.visitedCodes {
            guard let region = boundary.city(code: code) else { continue }
            guard !BoundaryStore.isPolar(region) else { continue }
            area += boundary.areaKm2(of: region)
        }
        stats.areaKm2 = area
        stats.totalAreaKm2 = boundary.totalAreaKm2

        // 省级进度
        var rows: [ProvinceProgress] = []
        for province in boundary.provincesSorted {
            let total = boundary.cities(of: province.code).count
            let visited = provinceHits[province.code] ?? 0
            rows.append(ProvinceProgress(region: province, visited: visited, total: total))
            if total >= 5, visited == total, let region = boundary.province(code: province.code) {
                stats.fullProvinces.append(region)
            }
        }
        stats.provinceProgress = rows.sorted { a, b in
            if a.ratio == b.ratio { return a.visited > b.visited }
            return a.ratio > b.ratio
        }
        return stats
    }
}

/// 旅行者等级称号：护照页顶部那一行大字。
enum TravelRank {
    static func title(for cityCount: Int) -> String {
        switch cityCount {
        case 0: return "还没出发"
        case 1...2: return "启程者"
        case 3...9: return "旅人"
        case 10...24: return "行者"
        case 25...49: return "远行者"
        case 50...99: return "游侠"
        case 100...199: return "旅行家"
        default: return "大地行者"
        }
    }

    static func nextThreshold(for cityCount: Int) -> Int? {
        [1, 3, 10, 25, 50, 100, 200].first { $0 > cityCount }
    }
}

// MARK: - 徽章

enum BadgeKind: Equatable {
    case cities(Int)
    case provinces(Int)
    case allProvinces
    case stories(Int)
    case photos(Int)
    case tags(Int)
    case fullProvince
    case north, south, east, west
    case japan
    case antarctica
    case arctic
    case spanYears(Int)
}

struct BadgeDefinition: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let tier: Int        // 1 铜 / 2 银 / 3 金
    let kind: BadgeKind
}

struct BadgeState: Identifiable {
    let definition: BadgeDefinition
    let unlocked: Bool
    let progress: Double
    let progressText: String

    var id: String { definition.id }
}

enum BadgeCatalog {
    static let all: [BadgeDefinition] = [
        // 城市数
        BadgeDefinition(id: "city-1", title: "第一步", detail: "记录第 1 个城市",
                        symbol: "figure.walk", tier: 1, kind: .cities(1)),
        BadgeDefinition(id: "city-5", title: "初上路", detail: "点亮 5 个城市",
                        symbol: "signpost.right", tier: 1, kind: .cities(5)),
        BadgeDefinition(id: "city-10", title: "十城", detail: "点亮 10 个城市",
                        symbol: "10.circle.fill", tier: 2, kind: .cities(10)),
        BadgeDefinition(id: "city-25", title: "四方行客", detail: "点亮 25 个城市",
                        symbol: "square.grid.2x2.fill", tier: 2, kind: .cities(25)),
        BadgeDefinition(id: "city-50", title: "半百之城", detail: "点亮 50 个城市",
                        symbol: "50.circle.fill", tier: 3, kind: .cities(50)),
        BadgeDefinition(id: "city-100", title: "百城", detail: "点亮 100 个城市",
                        symbol: "crown.fill", tier: 3, kind: .cities(100)),
        BadgeDefinition(id: "city-200", title: "行遍中国", detail: "点亮 200 个城市",
                        symbol: "flame.fill", tier: 3, kind: .cities(200)),
        // 省份
        BadgeDefinition(id: "prov-1", title: "初见省域", detail: "点亮 1 个省级行政区",
                        symbol: "map", tier: 1, kind: .provinces(1)),
        BadgeDefinition(id: "prov-5", title: "五省通", detail: "点亮 5 个省级行政区",
                        symbol: "map.fill", tier: 1, kind: .provinces(5)),
        BadgeDefinition(id: "prov-10", title: "十省", detail: "点亮 10 个省级行政区",
                        symbol: "10.square.fill", tier: 2, kind: .provinces(10)),
        BadgeDefinition(id: "prov-20", title: "廿省", detail: "点亮 20 个省级行政区",
                        symbol: "20.square.fill", tier: 2, kind: .provinces(20)),
        BadgeDefinition(id: "prov-30", title: "三十省", detail: "点亮 30 个省级行政区",
                        symbol: "30.square.fill", tier: 3, kind: .provinces(30)),
        BadgeDefinition(id: "prov-all", title: "全域点亮", detail: "点亮全部省级行政区",
                        symbol: "star.circle.fill", tier: 3, kind: .allProvinces),
        // 故事 / 照片 / 标签
        BadgeDefinition(id: "story-1", title: "第一个故事", detail: "给 1 个城市写下故事",
                        symbol: "text.book.closed", tier: 1, kind: .stories(1)),
        BadgeDefinition(id: "story-5", title: "会讲故事", detail: "给 5 个城市写下故事",
                        symbol: "text.book.closed.fill", tier: 2, kind: .stories(5)),
        BadgeDefinition(id: "story-20", title: "旅行作家", detail: "给 20 个城市写下故事",
                        symbol: "pencil.and.scribble", tier: 3, kind: .stories(20)),
        BadgeDefinition(id: "story-50", title: "人生手记", detail: "给 50 个城市写下故事",
                        symbol: "books.vertical.fill", tier: 3, kind: .stories(50)),
        BadgeDefinition(id: "photo-1", title: "第一张照片", detail: "给城市添 1 张照片",
                        symbol: "photo", tier: 1, kind: .photos(1)),
        BadgeDefinition(id: "photo-10", title: "十张定格", detail: "累计添加 10 张照片",
                        symbol: "photo.stack", tier: 2, kind: .photos(10)),
        BadgeDefinition(id: "photo-50", title: "影集", detail: "累计添加 50 张照片",
                        symbol: "photo.stack.fill", tier: 3, kind: .photos(50)),
        BadgeDefinition(id: "tag-1", title: "贴标签的人", detail: "给 1 个城市打标签",
                        symbol: "tag", tier: 1, kind: .tags(1)),
        BadgeDefinition(id: "tag-5", title: "分类学家", detail: "给 5 个城市打标签",
                        symbol: "tag.fill", tier: 2, kind: .tags(5)),
        // 特殊
        BadgeDefinition(id: "north", title: "极北之地", detail: "到过北纬 49° 以北的城市",
                        symbol: "snowflake", tier: 2, kind: .north),
        BadgeDefinition(id: "south", title: "南国之南", detail: "到过北纬 20° 以南的城市",
                        symbol: "sun.max.fill", tier: 2, kind: .south),
        BadgeDefinition(id: "east", title: "东方第一", detail: "到过东经 130° 以东的城市",
                        symbol: "sunrise.fill", tier: 2, kind: .east),
        BadgeDefinition(id: "west", title: "西域远行", detail: "到过东经 80° 以西的城市",
                        symbol: "mountain.2.fill", tier: 2, kind: .west),
        BadgeDefinition(id: "japan", title: "一水之隔", detail: "点亮任意一个日本城市",
                        symbol: "sailboat.fill", tier: 2, kind: .japan),
        BadgeDefinition(id: "antarctica", title: "第七大陆", detail: "记录南极洲",
                        symbol: "pawprint.fill", tier: 3, kind: .antarctica),
        BadgeDefinition(id: "arctic", title: "极夜之光", detail: "记录北极地区",
                        symbol: "moon.stars.fill", tier: 3, kind: .arctic),
        BadgeDefinition(id: "span-5", title: "五年之约", detail: "记录跨度满 5 年",
                        symbol: "calendar", tier: 2, kind: .spanYears(5)),
        BadgeDefinition(id: "span-10", title: "十年足迹", detail: "记录跨度满 10 年",
                        symbol: "calendar.badge.clock", tier: 3, kind: .spanYears(10)),
        BadgeDefinition(id: "full-prov", title: "全省点亮", detail: "把某个省的城市全部走完",
                        symbol: "checkmark.seal.fill", tier: 3, kind: .fullProvince)
    ]

    static let total = all.count

    /// 把统计快照算成徽章状态列表。视图只管画，判定逻辑都在这里。
    static func evaluate(_ s: TravelStats) -> [BadgeState] {
        all.map { def in
            let r = measure(def.kind, s)
            return BadgeState(definition: def, unlocked: r.done,
                              progress: r.value, progressText: r.text)
        }
    }

    static func unlockedCount(_ s: TravelStats) -> Int {
        all.reduce(0) { $0 + (measure($1.kind, s).done ? 1 : 0) }
    }

    private struct Measure {
        let done: Bool
        let value: Double
        let text: String
    }

    private static func step(_ current: Int, _ target: Int, _ label: String) -> Measure {
        Measure(done: current >= target,
                value: target > 0 ? min(1, Double(current) / Double(target)) : 1,
                text: "\(min(current, target))/\(target) \(label)")
    }

    private static func measure(_ kind: BadgeKind, _ s: TravelStats) -> Measure {
        switch kind {
        case .cities(let n): return step(s.cityCount, n, "城市")
        case .provinces(let n): return step(s.provinceCount, n, "省级")
        case .allProvinces: return step(s.provinceCount, max(1, s.totalProvinceCount), "省级")
        case .stories(let n): return step(s.storyCount, n, "故事")
        case .photos(let n): return step(s.photoCount, n, "张照片")
        case .tags(let n): return step(s.tagCount, n, "城市带标签")
        case .spanYears(let n):
            return Measure(done: s.yearSpan >= n,
                           value: n > 0 ? min(1, Double(s.yearSpan) / Double(n)) : 1,
                           text: "\(min(s.yearSpan, n))/\(n) 年")
        case .fullProvince:
            return Measure(done: !s.fullProvinces.isEmpty,
                           value: s.fullProvinces.isEmpty ? 0 : 1,
                           text: s.fullProvinces.isEmpty ? "还没走完一个省" : "已走完 \(s.fullProvinces.count) 个省")
        case .north:
            let lat = s.north?.region.center.lat ?? 0
            return Measure(done: lat >= 49, value: min(1, max(0, (lat - 30) / 19)),
                           text: s.north.map { String(format: "最北 %.1f°N", $0.region.center.lat) } ?? "还没有记录")
        case .south:
            let lat = s.south?.region.center.lat ?? 90
            return Measure(done: (s.south != nil) && lat <= 20,
                           value: s.south == nil ? 0 : min(1, max(0, (30 - lat) / 10)),
                           text: s.south.map { String(format: "最南 %.1f°N", $0.region.center.lat) } ?? "还没有记录")
        case .east:
            let lon = s.east?.region.center.lon ?? 0
            return Measure(done: lon >= 130, value: min(1, max(0, (lon - 110) / 20)),
                           text: s.east.map { String(format: "最东 %.1f°E", $0.region.center.lon) } ?? "还没有记录")
        case .west:
            let lon = s.west?.region.center.lon ?? 180
            return Measure(done: (s.west != nil) && lon <= 80,
                           value: s.west == nil ? 0 : min(1, max(0, (100 - lon) / 20)),
                           text: s.west.map { String(format: "最西 %.1f°E", $0.region.center.lon) } ?? "还没有记录")
        case .japan:
            return Measure(done: s.japanCount > 0, value: s.japanCount > 0 ? 1 : 0,
                           text: s.japanCount > 0 ? "日本 \(s.japanCount) 城" : "还没记录日本")
        case .antarctica:
            return Measure(done: s.hasAntarctica, value: s.hasAntarctica ? 1 : 0,
                           text: s.hasAntarctica ? "已记录" : "还没记录")
        case .arctic:
            return Measure(done: s.hasArctic, value: s.hasArctic ? 1 : 0,
                           text: s.hasArctic ? "已记录" : "还没记录")
        }
    }
}
