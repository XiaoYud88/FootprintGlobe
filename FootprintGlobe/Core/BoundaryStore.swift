import Foundation
import OSLog

/// 离线行政边界仓库。数据来自随包携带的 `boundaries.json`（DataV GeoAtlas，GCJ-02）。
final class BoundaryStore {
    static let shared = BoundaryStore()

    private(set) var provinces: [Region] = []
    private(set) var cities: [Region] = []
    private(set) var cityByCode: [String: Region] = [:]
    private(set) var provinceByCode: [String: Region] = [:]
    private(set) var citiesByProvince: [String: [Region]] = [:]
    private(set) var loadError: String?

    private var index: CityGridIndex
    private let log = Logger(subsystem: "com.personal.footprintglobe", category: "boundary")

    // MARK: - 大洲常量

    static let japanCode = "JP"
    static let antarcticaCode = "AQ"
    /// 北极没有陆地边界，用一个覆盖极点的小圆帽当「虚拟行政区」，只为了能记录、能点亮。
    static let arcticProvinceCode = "AR"
    static let arcticCityCode = "AR-POLE"

    /// 面积缓存：环形积分的开销不小，算一次就存住
    private var areaCache: [String: Double] = [:]
    private var cachedTotalArea: Double?

    private struct Payload: Decodable {
        struct RawProvince: Decodable {
            let code: String
            let name: String
            let rings: [[[Double]]]
            let center: [Double]?
        }
        struct RawCity: Decodable {
            let code: String
            let name: String
            let provinceCode: String
            let rings: [[[Double]]]
            let center: [Double]?
        }
        let provinces: [RawProvince]
        let cities: [RawCity]
    }

    private init() {
        index = CityGridIndex(regions: [])
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "boundaries", withExtension: "json") else {
            loadError = "找不到 boundaries.json"
            log.error("boundaries.json missing from bundle")
            return
        }
        let started = Date()
        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(Payload.self, from: data)

            provinces = payload.provinces.compactMap { raw in
                let rings = BoundaryStore.toRings(raw.rings)
                guard !rings.isEmpty else { return nil }
                return Region(code: raw.code, name: raw.name, provinceCode: raw.code,
                              level: .province, rings: rings,
                              center: BoundaryStore.toCoord(raw.center))
            }
            cities = payload.cities.compactMap { raw in
                let rings = BoundaryStore.toRings(raw.rings)
                guard !rings.isEmpty else { return nil }
                return Region(code: raw.code, name: raw.name, provinceCode: raw.provinceCode,
                              level: .city, rings: rings,
                              center: BoundaryStore.toCoord(raw.center))
            }
            appendArctic()
            cityByCode = cities.reduce(into: [:]) { $0[$1.code] = $1 }
            provinceByCode = provinces.reduce(into: [:]) { $0[$1.code] = $1 }
            citiesByProvince = Dictionary(grouping: cities, by: { $0.provinceCode })
            index = CityGridIndex(regions: cities)

