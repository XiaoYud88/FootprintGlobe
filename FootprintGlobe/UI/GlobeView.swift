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

/// 地球上画一条行程需要的东西：起点、终点、交通工具、相位（让多条线错开时间飞）
struct GlobeLeg: Identifiable, Equatable {
    let id: UUID
    let from: GeoCoord
    let to: GeoCoord
    let mode: TransportMode
    /// 0…1，决定这条线在循环里的起始时刻
    let phase: Double
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
    /// 陀螺仪视差：相机中心额外偏移多少度（球面跟着手腕轻微转，星空不动，有层次）
    var parallax: CGSize = .zero
    /// 外观只用来触发重绘（Theme 是全局静态，Canvas 不会自己知道它变了）
    var appearance: AppearanceMode = .dark
    /// 家的位置：画一枚金色标记，并从家向去过的城市拉出很淡的归家线
    var home: GeoCoord?
    /// 家最近的几座城市（归家线只画这些，避免几百条线糊成一片）
    var homeArcs: [[GeoCoord]] = []
    /// 正在循环飞/跑的行程
    var legs: [GlobeLeg] = []
    /// 是否播放动画（照片渲染时传 false，静态出图）
    var animated: Bool = false

    var body: some View {
        Group {
            if let interval = motionInterval {
                TimelineView(.animation(minimumInterval: interval, paused: false)) { timeline in
                    canvas(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                canvas(time: 0)
            }
        }
        .id(appearance)
        .accessibilityLabel("3D 地球")
    }

    /// 没有行程也没有家的时候完全不动（省电）；
    /// 只有家的呼吸光环时降到 8 帧，真在飞的时候才跑满 24 帧。
    private var motionInterval: Double? {
        guard animated else { return nil }
        if !legs.isEmpty { return 1.0 / 24.0 }
        if home != nil { return 1.0 / 8.0 }
        return nil
    }

    private func canvas(time: TimeInterval) -> some View {
        Canvas { context, size in
            draw(in: context, size: size, time: time)
        }
    }

    private func draw(in context: GraphicsContext, size: CGSize, time: TimeInterval) {
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
                       with: .color(Theme.atmosphere
                        .opacity(Theme.isLight ? 0.14 : 0.26)))
        }
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: radius * 0.07))
            let inner = sphereRect.insetBy(dx: -radius * 0.022, dy: -radius * 0.022)
            layer.fill(Path(ellipseIn: inner),
                       with: .color(Theme.atmosphere
                        .opacity(Theme.isLight ? 0.20 : 0.34)))
        }

        // 球体本体：上下一个渐变，给球一个固定的光向
        let baseTop = Theme.globeTop
        let baseBottom = Theme.globeBottom
        context.fill(sphere, with: .linearGradient(
            Gradient(colors: [baseTop, baseBottom]),
            startPoint: CGPoint(x: origin.x - radius * 0.5, y: origin.y - radius),
            endPoint: CGPoint(x: origin.x + radius * 0.6, y: origin.y + radius)))

        // 陀螺仪视差只挪相机中心，不动球本身：星空静止时球面轻微跟着手转，就有了纵深
        let lat = min(max(center.lat + Double(parallax.height), -82), 82)
        let viewCenter = GeoCoord(lon: center.lon + Double(parallax.width), lat: lat)
        let projection = OrthoProjection(origin: origin, radius: radius, center: viewCenter)

        var surface = context
        surface.clip(to: sphere)

        drawGraticule(in: surface, projection: projection)
        drawWorld(in: surface, projection: projection)
        drawLand(in: surface, projection: projection)
        drawPolarCircle(in: surface, projection: projection)
        drawHomeGlow(in: surface, projection: projection, radius: radius, sphere: sphere)
        drawHomeTrails(in: surface, projection: projection)
        drawLegTrails(in: surface, viewCenter: viewCenter, origin: origin, radius: radius)
        drawMarkers(in: surface, projection: projection)
        drawHighlight(in: surface, origin: origin, radius: radius, sphere: sphere)
        drawShading(in: surface, origin: origin, radius: radius, sphere: sphere)

        // 球外这两层不裁剪：交通工具浮在球面之上，家标记也要能「冒」出球边缘
        drawLegVehicles(in: context, viewCenter: viewCenter, origin: origin,
                        radius: radius, time: time)
        drawHomeMarker(in: context, viewCenter: viewCenter, origin: origin,
                       radius: radius, time: time)

        // 边缘一圈极薄的亮边，球才不会「贴」在星空上
        context.stroke(sphere, with: .color(Color.white.opacity(Theme.isLight ? 0.35 : 0.16)),
                       lineWidth: 0.9)
        context.stroke(sphere, with: .color(Theme.atmosphere.opacity(0.28)),
                       lineWidth: 0.4)
        if Theme.isLight {
            // 浅色系球体跟纸面颜色接近，补一圈墨线才有边界
            context.stroke(sphere, with: .color(Theme.border.opacity(0.30)), lineWidth: 0.5)
        }
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

    // MARK: - 球面光

    /// 上一版的晨昏线在手机小屏上又糊又脏（径向渐变会在地球边缘糊成一圈灰），
    /// 这一版直接去掉，改成固定方向的一束柔光：左上高光 + 边缘暗角，
    /// 球看起来是「被灯照着」，干净、也不用跟着时间刷新。
    private func drawHighlight(in context: GraphicsContext, origin: CGPoint,
                               radius: Double, sphere: Path) {
        let light = CGPoint(x: origin.x - radius * 0.34, y: origin.y - radius * 0.40)
        let peak = Theme.isLight ? 0.18 : 0.22
        context.fill(sphere, with: .radialGradient(
            Gradient(stops: [
                .init(color: Color.white.opacity(peak), location: 0),
                .init(color: Color.white.opacity(peak * 0.45), location: 0.42),
                .init(color: .clear, location: 1)
            ]),
            center: light,
            startRadius: 0,
            endRadius: radius * 1.12))
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

    // MARK: - 家

    /// 设了家之后，球面上家周围有一小片暖光——「有一盏灯一直亮着」
    private func drawHomeGlow(in context: GraphicsContext, projection: OrthoProjection,
                              radius: Double, sphere: Path) {
        guard let home else { return }
        let (point, visible) = projection.project(home)
        guard visible else { return }
        var layer = context
        layer.clip(to: sphere)
        layer.fill(sphere, with: .radialGradient(
            Gradient(stops: [
                .init(color: Theme.gold.opacity(0.18), location: 0),
                .init(color: Theme.gold.opacity(0.05), location: 0.42),
                .init(color: .clear, location: 1)
            ]),
            center: point,
            startRadius: 0,
            endRadius: radius * 0.95))
    }

    /// 从家向最近的几座城市拉出的极淡归家线：不抢主视觉，但一眼能看出「都从这儿出发」
    private func drawHomeTrails(in context: GraphicsContext, projection: OrthoProjection) {
        guard !homeArcs.isEmpty else { return }
        var path = Path()
        for arc in homeArcs {
            append(&path, projection: projection, points: arc)
        }
        context.stroke(path, with: .color(Theme.gold.opacity(0.26)),
                       style: StrokeStyle(lineWidth: 0.8, lineCap: .round, dash: [2, 6]))
    }

    /// 家标记：金色圆点 + 白色小屋顶 + 两圈错开的呼吸光环 + 沿球面法线挑出去的一小截光柱。
    /// 光柱是立体感的关键——它让「家」是站在球上，而不是贴在球面的一张图。
    private func drawHomeMarker(in context: GraphicsContext, viewCenter: GeoCoord,
                                origin: CGPoint, radius: Double, time: TimeInterval) {
        guard let home else { return }
        let projection = OrthoProjection(origin: origin, radius: radius, center: viewCenter)
        let (point, visible) = projection.project(home)
        guard visible else { return }

        for index in 0..<2 {
            let phase = (time / 2.8 + Double(index) * 0.5)
                .truncatingRemainder(dividingBy: 1)
            let grow = radius * (0.022 + 0.085 * phase)
            let alpha = (1 - phase) * (Theme.isLight ? 0.42 : 0.58)
            context.stroke(dotPath(at: point, radius: grow),
                           with: .color(Theme.gold.opacity(alpha)), lineWidth: 1.1)
        }

        let dx = Double(point.x - origin.x)
        let dy = Double(point.y - origin.y)
        let dist = hypot(dx, dy)
        if dist > 1 {
            let edge = min(1, dist / radius)
            let length = radius * (0.05 + 0.10 * edge)
            let ux = dx / dist
            let uy = dy / dist
            let halfWidth = radius * 0.028
            var beam = Path()
            beam.move(to: CGPoint(x: point.x - uy * halfWidth, y: point.y + ux * halfWidth))
            beam.addLine(to: CGPoint(x: point.x + uy * halfWidth, y: point.y - ux * halfWidth))
            beam.addLine(to: CGPoint(x: point.x + ux * length, y: point.y + uy * length))
            beam.closeSubpath()
            var layer = context
            layer.clip(to: beam)
            layer.fill(beam, with: .linearGradient(
                Gradient(colors: [Theme.gold.opacity(0.34), Theme.gold.opacity(0)]),
                startPoint: point,
                endPoint: CGPoint(x: point.x + ux * length, y: point.y + uy * length)))
        }

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 3.4))
            layer.fill(dotPath(at: point, radius: 4.8), with: .color(Theme.gold.opacity(0.9)))
        }
        context.fill(dotPath(at: point, radius: 3.0), with: .color(Theme.gold))
        context.fill(dotPath(at: point, radius: 1.2), with: .color(Color.white.opacity(0.95)))

        var roof = Path()
        roof.move(to: CGPoint(x: point.x, y: point.y - 9.8))
        roof.addLine(to: CGPoint(x: point.x + 3.7, y: point.y - 5.8))
        roof.addLine(to: CGPoint(x: point.x - 3.7, y: point.y - 5.8))
        roof.closeSubpath()
        context.fill(roof, with: .color(Theme.gold))
    }

    // MARK: - 出行

    /// 航迹：按交通方式抬到不同高度再投影，于是飞机是悬在空中一条弧，高铁贴着地面
    private func drawLegTrails(in context: GraphicsContext, viewCenter: GeoCoord,
                               origin: CGPoint, radius: Double) {
        guard !legs.isEmpty else { return }
        for leg in legs {
            let lifted = OrthoProjection(origin: origin,
                                         radius: radius * (1 + leg.mode.altitude),
                                         center: viewCenter)
            var path = Path()
            append(&path, projection: lifted,
                   points: GreatCircle.samples(from: leg.from, to: leg.to, count: 64))
            let tint = leg.mode.tint
            if leg.mode.dashed {
                context.stroke(path, with: .color(tint.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [3, 6]))
            } else {
                context.stroke(path, with: .color(Color.black.opacity(0.20)), lineWidth: 3.4)
                context.stroke(path, with: .color(tint.opacity(0.82)), lineWidth: 1.2)
            }
        }
    }

    /// 交通工具本体：底下一层投影 + 一个带上下渐变的圆角载体 + 白色图标，
    /// 飞机和船再按屏幕上的行进方向转过来，看起来才像在「飞」而不是在滑。
    private func drawLegVehicles(in context: GraphicsContext, viewCenter: GeoCoord,
                                 origin: CGPoint, radius: Double, time: TimeInterval) {
        guard !legs.isEmpty else { return }
        for leg in legs {
            let (t, alpha) = leg.motion(at: time)
            guard alpha > 0.02 else { continue }
            let projection = OrthoProjection(origin: origin,
                                            radius: radius * (1 + leg.mode.altitude),
                                            center: viewCenter)
            let coord = GreatCircle.point(from: leg.from, to: leg.to, t: t)
            let (point, visible) = projection.project(coord)
            guard visible else { continue }

            let side = max(7.5, radius * leg.mode.iconScale * 2.2)
            var heading = 0.0
            if leg.mode.turns {
                let behind = projection.project(
                    GreatCircle.point(from: leg.from, to: leg.to, t: max(0, t - 0.02))).point
                let ahead = projection.project(
                    GreatCircle.point(from: leg.from, to: leg.to, t: min(1, t + 0.02))).point
                heading = atan2(Double(ahead.y - behind.y),
                                Double(ahead.x - behind.x))
            }

            var layer = context
            layer.opacity = alpha
            layer.translateBy(x: point.x, y: point.y)
            layer.rotate(by: Angle(radians: heading))

            // 影子落在球的表面上，图标浮在上面，这一小段距离就是「立体」
            layer.fill(Path(ellipseIn: CGRect(x: -side * 0.42, y: side * 0.18,
                                              width: side * 0.84, height: side * 0.34)),
                       with: .color(Color.black.opacity(0.26)))
            let body = Path(roundedRect: CGRect(x: -side * 0.46, y: -side * 0.46,
                                                width: side * 0.92, height: side * 0.92),
                            cornerRadius: side * 0.30)
            layer.fill(body, with: .linearGradient(
                Gradient(colors: [leg.mode.tint.opacity(0.99), leg.mode.tint.opacity(0.68)]),
                startPoint: CGPoint(x: 0, y: -side * 0.5),
                endPoint: CGPoint(x: 0, y: side * 0.5)))
            layer.stroke(body, with: .color(Color.white.opacity(0.42)), lineWidth: 0.6)

            var symbol = layer.resolve(Image(systemName: leg.mode.symbol))
            symbol.shading = .color(Color.white)
            layer.draw(symbol, in: CGRect(x: -side * 0.30, y: -side * 0.30,
                                          width: side * 0.60, height: side * 0.60))
        }
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

// MARK: - 交通工具的颜色 / 运动节奏

extension TransportMode {
    /// 每种交通一个自己的颜色，地球上同时飞好几条也分得清
    var tint: Color {
        switch self {
        case .plane: return Theme.brandLight
        case .highSpeed: return Theme.gold
        case .train: return Theme.pending
        case .car: return Theme.wish
        case .ship: return Theme.atmosphere
        case .walk: return Theme.textSecondary
        }
    }
}

extension GlobeLeg {
    /// 一趟循环：去程 → 在终点停一会儿 → 回程 → 再停一会儿。
    /// 返回当前走过多少（0…1）和透明度（起步/落地时淡入淡出，避免图标突然闪现）。
    func motion(at time: TimeInterval) -> (t: Double, alpha: Double) {
        let hold = 1.6
        let cycle = 2 * (mode.duration + hold)
        guard cycle > 0 else { return (0, 0) }
        var local = (time + phase * cycle).truncatingRemainder(dividingBy: cycle)
        if local < 0 { local += cycle }
        let half = cycle / 2
        let outbound = local < half
        let legTime = outbound ? local : local - half
        let travel = min(1, legTime / mode.duration)
        let holding = legTime >= mode.duration
        let t = outbound ? travel : 1 - travel
        let fade = holding ? 0 : min(1, min(travel / 0.06, (1 - travel) / 0.06))
        return (t, max(0, fade))
    }
}
