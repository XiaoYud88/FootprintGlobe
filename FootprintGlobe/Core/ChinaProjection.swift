import Foundation
import CoreGraphics

/// 中国平面图投影：等距圆柱 + 纬度修正。
///
/// 世界坐标约定是 `(x = 经度, y = -纬度)`（`Region.path` 就是这么生成的），
/// 所以屏幕 y 的换算必须是 `y' = -ky·(-lat) + ty = ky·lat + ty`。
/// 这里把投影单独抽出来，好处是：地图绘制、点击命中、以及离线冒烟测试
/// 用的是同一份公式，不会再出现「某一处写反了但只有真机才看得出来」。
struct ChinaProjection {
    let size: CGSize
    let center: GeoCoord
    let lonSpan: Double
    /// 每 1° 经度对应的水平点数
    let k: Double
    /// 每 1° 纬度对应的垂直点数（按当前中心纬度做 cos 修正）
    let ky: Double

    init(size: CGSize, center: GeoCoord, lonSpan: Double) {
        let span = max(lonSpan, 0.05)
        let pointsPerLon = Double(size.width) / span
        let pointsPerLat = pointsPerLon / max(0.25, cos(center.lat * .pi / 180))
        self.size = size
        self.center = center
        self.lonSpan = span
        self.k = pointsPerLon
        self.ky = pointsPerLat
    }

    /// 世界坐标 → 屏幕坐标
    var affine: CGAffineTransform {
        CGAffineTransform(a: CGFloat(k), b: 0, c: 0, d: CGFloat(ky),
                          tx: CGFloat(Double(size.width) / 2 - center.lon * k),
                          ty: CGFloat(Double(size.height) / 2 + center.lat * ky))
    }

    /// 屏幕内可见的经纬度范围，用于裁剪绘制对象
    var visibleBox: BBox {
        let latSpan = Double(size.height) / ky
        return BBox(minLon: center.lon - lonSpan / 2, minLat: center.lat - latSpan / 2,
                    maxLon: center.lon + lonSpan / 2, maxLat: center.lat + latSpan / 2)
    }

    func screenPoint(_ coord: GeoCoord) -> CGPoint {
        CGPoint(x: coord.lon, y: -coord.lat).applying(affine)
    }

    /// 屏幕点 → 经纬度（给以后点击城市用）
    func coord(at point: CGPoint) -> GeoCoord {
        GeoCoord(lon: center.lon + (Double(point.x) - Double(size.width) / 2) / k,
                 lat: center.lat - (Double(point.y) - Double(size.height) / 2) / ky)
    }
}
