import SwiftUI

/// 正交投影：把经纬度投到屏幕上，同时返回该点是否在可见半球（正面）。
struct OrthoProjection {
    let origin: CGPoint
    let radius: Double
    private let lon0: Double
    private let lat0: Double
    private let sinLat0: Double
    private let cosLat0: Double

    init(origin: CGPoint, radius: Double, center: GeoCoord) {
        self.origin = origin
        self.radius = radius
        self.lon0 = center.lon * .pi / 180
        self.lat0 = center.lat * .pi / 180
        self.sinLat0 = sin(lat0)
        self.cosLat0 = cos(lat0)
    }

    func project(_ p: GeoCoord) -> (point: CGPoint, visible: Bool) {
        let lon = p.lon * .pi / 180
        let lat = p.lat * .pi / 180
        let dLon = lon - lon0
        let cosC = sinLat0 * sin(lat) + cosLat0 * cos(lat) * cos(dLon)
        let x = origin.x + radius * cos(lat) * sin(dLon)
        let y = origin.y - radius * (cosLat0 * sin(lat) - sinLat0 * cos(lat) * cos(dLon))
        return (CGPoint(x: x, y: y), cosC > 0.02)
    }
}

/// 自绘 3D 地球：球体渐变 + 经纬网 + 世界陆地 + 中国/日本/极地轮廓 + 去过的地方发光。
/// 不依赖任何地图 SDK，只有离线边界数据。
struct GlobeView: View {
    let center: GeoCoord
    let radiusFactor: Double
    let provinces: [Region]
    let visitedProvinceCodes: Set<String>
    let visitedCities: [Region]
    let pendingCities: [Region]
    let focus: GeoCoord?
    /// 世界陆地轮廓（只做背景，不参与判定）
    var countries: [WorldCountry] = []
    /// 太阳直射点，用来画晨昏线（白天 / 黑夜）
    var sun: GeoCoord = GeoCoord(lon: 0, lat: 0)
    /// 外观只用来触发重绘（Theme 是全局静态，Canvas 不会自己知道它变了）
    var appearance: AppearanceMode = .dark