            let ms = Int(Date().timeIntervalSince(started) * 1000)
            log.info("loaded \(self.provinces.count) provinces, \(self.cities.count) cities in \(ms)ms")
        } catch {
            loadError = "边界数据解析失败：\(error.localizedDescription)"
            log.error("decode failed: \(error.localizedDescription)")
        }
    }

    /// 北极没有国籍、没有行政边界，但用户想看它。
    /// 这里合成一个覆盖极点附近的小圆帽：能画、能点、能手动记录，不影响定位判定。
    private func appendArctic() {
        guard provinceByCode[BoundaryStore.arcticProvinceCode] == nil else { return }
        let cap = BoundaryStore.polarCap(centerLon: 15, latFrom: 84.0, latTo: 89.6, lonRadius: 16)
        let province = Region(code: BoundaryStore.arcticProvinceCode, name: "北极地区",
                              provinceCode: BoundaryStore.arcticProvinceCode,
                              level: .province, rings: [cap],
                              center: GeoCoord(lon: 15, lat: 88))
        let city = Region(code: BoundaryStore.arcticCityCode, name: "北极点",
                          provinceCode: BoundaryStore.arcticProvinceCode,
                          level: .city, rings: [cap],
                          center: GeoCoord(lon: 15, lat: 88))
        provinces.append(province)
        cities.append(city)
    }

    /// 极地小圆帽：一个不跨 ±180° 的近似多边形。
    private static func polarCap(centerLon: Double, latFrom: Double,
                                 latTo: Double, lonRadius: Double) -> [GeoCoord] {
        var ring: [GeoCoord] = []
        let steps = 24
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2 * .pi
            ring.append(GeoCoord(lon: centerLon + cos(t) * lonRadius,
                                 lat: latFrom + (latTo - latFrom) * 0.5 + sin(t) * (latTo - latFrom) * 0.5))
        }
        return ring
    }

    private static func toRings(_ raw: [[[Double]]]) -> [[GeoCoord]] {
        raw.compactMap { ring in
            guard ring.count >= 3 else { return nil }
            return ring.map { GeoCoord(lon: $0[0], lat: $0[1]) }
        }
    }

    private static func toCoord(_ raw: [Double]?) -> GeoCoord? {
        guard let raw = raw, raw.count >= 2 else { return nil }
        return GeoCoord(lon: raw[0], lat: raw[1])
    }

    // MARK: - 查询

    var cityCount: Int { cities.count }
    var provinceCount: Int { provinces.count }

    func city(code: String) -> Region? { cityByCode[code] }
    func province(code: String) -> Region? { provinceByCode[code] }
    func cities(of provinceCode: String) -> [Region] { citiesByProvince[provinceCode] ?? [] }

    /// 点落在哪个地级市里（GCJ-02 输入）。
    func city(containing coord: GeoCoord) -> Region? {
        for code in index.candidates(lon: coord.lon, lat: coord.lat) {
            guard let region = cityByCode[code] else { continue }
            guard region.bounds.contains(coord) else { continue }
            if PolygonTest.contains(rings: region.rings, point: coord) {
                return region
            }
        }
        return nil
    }

    func province(of city: Region) -> Region? { provinceByCode[city.provinceCode] }

    /// 全部省按行政区划代码排序，用于列表展示。
    var provincesSorted: [Region] {
        provinces.sorted { $0.code < $1.code }
    }

    // MARK: - 面积

    /// 一个行政区所有环围出来的球面面积（km²），按 code 缓存。
    func areaKm2(of region: Region) -> Double {
        if let cached = areaCache[region.code] { return cached }
        var total = 0.0
        for ring in region.rings { total += GeoMath.ringAreaKm2(ring) }
        areaCache[region.code] = total
        return total
    }

    /// 可点亮面积合计 = 中国 + 日本。
    ///
    /// 南极洲单块 1400 万 km²，放进来会让「面积占比」一跳就是一个大陆，失去意义，
    /// 所以分母只算中国和日本；南极、北极在护照页单独成行展示。
    var totalAreaKm2: Double {
        if let cached = cachedTotalArea { return cached }
        var total = 0.0
        for region in cities where !BoundaryStore.isPolar(region) {
            total += areaKm2(of: region)
        }
        cachedTotalArea = total
        return total
    }

    static func isPolar(_ region: Region) -> Bool {
        region.provinceCode == antarcticaCode
            || region.provinceCode == arcticProvinceCode
            || region.code == antarcticaCode
    }

    // MARK: - 分组（中国 / 日本 / 极地）

    var chinaProvinces: [Region] {
        provincesSorted.filter { $0.code != BoundaryStore.japanCode
            && $0.code != BoundaryStore.antarcticaCode
            && $0.code != BoundaryStore.arcticProvinceCode }
    }

    var japanProvince: Region? { provinceByCode[BoundaryStore.japanCode] }
    var antarcticaProvince: Region? { provinceByCode[BoundaryStore.antarcticaCode] }
    var arcticProvince: Region? { provinceByCode[BoundaryStore.arcticProvinceCode] }

    var antarcticaCity: Region? { cityByCode[BoundaryStore.antarcticaCode] }
    var arcticCity: Region? { cityByCode[BoundaryStore.arcticCityCode] }

    /// 日文县名太长（「北海道」「青森県」已经最短），这里只把「県/都/府」尾巴去掉，
    /// 让地图上的标签和中文省名一样短。
    var japanCities: [Region] { cities(of: BoundaryStore.japanCode) }

    /// 一个省的归属大洲名，护照页和列表分组用。
    func areaTitle(of province: Region) -> String {
        switch province.code {
        case BoundaryStore.japanCode: return "日本"
        case BoundaryStore.antarcticaCode: return "南极洲"
        case BoundaryStore.arcticProvinceCode: return "北极"
        default: return "中国"
        }
    }

    func isJapan(_ code: String) -> Bool { code.hasPrefix(BoundaryStore.japanCode + "-") }
}
