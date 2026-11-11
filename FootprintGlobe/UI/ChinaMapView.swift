import SwiftUI

/// 中国平面图（等距圆柱投影 + 纬度修正），按缩放分三层：
/// 国家级（省轮廓）→ 省级（市轮廓）→ 市级（市名 + 去过的市最明显）。
struct ChinaMapView: View {
    let center: GeoCoord
    let lonSpan: Double
    let detail: DetailLevel
    let provinces: [Region]
    let cities: [Region]
    let visitedCityCodes: Set<String>
    let wishlistCityCodes: Set<String>
    let pendingCityCodes: Set<String>
    let visitedProvinceCodes: Set<String>
    let focus: GeoCoord?

    var body: some View {
        Canvas { context, size in
            draw(in: context, size: size)
        }
        .accessibilityLabel("中国地图")
    }

    // MARK: - 投影

    private func transform(for size: CGSize) -> CGAffineTransform {
        let k = Double(size.width) / max(lonSpan, 0.05)
        let ky = k / max(0.25, cos(center.lat * .pi / 180))
        return CGAffineTransform(a: CGFloat(k), b: 0, c: 0, d: CGFloat(-ky),
                                 tx: CGFloat(Double(size.width) / 2 - center.lon * k),
                                 ty: CGFloat(Double(size.height) / 2 + center.lat * ky))
    }

    private func visibleBox(for size: CGSize) -> BBox {
        let k = Double(size.width) / max(lonSpan, 0.05)
        let ky = k / max(0.25, cos(center.lat * .pi / 180))
        let latSpan = Double(size.height) / ky
        return BBox(minLon: center.lon - lonSpan / 2, minLat: center.lat - latSpan / 2,
                    maxLon: center.lon + lonSpan / 2, maxLat: center.lat + latSpan / 2)
    }

    private func screenPoint(_ coord: GeoCoord, _ t: CGAffineTransform) -> CGPoint {
        CGPoint(x: coord.lon, y: -coord.lat).applying(t)
    }

    // MARK: - 绘制

    private func draw(in context: GraphicsContext, size: CGSize) {
        let t = transform(for: size)
        let visible = visibleBox(for: size)
        let activeProvinces = provinces.filter { $0.bounds.intersects(visible) }
        let activeCities = cities.filter { $0.bounds.intersects(visible) }

        // 1. 陆地底色
        var base = Path()
        for province in activeProvinces { base.addPath(province.path) }
        context.fill(base.applying(t), with: .color(Theme.land))

        // 2. 去过的省：国家级时最重，往里缩时退成淡底
        var visitedProvinces = Path()
        for province in activeProvinces where visitedProvinceCodes.contains(province.code) {
            visitedProvinces.addPath(province.path)
        }
        context.fill(visitedProvinces.applying(t),
                     with: .color(Theme.brand.opacity(detail == .country ? 0.52 : 0.12)))

        // 3. 市一级：边界 / 去过的市 / 想去 / 待确认
        if detail != .country {
            var cityBorders = Path()
            for city in activeCities { cityBorders.addPath(city.path) }
            context.stroke(cityBorders.applying(t),
                           with: .color(Theme.border.opacity(detail == .city ? 0.42 : 0.20)),
                           lineWidth: detail == .city ? 0.7 : 0.4)

            var visitedFill = Path()
            var wishFill = Path()
            var pendingFill = Path()
            var hasWish = false
            var hasPending = false
            var hasVisited = false
            for city in activeCities {
                if visitedCityCodes.contains(city.code) {
                    visitedFill.addPath(city.path)
                    hasVisited = true
                } else if wishlistCityCodes.contains(city.code) {
                    wishFill.addPath(city.path)
                    hasWish = true
                } else if pendingCityCodes.contains(city.code) {
                    pendingFill.addPath(city.path)
                    hasPending = true
                }
            }
            if hasWish {
                context.fill(wishFill.applying(t), with: .color(Theme.wish.opacity(0.16)))
                context.stroke(wishFill.applying(t), with: .color(Theme.wish.opacity(0.75)),
                               style: StrokeStyle(lineWidth: 0.9, dash: [3, 2.5]))
            }
            if hasPending {
                context.fill(pendingFill.applying(t), with: .color(Theme.pending.opacity(0.14)))
                context.stroke(pendingFill.applying(t), with: .color(Theme.pending.opacity(0.9)),
                               style: StrokeStyle(lineWidth: 1.0, dash: [3, 2.5]))
            }
            if hasVisited {
                context.fill(visitedFill.applying(t), with: .color(Theme.brand.opacity(0.34)))
                context.stroke(visitedFill.applying(t), with: .color(Theme.brand.opacity(0.95)),
                               lineWidth: detail == .city ? 1.3 : 1.0)
            }
        }

        // 4. 省界压在最上层
        var provinceBorders = Path()
        for province in activeProvinces { provinceBorders.addPath(province.path) }
        context.stroke(provinceBorders.applying(t),
                       with: .color(Theme.border.opacity(detail == .country ? 0.55 : 0.70)),
                       lineWidth: detail == .country ? 0.6 : 0.8)

        // 5. 文字
        drawLabels(in: context, t: t, size: size, provinces: activeProvinces, cities: activeCities)

        // 6. 我的位置
        drawFocus(in: context, t: t)
    }