    var body: some View {
        Canvas { context, size in
            draw(in: context, size: size)
        }
        .id(appearance)
        .accessibilityLabel("3D 地球")
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let radius = Double(min(size.width, size.height)) * radiusFactor
        guard radius > 10 else { return }
        let origin = CGPoint(x: size.width / 2, y: size.height / 2)
        let sphereRect = CGRect(x: origin.x - radius, y: origin.y - radius,
                                width: radius * 2, height: radius * 2)
        let sphere = Path(ellipseIn: sphereRect)

        // 大气光：内圈紧一点、外圈散一点，像真有大气的散射
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: radius * 0.24))
            let outer = sphereRect.insetBy(dx: -radius * 0.10, dy: -radius * 0.10)
            layer.fill(Path(ellipseIn: outer),
                       with: .color(Color(red: 0.32, green: 0.52, blue: 1.0)
                        .opacity(Theme.isLight ? 0.14 : 0.26)))
        }
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: radius * 0.07))
            let inner = sphereRect.insetBy(dx: -radius * 0.022, dy: -radius * 0.022)
            layer.fill(Path(ellipseIn: inner),
                       with: .color(Color(red: 0.55, green: 0.72, blue: 1.0)
                        .opacity(Theme.isLight ? 0.20 : 0.34)))
        }

        // 球体本体：海洋底色，靠近太阳一侧稍亮偏暖
        let baseTop = Theme.isLight
            ? Color(red: 0.80, green: 0.86, blue: 0.92)
            : Color(red: 0.075, green: 0.115, blue: 0.185)
        let baseBottom = Theme.isLight
            ? Color(red: 0.86, green: 0.90, blue: 0.93)
            : Color(red: 0.030, green: 0.052, blue: 0.105)
        context.fill(sphere, with: .linearGradient(
            Gradient(colors: [baseTop, baseBottom]),
            startPoint: CGPoint(x: origin.x - radius * 0.5, y: origin.y - radius),
            endPoint: CGPoint(x: origin.x + radius * 0.6, y: origin.y + radius)))

        let projection = OrthoProjection(origin: origin, radius: radius, center: center)

        var surface = context
        surface.clip(to: sphere)

        drawGraticule(in: surface, projection: projection)
        drawWorld(in: surface, projection: projection)
        drawLand(in: surface, projection: projection)
        drawPolarCircle(in: surface, projection: projection)
        drawMarkers(in: surface, projection: projection)
        drawDayNight(in: surface, origin: origin, radius: radius,
                     projection: projection, sphere: sphere)
        drawShading(in: surface, origin: origin, radius: radius, sphere: sphere)

        // 边缘一圈极薄的亮边，球才不会「贴」在星空上
        context.stroke(sphere, with: .color(Color.white.opacity(Theme.isLight ? 0.35 : 0.16)),
                       lineWidth: 0.9)
        context.stroke(sphere, with: .color(Color(red: 0.55, green: 0.72, blue: 1.0).opacity(0.28)),
                       lineWidth: 0.4)
    }

    // MARK: - 世界背景陆地

    private func drawWorld(in context: GraphicsContext, projection: OrthoProjection) {
        guard !countries.isEmpty else { return }
        var path = Path()
        for country in countries {
            path.addPath(polyline(rings: country.rings, stride: 2, projection: projection))
        }
        context.fill(path, with: .color(Theme.landDim.opacity(Theme.isLight ? 0.50 : 0.32)))
        context.stroke(path, with: .color(Theme.border.opacity(0.20)), lineWidth: 0.3)
    }

    /// 北极圈：北极没有陆地边界，用一条虚线标出位置，让地球上方不空着。
    private func drawPolarCircle(in context: GraphicsContext, projection: OrthoProjection) {
        var path = Path()
        append(&path, projection: projection,
               points: stride(from: -180.0, through: 180.0, by: 3.0).map {
                   GeoCoord(lon: $0, lat: 66.56)
               })
        context.stroke(path, with: .color(Theme.brandLight.opacity(0.45)),
                       style: StrokeStyle(lineWidth: 0.7, dash: [4, 4]))
    }

    // MARK: - 经纬网

    private func drawGraticule(in context: GraphicsContext, projection: OrthoProjection) {
        var path = Path()
        for lon in stride(from: -180.0, through: 180.0, by: 30.0) {
            append(&path, projection: projection,
                   points: stride(from: -80.0, through: 80.0, by: 4.0).map {
                       GeoCoord(lon: lon, lat: $0)
                   })
        }
        for lat in stride(from: -60.0, through: 60.0, by: 30.0) {
            append(&path, projection: projection,
                   points: stride(from: -180.0, through: 180.0, by: 4.0).map {
                       GeoCoord(lon: $0, lat: lat)
                   })
        }
        context.stroke(path, with: .color(Theme.graticule.opacity(0.22)), lineWidth: 0.5)
    }

    // MARK: - 陆地

    private func drawLand(in context: GraphicsContext, projection: OrthoProjection) {
        var land = Path()
        var visited = Path()
        for province in provinces {
            let path = polyline(rings: province.rings, stride: 3, projection: projection)
            land.addPath(path)
            if visitedProvinceCodes.contains(province.code) {
                visited.addPath(path)
            }
        }

        context.fill(land, with: .color(Theme.land.opacity(0.94)))
        if !visitedProvinceCodes.isEmpty {
            context.fill(visited, with: .color(Theme.brand.opacity(0.55)))
        }
        context.stroke(land, with: .color(Theme.border.opacity(0.55)), lineWidth: 0.45)
    }

    // MARK: - 标记点

    private func drawMarkers(in context: GraphicsContext, projection: OrthoProjection) {
        // 候选（待确认）：琥珀色空心小点
        for city in pendingCities {
            let (point, visible) = projection.project(city.center)
            guard visible else { continue }
            context.stroke(dotPath(at: point, radius: 3.2),
                           with: .color(Theme.pending.opacity(0.85)), lineWidth: 1.1)
        }

        var dots: [CGPoint] = []
        for city in visitedCities {
            let (point, visible) = projection.project(city.center)
            if visible { dots.append(point) }
        }
        guard !dots.isEmpty else { return }

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 3.5))
            for point in dots {
                layer.fill(dotPath(at: point, radius: 3.4), with: .color(Theme.brand))
            }
        }
        for point in dots {
            context.fill(dotPath(at: point, radius: 1.7), with: .color(Theme.brandLight))
        }

        if let focus = focus {
            let (point, visible) = projection.project(focus)
            if visible {
                let ink: Color = Theme.isLight ? Color.black.opacity(0.65) : .white
                context.stroke(dotPath(at: point, radius: 6), with: .color(ink.opacity(0.75)),
                               lineWidth: 1.2)
                context.fill(dotPath(at: point, radius: 2.6), with: .color(ink))
            }
        }
    }

    private func dotPath(at point: CGPoint, radius: Double) -> Path {
        Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                               width: radius * 2, height: radius * 2))
    }

    // MARK: - 晨昏线（白天 / 黑夜）

    /// 用「以太阳直射点为中心的径向渐变」近似真实的日照分布：
    /// 屏幕上到直射点的距离 d 对应球面角 θ（d = R·sinθ），亮度 ∝ cosθ = √(1−(d/R)²)，
    /// 所以只要按 d/R 取几档透明度，就能得到一条自然的晨昏线，不用做逐像素光照。
    private func drawDayNight(in context: GraphicsContext, origin: CGPoint, radius: Double,
                              projection: OrthoProjection, sphere: Path) {
        let (sunPoint, _) = projection.project(sun)
        let peak = Theme.isLight ? 0.50 : 0.84

        context.fill(sphere, with: .radialGradient(
            Gradient(stops: [
                .init(color: Color.black.opacity(0), location: 0.00),
                .init(color: Color.black.opacity(peak * 0.05), location: 0.30),
                .init(color: Color.black.opacity(peak * 0.16), location: 0.50),
                .init(color: Color.black.opacity(peak * 0.34), location: 0.70),
                .init(color: Color.black.opacity(peak * 0.56), location: 0.85),
                .init(color: Color.black.opacity(peak * 0.80), location: 0.95),
                .init(color: Color.black.opacity(peak), location: 1.00)
            ]),
            center: sunPoint,
            startRadius: 0,
            endRadius: radius))

        // 晨昏线上一条暖色带（日出日落的那种橘）
        let warm = Color(red: 1.0, green: 0.56, blue: 0.30)
        context.fill(sphere, with: .radialGradient(
            Gradient(stops: [
                .init(color: warm.opacity(0), location: 0.78),
                .init(color: warm.opacity(Theme.isLight ? 0.10 : 0.20), location: 0.93),
                .init(color: warm.opacity(Theme.isLight ? 0.05 : 0.10), location: 0.985),
                .init(color: warm.opacity(0), location: 1.0)
            ]),
            center: sunPoint,
            startRadius: 0,
            endRadius: radius))

        // 直射点的高光：一点点就够了，多了像塑料球
        context.fill(sphere, with: .radialGradient(
            Gradient(stops: [
                .init(color: Color.white.opacity(Theme.isLight ? 0.22 : 0.30), location: 0),
                .init(color: Color.white.opacity(Theme.isLight ? 0.08 : 0.10), location: 0.45),
                .init(color: .clear, location: 1)
            ]),
            center: sunPoint,
            startRadius: 0,
            endRadius: radius * 0.72))
    }

    // MARK: - 球面明暗

    private func drawShading(in context: GraphicsContext, origin: CGPoint,
                             radius: Double, sphere: Path) {
        // 边缘暗角：球体边缘向内收光，立体感主要靠这一层
        context.fill(sphere, with: .radialGradient(
            Gradient(stops: [
                .init(color: .clear, location: 0.52),
                .init(color: Color.black.opacity(Theme.isLight ? 0.10 : 0.26), location: 0.86),
                .init(color: Color.black.opacity(Theme.isLight ? 0.22 : 0.46), location: 1.0)
            ]),
            center: origin,
            startRadius: radius * 0.25,
            endRadius: radius))
    }

    // MARK: - 折线构建

    /// 把一串经纬度按可见性拆成子路径（跨越球面边缘时断开，避免连线穿球）。
    private func append(_ path: inout Path, projection: OrthoProjection, points: [GeoCoord]) {
        var started = false
        for coord in points {
            let (point, visible) = projection.project(coord)
            if visible {
                if started { path.addLine(to: point) } else { path.move(to: point); started = true }
            } else if started {
                started = false
            }
        }
    }

    private func polyline(rings: [[GeoCoord]], stride: Int,
                          projection: OrthoProjection) -> Path {
        var path = Path()
        for ring in rings {
            guard ring.count >= 3 else { continue }
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
                index += stride
            }
            if started { path.closeSubpath() }
        }
        return path
    }
}
