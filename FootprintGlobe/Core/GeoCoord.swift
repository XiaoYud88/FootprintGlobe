import Foundation
import CoreLocation

/// 一个经纬度点。
///
/// 约定：全 App 内部统一使用 **GCJ-02**（火星坐标），因为离线边界数据来自
/// DataV GeoAtlas，是 GCJ-02。系统定位拿到的是 WGS-84，入口处用
/// `GeoMath.wgs84ToGcj02` 转一次，之后所有判断/绘制都用同一套坐标。
struct GeoCoord: Hashable, Codable {
    var lon: Double
    var lat: Double

    static let chinaCenter = GeoCoord(lon: 104.0, lat: 35.4)

    init(lon: Double, lat: Double) {
        self.lon = lon
        self.lat = lat
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(lon: coordinate.longitude, lat: coordinate.latitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

/// 经纬度包围盒。
struct BBox: Hashable {
    var minLon: Double
    var minLat: Double
    var maxLon: Double
    var maxLat: Double

    init(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
        self.minLon = minLon
        self.minLat = minLat
        self.maxLon = maxLon
        self.maxLat = maxLat
    }

    init(ring: [GeoCoord]) {
        var minLon = Double.greatestFiniteMagnitude
        var minLat = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        for p in ring {
            if p.lon < minLon { minLon = p.lon }
            if p.lon > maxLon { maxLon = p.lon }
            if p.lat < minLat { minLat = p.lat }
            if p.lat > maxLat { maxLat = p.lat }
        }
        self.init(minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat)
    }

    var centerLon: Double { (minLon + maxLon) / 2 }
    var centerLat: Double { (minLat + maxLat) / 2 }

    func contains(_ p: GeoCoord) -> Bool {
        p.lon >= minLon && p.lon <= maxLon && p.lat >= minLat && p.lat <= maxLat
    }

    func intersects(_ other: BBox) -> Bool {
        !(other.minLon > maxLon || other.maxLon < minLon ||
          other.minLat > maxLat || other.maxLat < minLat)
    }

    func expanded(by d: Double) -> BBox {
        BBox(minLon: minLon - d, minLat: minLat - d, maxLon: maxLon + d, maxLat: maxLat + d)
    }
}

enum GeoMath {
    private static let earthRadius = 6_371_000.0

    /// WGS-84 -> GCJ-02。境外坐标原样返回。
    static func wgs84ToGcj02(_ c: GeoCoord) -> GeoCoord {
        if isOutsideChina(c) { return c }
        let dLat = transformLat(x: c.lon - 105.0, y: c.lat - 35.0)
        let dLon = transformLon(x: c.lon - 105.0, y: c.lat - 35.0)
        let radLat = c.lat / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - 0.00669342162296594323 * magic * magic
        let sqrtMagic = sqrt(magic)
        let dLatFinal = (dLat * 180.0) / ((6_378_245.0 * (1 - 0.00669342162296594323)) / (magic * sqrtMagic) * .pi)
        let dLonFinal = (dLon * 180.0) / (6_378_245.0 / sqrtMagic * cos(radLat) * .pi)
        return GeoCoord(lon: c.lon + dLonFinal, lat: c.lat + dLatFinal)
    }

    static func isOutsideChina(_ c: GeoCoord) -> Bool {
        !(c.lon > 73.66 && c.lon < 135.05 && c.lat > 3.86 && c.lat < 53.55)
    }

    private static func transformLat(x: Double, y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * .pi) + 320.0 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLon(x: Double, y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }

    /// 一个环围出来的球面面积（平方公里）。
    ///
    /// 用梯形积分的球面面积公式，对经纬度环直接求和；结果取绝对值，
    /// 所以环的绕向（顺时针/逆时针）不影响结果。用于「点亮面积占比」。
    static func ringAreaKm2(_ ring: [GeoCoord]) -> Double {
        guard ring.count >= 3 else { return 0 }
        let radiusKm = earthRadius / 1000.0
        var total = 0.0
        for i in 0..<ring.count {
            let a = ring[i]
            let b = ring[(i + 1) % ring.count]
            let latA = a.lat * .pi / 180
            let latB = b.lat * .pi / 180
            var dLon = (b.lon - a.lon) * .pi / 180
            // 跨 ±180° 的环先归一化，避免算出整个地球
            if dLon > .pi { dLon -= 2 * .pi }
            if dLon < -.pi { dLon += 2 * .pi }
            total += dLon * (2 + sin(latA) + sin(latB))
        }
        return abs(total * radiusKm * radiusKm / 2)
    }

    /// 两点间球面距离（公里）。
    static func kilometers(_ a: GeoCoord, _ b: GeoCoord) -> Double {
        let dLat = (b.lat - a.lat) / 180.0 * .pi
        let dLon = (b.lon - a.lon) / 180.0 * .pi
        let lat1 = a.lat / 180.0 * .pi
        let lat2 = b.lat / 180.0 * .pi
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h))) / 1000.0
    }
}
