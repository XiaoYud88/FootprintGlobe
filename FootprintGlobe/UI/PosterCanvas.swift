import UIKit

/// 足迹海报，用纯 Core Graphics 画。
///
/// 之前两版都是用 `ImageRenderer` 去渲染一个 SwiftUI 视图，问题是那套视图里塞了
/// `Canvas`（地球）+ `GeometryReader`（进度条）+ `.blur` 滤镜，`ImageRenderer` 对这三样
/// 都不太稳：要么渲出一张空白图（正是用户看到的「一片灰」），要么在主线程卡好几秒
/// （弹窗先露出来一片灰，图才慢慢出现）。
///
/// 这一版直接放弃 `ImageRenderer`：坐标系、字号、位置全部写死，只用 CGContext 画。
/// 好处是快（几十毫秒）、稳（不可能渲不出来）、而且不依赖 App 当前主题。
enum PosterCanvas {
    /// 海报逻辑尺寸（最终像素 = 这个 × scale）
    static let size = CGSize(width: 360, height: 660)

    /// 固定深色：深底上的发光点更好看，也更像「一张图」，跟 App 主题无关
    private enum Pal {
        static let accent = UIColor(red: 0.62, green: 0.56, blue: 1.00, alpha: 1)
        static let accentDim = UIColor(red: 0.40, green: 0.35, blue: 0.78, alpha: 1)
        static let gold = UIColor(red: 0.98, green: 0.78, blue: 0.36, alpha: 1)
        static let textPrimary = UIColor.white
        static let textSecondary = UIColor.white.withAlphaComponent(0.66)
        static let textTertiary = UIColor.white.withAlphaComponent(0.38)
        static let card = UIColor.white.withAlphaComponent(0.055)
        static let hairline = UIColor.white.withAlphaComponent(0.10)
        static let oceanLight = UIColor(red: 0.29, green: 0.37, blue: 0.58, alpha: 1)
        static let oceanTop = UIColor(red: 0.19, green: 0.25, blue: 0.43, alpha: 1)
        static let oceanBottom = UIColor(red: 0.04, green: 0.06, blue: 0.15, alpha: 1)
        static let land = UIColor(red: 0.27, green: 0.50, blue: 0.47, alpha: 1)
        static let landDim = UIColor(red: 0.18, green: 0.28, blue: 0.38, alpha: 1)
        static let graticule = UIColor.white.withAlphaComponent(0.10)
    }

    private enum Align { case left, center, right }

    private static let padding: CGFloat = 24
    private static var contentWidth: CGFloat { size.width - padding * 2 }

    // MARK: - 入口

