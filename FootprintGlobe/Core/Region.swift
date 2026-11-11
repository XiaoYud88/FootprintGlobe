import Foundation
import SwiftUI

enum RegionLevel: String, Hashable {
    case province
    case city
}

/// 一个行政区（省 或 地级市），带一份预先生成的绘制路径。
///
/// `path` 的坐标是「世界坐标」：x = 经度，y = -纬度。
/// 绘制时用 `CGAffineTransform` 把它映射到屏幕，这样平移/缩放不用重建路径。
struct Region: Identifiable {
    let code: String
    let name: String
    let provinceCode: String
    let level: RegionLevel
    let rings: [[GeoCoord]]
    let bounds: BBox
    let center: GeoCoord
    let path: Path

    var id: String { code }

    /// 城市去掉末尾「市」，用于密集区域显示更短的标签。
    var shortName: String {
        guard level == .city else { return name }
        if name.hasSuffix("市") { return String(name.dropLast()) }
        return name
    }

    init(code: String, name: String, provinceCode: String, level: RegionLevel,
         rings: [[GeoCoord]], center: GeoCoord?) {
        self.code = code
        self.name = name
        self.provinceCode = provinceCode
        self.level = level
        self.rings = rings

        var box = BBox(ring: rings.first ?? [])
        for ring in rings.dropFirst() {
            let b = BBox(ring: ring)
            box = BBox(minLon: min(box.minLon, b.minLon), minLat: min(box.minLat, b.minLat),
                       maxLon: max(box.maxLon, b.maxLon), maxLat: max(box.maxLat, b.maxLat))
        }
        self.bounds = box
        self.center = center ?? GeoCoord(lon: box.centerLon, lat: box.centerLat)
        self.path = Region.makePath(rings: rings, stride: 1)
    }

    private static func makePath(rings: [[GeoCoord]], stride: Int) -> Path {
        var path = Path()
        for ring in rings {
            guard ring.count >= 3 else { continue }
            path.move(to: worldPoint(ring[0]))
            var i = stride
            while i < ring.count {
                path.addLine(to: worldPoint(ring[i]))
                i += stride
            }
            // 补齐最后一个点，避免轮廓缺角
            if let last = ring.last {
                path.addLine(to: worldPoint(last))
            }
            path.closeSubpath()
        }
        return path
    }

    private static func worldPoint(_ p: GeoCoord) -> CGPoint {
        CGPoint(x: p.lon, y: -p.lat)
    }
}

extension Region: Equatable {
    static func == (lhs: Region, rhs: Region) -> Bool { lhs.code == rhs.code }
}

extension Region: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(code) }
}

/// 点在多边形内判定（射线法）。
enum PolygonTest {
    static func contains(rings: [[GeoCoord]], point p: GeoCoord) -> Bool {
        for ring in rings where rayCast(ring, p) {
            return true
        }
        return false
    }

    static func rayCast(_ ring: [GeoCoord], _ p: GeoCoord) -> Bool {
        let n = ring.count
        guard n >= 3 else { return false }
        var inside = false
        var j = n - 1
        for i in 0..<n {
            let a = ring[i]
            let b = ring[j]
            if (a.lat > p.lat) != (b.lat > p.lat) {
                let t = (p.lat - a.lat) / (b.lat - a.lat)
                let x = a.lon + t * (b.lon - a.lon)
                if p.lon < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}

/// 用 0.5° 网格给城市建空间索引，避免每次判定都遍历 370 个多边形。
final class CityGridIndex {
    private let cellSize = 0.5
    private let originLon = 70.0
    private let originLat = 0.0
    private var buckets: [Int64: [String]] = [:]

    init(regions: [Region]) {
        for r in regions {
            let box = r.bounds.expanded(by: 0.05)
            let x0 = gridX(box.minLon), x1 = gridX(box.maxLon)
            let y0 = gridY(box.minLat), y1 = gridY(box.maxLat)
            for y in y0...y1 {
                for x in x0...x1 {
                    buckets[key(x, y), default: []].append(r.code)
                }
            }
        }
    }

    func candidates(lon: Double, lat: Double) -> [String] {
        buckets[key(gridX(lon), gridY(lat))] ?? []
    }

    private func gridX(_ lon: Double) -> Int { Int(floor((lon - originLon) / cellSize)) }
    private func gridY(_ lat: Double) -> Int { Int(floor((lat - originLat) / cellSize)) }
    private func key(_ x: Int, _ y: Int) -> Int64 {
        Int64(y &* 4_000) &+ Int64(x &+ 1_000)
    }
}