    private func drawLabels(in context: GraphicsContext, t: CGAffineTransform, size: CGSize,
                            provinces: [Region], cities: [Region]) {
        var occupied: [CGRect] = []

        func place(_ text: String, at point: CGPoint, fontSize: CGFloat,
                   color: Color, weight: Font.Weight = .medium) {
            guard point.x > 0, point.x < size.width, point.y > 0, point.y < size.height else { return }
            let estimated = CGSize(width: CGFloat(text.count) * fontSize * 1.02,
                                   height: fontSize * 1.25)
            let rect = CGRect(x: point.x - estimated.width / 2,
                              y: point.y - estimated.height / 2,
                              width: estimated.width, height: estimated.height)
            if occupied.contains(where: { $0.intersects(rect) }) { return }
            occupied.append(rect)
            context.draw(Text(text)
                            .font(.system(size: fontSize, weight: weight, design: .rounded))
                            .foregroundStyle(color),
                         at: point)
        }

        // 省名
        if detail != .city {
            for province in provinces {
                let short = province.name
                    .replacingOccurrences(of: "省", with: "")
                    .replacingOccurrences(of: "自治区", with: "")
                    .replacingOccurrences(of: "维吾尔", with: "")
                    .replacingOccurrences(of: "壮族", with: "")
                    .replacingOccurrences(of: "回族", with: "")
                    .replacingOccurrences(of: "特别行政区", with: "")
                let tappable = visitedProvinceCodes.contains(province.code)
                place(short, at: screenPoint(province.center, t), fontSize: 10.5,
                      color: tappable ? Theme.brandLight : Theme.textSecondary,
                      weight: tappable ? .semibold : .medium)
            }
        }

        // 市名：去过 / 想去的优先
        if detail != .city {
            for city in cities where visitedCityCodes.contains(city.code) {
                place(city.shortName, at: screenPoint(city.center, t), fontSize: 9,
                      color: Theme.brandLight, weight: .semibold)
            }
        } else {
            for city in cities where visitedCityCodes.contains(city.code) {
                place(city.shortName, at: screenPoint(city.center, t), fontSize: 10,
                      color: Theme.brandLight, weight: .semibold)
            }
            for city in cities where wishlistCityCodes.contains(city.code) {
                place(city.shortName, at: screenPoint(city.center, t), fontSize: 9,
                      color: Theme.wish, weight: .medium)
            }
            for city in cities where pendingCityCodes.contains(city.code) {
                place(city.shortName, at: screenPoint(city.center, t), fontSize: 9,
                      color: Theme.pending, weight: .semibold)
            }
            for city in cities {
                if visitedCityCodes.contains(city.code) || wishlistCityCodes.contains(city.code)
                    || pendingCityCodes.contains(city.code) { continue }
                place(city.shortName, at: screenPoint(city.center, t), fontSize: 8.5,
                      color: Theme.textTertiary, weight: .regular)
            }
        }
    }

    private func drawFocus(in context: GraphicsContext, t: CGAffineTransform) {
        guard let focus else { return }
        let point = screenPoint(focus, t)
        guard point.x.isFinite, point.y.isFinite else { return }
        let halo = Path(ellipseIn: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18))
        context.stroke(halo, with: .color(.white.opacity(0.35)), lineWidth: 1)
        let dot = Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
        context.fill(dot, with: .color(.white))
    }
}
