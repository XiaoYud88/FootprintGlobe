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
}
