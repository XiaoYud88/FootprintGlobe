import Foundation
import OSLog

/// 地球背景用的世界陆地轮廓（不含中国的省市细节，只是「这个世界长什么样」）。
///
/// 数据来自 Natural Earth 1:50m 国界，已简化到 0.22°、丢掉小于 0.5° 的碎岛，
/// 打包后约 180 KB / 1 万点，只在自绘地球上画一层暗色陆地。
struct WorldCountry: Identifiable {
    let code: String
    let name: String
    let rings: [[GeoCoord]]
    let bounds: BBox

    var id: String { code }
}

final class WorldStore {
    static let shared = WorldStore()

    private(set) var countries: [WorldCountry] = []
    private(set) var loadError: String?
    private var didLoad = false

    private let log = Logger(subsystem: "com.personal.footprintglobe", category: "world")

    private struct Payload: Decodable {
        struct RawCountry: Decodable {
            let code: String
            let name: String
            let rings: [[[Double]]]
        }
        let countries: [RawCountry]
    }

    /// 懒加载：只有真的要画地球时才解析。
    func loadIfNeeded() -> [WorldCountry] {
        guard !didLoad else { return countries }
        didLoad = true

        guard let url = Bundle.main.url(forResource: "world", withExtension: "json") else {
            loadError = "找不到 world.json"
            log.error("world.json missing from bundle")
            return countries
        }
        let started = Date()
        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            countries = payload.countries.compactMap { raw in
                let rings = raw.rings.compactMap { ring -> [GeoCoord]? in
                    guard ring.count >= 4 else { return nil }
                    return ring.map { GeoCoord(lon: $0[0], lat: $0[1]) }
                }
                guard !rings.isEmpty else { return nil }
                var box = BBox(ring: rings[0])
                for ring in rings.dropFirst() {
                    let b = BBox(ring: ring)
                    box = BBox(minLon: min(box.minLon, b.minLon), minLat: min(box.minLat, b.minLat),
                               maxLon: max(box.maxLon, b.maxLon), maxLat: max(box.maxLat, b.maxLat))
                }
                return WorldCountry(code: raw.code, name: raw.name, rings: rings, bounds: box)
            }
            let points = countries.reduce(0) { $0 + $1.rings.reduce(0) { $0 + $1.count } }
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            log.info("loaded \(self.countries.count) countries / \(points) pts in \(ms)ms")
            return countries
        } catch {
            loadError = "世界轮廓解析失败：\(error.localizedDescription)"
            log.error("world decode failed: \(error.localizedDescription)")
            return countries
        }
    }
}