    /// `detail == false` 时省掉世界陆地轮廓，出图更快（兜底用）
    static func image(_ data: PosterData, detail: Bool, scale: CGFloat = 2.6) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            draw(data, detail: detail, context: context.cgContext)
        }
    }

    // MARK: - 整体排版

    private static func draw(_ data: PosterData, detail: Bool, context c: CGContext) {
        drawBackground(in: c)
        drawHeader(data, in: c)
        drawGlobe(data, detail: detail, in: c,
                  center: CGPoint(x: size.width / 2, y: 262), radius: 130)
        drawNumbers(data, in: c, top: 412)
        drawExtremes(data, in: c, top: 476)
        drawCoverage(data, in: c, top: 552)
        drawFooter(data, in: c, top: 618)
    }

    // MARK: - 背景

    private static func drawBackground(in c: CGContext) {
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [UIColor(red: 0.075, green: 0.085, blue: 0.165, alpha: 1).cgColor,
                                           UIColor(red: 0.020, green: 0.024, blue: 0.055, alpha: 1).cgColor,
                                           UIColor(red: 0.008, green: 0.010, blue: 0.026, alpha: 1).cgColor]
                                      as CFArray,
                                  locations: [0, 0.55, 1])
        if let gradient {
            c.drawLinearGradient(gradient,
                                 start: CGPoint(x: 0, y: 0),
                                 end: CGPoint(x: 0, y: size.height),
                                 options: [])
        } else {
            c.setFillColor(UIColor.black.cgColor)
            c.fill(CGRect(origin: .zero, size: size))
        }

        // 顶部一层淡紫，避免纯黑太闷
        let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [Pal.accent.withAlphaComponent(0.20).cgColor,
                                       Pal.accent.withAlphaComponent(0).cgColor] as CFArray,
                              locations: [0, 1])
        if let glow {
            let top = CGPoint(x: size.width / 2, y: -20)
            c.drawRadialGradient(glow, startCenter: top, startRadius: 0,
                                 endCenter: top, endRadius: 320, options: [])
        }

        // 星星：固定种子，每次出图位置一致
        var seed: UInt64 = 20_241_112
        for _ in 0..<90 {
            let x = nextRandom(&seed) * size.width
            let y = nextRandom(&seed) * size.height
            let alpha = 0.10 + nextRandom(&seed) * 0.42
            let radius = 0.5 + nextRandom(&seed) * 1.0
            c.setFillColor(UIColor.white.withAlphaComponent(alpha).cgColor)
            c.fillEllipse(in: CGRect(x: x, y: y, width: radius, height: radius))
        }
    }

    private static func nextRandom(_ seed: inout UInt64) -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let value = (seed >> 11) & 0x1F_FFFF_FFFF_FFFF
        return Double(value) / Double(0x20_0000_0000_0000)
    }

    // MARK: - 顶部标题

    private static func drawHeader(_ data: PosterData, in c: CGContext) {
        let stats = data.stats
        text("FOOTPRINT GLOBE", font: font(9, .semibold), color: Pal.textTertiary,
             x: size.width / 2, centerY: 34, tracking: 3.4)
        text(TravelRank.title(for: stats.cityCount), font: font(31, .heavy),
             color: Pal.textPrimary, x: size.width / 2, centerY: 68)
        text(subtitle(stats), font: font(11.5, .regular), color: Pal.textSecondary,
             x: size.width / 2, centerY: 99)
    }

    private static func subtitle(_ stats: TravelStats) -> String {
        var parts: [String] = []
        if let first = stats.earliestYear { parts.append("自 \(first) 年起") }
        parts.append("\(stats.cityCount) 座城市")
        parts.append("\(stats.provinceCount) 个省级")
        return parts.joined(separator: " · ")
    }

    // MARK: - 地球

    private static func drawGlobe(_ data: PosterData, detail: Bool, in c: CGContext,
                                  center: CGPoint, radius: CGFloat) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)
        let spherePath = UIBezierPath(ovalIn: rect).cgPath

        // 球外一圈淡紫光晕
        c.saveGState()
        c.addEllipse(in: rect.insetBy(dx: -radius * 0.5, dy: -radius * 0.5))
        c.clip()
        let halo = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [Pal.accent.withAlphaComponent(0.24).cgColor,
                                       Pal.accent.withAlphaComponent(0).cgColor] as CFArray,
                              locations: [0.40, 1])
        if let halo {
            c.drawRadialGradient(halo, startCenter: center, startRadius: radius * 0.70,
                                 endCenter: center, endRadius: radius * 1.50, options: [])
        }
        c.restoreGState()

        // 球体本体：左上打光的径向渐变
        c.saveGState()
        c.addPath(spherePath)
        c.clip()

        let body = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [Pal.oceanLight.cgColor,
                                       Pal.oceanTop.cgColor,
                                       Pal.oceanBottom.cgColor] as CFArray,
                              locations: [0, 0.55, 1])
        if let body {
            let light = CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.40)
            c.drawRadialGradient(body, startCenter: light, startRadius: 0,
                                 endCenter: center, endRadius: radius * 1.45, options: [])
        }

        let projection = OrthoProjection(origin: center, radius: Double(radius),
                                         center: data.center)
        drawGraticule(projection, in: c)
        if detail { drawWorld(data.countries, projection: projection, in: c) }
        drawProvinces(data, projection: projection, in: c)
        drawMarkers(data, projection: projection, in: c)

        // 左上高光
        let highlightCenter = CGPoint(x: center.x - radius * 0.34, y: center.y - radius * 0.40)
        let highlight = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                   colors: [UIColor.white.withAlphaComponent(0.20).cgColor,
                                            UIColor.white.withAlphaComponent(0.09).cgColor,
                                            UIColor.white.withAlphaComponent(0).cgColor] as CFArray,
                                   locations: [0, 0.42, 1])
        if let highlight {
            c.drawRadialGradient(highlight, startCenter: highlightCenter, startRadius: 0,
                                 endCenter: highlightCenter, endRadius: radius * 1.12, options: [])
        }

        // 边缘暗角：立体感主要靠这一层
        let vignette = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [UIColor.black.withAlphaComponent(0).cgColor,
                                           UIColor.black.withAlphaComponent(0.26).cgColor,
                                           UIColor.black.withAlphaComponent(0.48).cgColor] as CFArray,
                                  locations: [0.52, 0.86, 1])
        if let vignette {
            c.drawRadialGradient(vignette, startCenter: center, startRadius: radius * 0.25,
                                 endCenter: center, endRadius: radius,
                                 options: [.drawsAfterEndLocation])
        }
        c.restoreGState()

        // 边缘描边：一道极细的亮边 + 一道大气色，球才不会「贴」在星空上
        c.addPath(spherePath)
        c.setStrokeColor(UIColor.white.withAlphaComponent(0.18).cgColor)
        c.setLineWidth(0.9)
        c.strokePath()
        c.addPath(spherePath)
        c.setStrokeColor(Pal.accent.withAlphaComponent(0.30).cgColor)
        c.setLineWidth(0.5)
        c.strokePath()
    }

    private static func drawGraticule(_ projection: OrthoProjection, in c: CGContext) {
        let path = CGMutablePath()
        for lon in stride(from: -180.0, through: 180.0, by: 30.0) {
            path.addPath(linePath(stride(from: -80.0, through: 80.0, by: 4.0).map {
                GeoCoord(lon: lon, lat: $0)
            }, projection: projection))
        }
        for lat in stride(from: -60.0, through: 60.0, by: 30.0) {
            path.addPath(linePath(stride(from: -180.0, through: 180.0, by: 4.0).map {
                GeoCoord(lon: $0, lat: lat)
            }, projection: projection))
        }
        c.addPath(path)
        c.setStrokeColor(Pal.graticule.cgColor)
        c.setLineWidth(0.5)
        c.strokePath()
    }

    private static func drawWorld(_ countries: [WorldCountry], projection: OrthoProjection,
                                  in c: CGContext) {
        guard !countries.isEmpty else { return }
        let path = CGMutablePath()
        for country in countries {
            path.addPath(shapePath(rings: country.rings, stride: 2, projection: projection))
        }
        c.addPath(path)
        c.setFillColor(Pal.landDim.cgColor)
        c.fillPath()
        c.addPath(path)
        c.setStrokeColor(UIColor.white.withAlphaComponent(0.10).cgColor)
        c.setLineWidth(0.3)
        c.strokePath()
    }

    private static func drawProvinces(_ data: PosterData, projection: OrthoProjection,
                                      in c: CGContext) {
        guard !data.provinces.isEmpty else { return }
        let all = CGMutablePath()
        let visited = CGMutablePath()
        for province in data.provinces {
            let path = shapePath(rings: province.rings, stride: 3, projection: projection)
            all.addPath(path)
            if data.visitedProvinceCodes.contains(province.code) {
                visited.addPath(path)
            }
        }
        c.addPath(all)
        c.setFillColor(Pal.land.cgColor)
        c.fillPath()
        c.addPath(visited)
        c.setFillColor(Pal.accent.withAlphaComponent(0.72).cgColor)
        c.fillPath()
        c.addPath(all)
        c.setStrokeColor(UIColor.black.withAlphaComponent(0.28).cgColor)
        c.setLineWidth(0.45)
        c.strokePath()
    }

    private static func drawMarkers(_ data: PosterData, projection: OrthoProjection,
                                    in c: CGContext) {
        for city in data.pendingCities {
            let (point, visible) = projection.project(city.center)
            guard visible else { continue }
            c.setStrokeColor(Pal.gold.withAlphaComponent(0.72).cgColor)
            c.setLineWidth(1.0)
            c.strokeEllipse(in: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
        }

        var dots: [CGPoint] = []
        for city in data.visitedCities {
            let (point, visible) = projection.project(city.center)
            if visible { dots.append(point) }
        }
        guard !dots.isEmpty else { return }

        // 发光点：用阴影当光晕，比一个个画径向渐变便宜得多
        c.saveGState()
        c.setShadow(offset: .zero, blur: 6, color: Pal.accent.withAlphaComponent(0.95).cgColor)
        c.setFillColor(Pal.accent.cgColor)
        for point in dots {
            c.fillEllipse(in: CGRect(x: point.x - 1.7, y: point.y - 1.7, width: 3.4, height: 3.4))
        }
        c.restoreGState()

        c.setFillColor(UIColor.white.withAlphaComponent(0.92).cgColor)
        for point in dots {
            c.fillEllipse(in: CGRect(x: point.x - 0.8, y: point.y - 0.8, width: 1.6, height: 1.6))
        }
    }

    // MARK: - 折线

    private static func shapePath(rings: [[GeoCoord]], stride step: Int,
                                  projection: OrthoProjection) -> CGPath {
        let path = CGMutablePath()
        for ring in rings where ring.count >= 3 {
            var started = false
            var index = 0
            while index < ring.count {
                let (point, visible) = projection.project(ring[index])
                if visible {
                    if started {
                        path.addLine(to: point)
                    } else {
                        path.move(to: point)
                        started = true
                    }
                } else if started {
                    path.closeSubpath()
                    started = false
                }
                index += step
            }
            if started { path.closeSubpath() }
        }
        return path
    }

    private static func linePath(_ coords: [GeoCoord], projection: OrthoProjection) -> CGPath {
        let path = CGMutablePath()
        var started = false
        for coord in coords {
            let (point, visible) = projection.project(coord)
            if visible {
                if started {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                    started = true
                }
            } else if started {
                started = false
            }
        }
        return path
    }

    // MARK: - 四个数字

    private static func drawNumbers(_ data: PosterData, in c: CGContext, top: CGFloat) {
        let stats = data.stats
        let items: [(String, String)] = [
            ("\(stats.cityCount)", "城市"),
            ("\(stats.provinceCount)", "省级"),
            ("\(stats.storyCount)", "故事"),
            ("\(stats.photoCount)", "照片")
        ]
        let gap: CGFloat = 8
        let tileWidth = (contentWidth - gap * 3) / 4
        let height: CGFloat = 50

        for (index, item) in items.enumerated() {
            let rect = CGRect(x: padding + (tileWidth + gap) * CGFloat(index),
                              y: top, width: tileWidth, height: height)
            rounded(rect, radius: 11, fill: Pal.card, in: c)
            text(item.0, font: font(21, .bold), color: Pal.textPrimary,
                 x: rect.midX, centerY: rect.minY + 21)
            text(item.1, font: font(9.5, .medium), color: Pal.textTertiary,
                 x: rect.midX, centerY: rect.minY + 37)
        }
    }

    // MARK: - 四极

    private static func drawExtremes(_ data: PosterData, in c: CGContext, top: CGFloat) {
        let stats = data.stats
        text("四极", font: font(9.5, .semibold), color: Pal.textTertiary,
             x: padding, centerY: top + 7, align: .left)
        if stats.yearSpan > 0 {
            text("记录跨度 \(stats.yearSpan) 年", font: font(9.5, .regular),
                 color: Pal.textTertiary, x: size.width - padding, centerY: top + 7, align: .right)
        }

        let items: [(String, String?)] = [
            ("最北", stats.north?.region.name),
            ("最南", stats.south?.region.name),
            ("最东", stats.east?.region.name),
            ("最西", stats.west?.region.name)
        ]
        let gap: CGFloat = 8
        let tileWidth = (contentWidth - gap * 3) / 4
        let tilesTop = top + 18
        let height: CGFloat = 44

        for (index, item) in items.enumerated() {
            let rect = CGRect(x: padding + (tileWidth + gap) * CGFloat(index),
                              y: tilesTop, width: tileWidth, height: height)
            rounded(rect, radius: 10, fill: Pal.card, in: c)
            text(item.0, font: font(8.5, .semibold), color: Pal.textTertiary,
                 x: rect.midX, centerY: tilesTop + 13)
            let name = item.1 ?? "—"
            let nameFont = fittedFont(name, font: font(12, .bold), maxWidth: tileWidth - 8)
            text(name, font: nameFont,
                 color: item.1 == nil ? Pal.textTertiary : Pal.textPrimary,
                 x: rect.midX, centerY: tilesTop + 30)
        }
    }

    // MARK: - 覆盖率

    private static func drawCoverage(_ data: PosterData, in c: CGContext, top: CGFloat) {
        let stats = data.stats
        let badgeRatio = data.totalBadges > 0
            ? Double(data.unlockedBadges) / Double(data.totalBadges) : 0
        bar("面积覆盖", detail: stats.areaRatioText, value: stats.areaRatio, in: c, top: top)
        bar("徽章", detail: "\(data.unlockedBadges)/\(data.totalBadges)",
            value: badgeRatio, in: c, top: top + 26)
    }

    private static func bar(_ title: String, detail: String, value: Double,
                            in c: CGContext, top: CGFloat) {
        text(title, font: font(9.5, .medium), color: Pal.textSecondary,
             x: padding, centerY: top + 7, align: .left)
        text(detail, font: font(9.5, .semibold), color: Pal.accent,
             x: size.width - padding, centerY: top + 7, align: .right)

        let track = CGRect(x: padding, y: top + 16, width: contentWidth, height: 4)
        rounded(track, radius: 2, fill: Pal.hairline, in: c)

        let clamped = min(1, max(0, value))
        let fillRect = CGRect(x: padding, y: top + 16,
                              width: max(3, contentWidth * CGFloat(clamped)), height: 4)
        c.saveGState()
        c.addPath(UIBezierPath(roundedRect: fillRect, cornerRadius: 2).cgPath)
        c.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [Pal.accentDim.cgColor, Pal.accent.cgColor] as CFArray,
                                  locations: [0, 1])
        if let gradient {
            c.drawLinearGradient(gradient,
                                 start: CGPoint(x: padding, y: 0),
                                 end: CGPoint(x: size.width - padding, y: 0),
                                 options: [])
        }
        c.restoreGState()
    }

    // MARK: - 底部

    private static func drawFooter(_ data: PosterData, in c: CGContext, top: CGFloat) {
        c.setFillColor(Pal.hairline.cgColor)
        c.fill(CGRect(x: padding, y: top, width: contentWidth, height: 0.8))
        text("足迹地球 \(data.version)", font: font(8.5, .medium), color: Pal.textTertiary,
             x: padding, centerY: top + 16, align: .left)
        text(dateText(data.generatedAt), font: font(8.5, .regular), color: Pal.textTertiary,
             x: size.width - padding, centerY: top + 16, align: .right)
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }

    // MARK: - 绘制小工具

    private static func rounded(_ rect: CGRect, radius: CGFloat, fill: UIColor,
                                in c: CGContext) {
        c.setFillColor(fill.cgColor)
        c.addPath(UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath)
        c.fillPath()
    }

    private static func font(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// 长名字自动缩字号，代替 SwiftUI 的 `minimumScaleFactor`
    private static func fittedFont(_ string: String, font: UIFont,
                                   maxWidth: CGFloat) -> UIFont {
        var size = font.pointSize
        while size > 6 {
            let candidate = UIFont(descriptor: font.fontDescriptor, size: size)
            let width = (string as NSString).size(withAttributes: [.font: candidate]).width
            if width <= maxWidth { return candidate }
            size -= 0.5
        }
        return UIFont(descriptor: font.fontDescriptor, size: 6)
    }

    private static func text(_ string: String, font: UIFont, color: UIColor,
                             x: CGFloat, centerY: CGFloat,
                             align: Align = .center, tracking: CGFloat = 0) {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        if tracking != 0 { attributes[.kern] = tracking }
        let attributed = NSAttributedString(string: string, attributes: attributes)
        let bounds = attributed.boundingRect(with: CGSize(width: 400, height: 120),
                                              options: [.usesLineFragmentOrigin], context: nil)
        let originX: CGFloat
        switch align {
        case .left: originX = x
        case .center: originX = x - bounds.width / 2
        case .right: originX = x - bounds.width
        }
        attributed.draw(at: CGPoint(x: originX, y: centerY - bounds.height / 2))
    }
}
