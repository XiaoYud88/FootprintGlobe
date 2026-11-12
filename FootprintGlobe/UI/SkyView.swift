import SwiftUI

/// 背景天空：多层星点 + 银河 + 月亮。
///
/// 之前的星空是 150 个随机白点，像屏幕坏点；这里重做成三层星（暗/中/亮），
/// 亮星带十字光芒，银河是一条模糊的斜带，右上角有一颗带光晕、有月相和环形山的月亮。
/// 星点位置用固定种子生成，不会每次重绘都跳；只有亮度会按时间轻微闪烁。
struct SkyView: View {
    var appearance: AppearanceMode = .dark
    /// 相机经度：球体转动时星空做一点视差，让「天在动」有层次
    var centerLon: Double = 105
    /// 用来算月相
    var date: Date = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.6)) { timeline in
            Canvas { context, size in
                draw(in: context, size: size, time: timeline.date.timeIntervalSince1970)
            }
        }
        .id(appearance)
        .allowsHitTesting(false)
    }

    private func draw(in context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let rect = CGRect(origin: .zero, size: size)
        if appearance == .light {
            drawDaylight(in: context, rect: rect)
            drawMoon(in: context, rect: rect, faint: true)
            return
        }

        // 深空底色：不是纯黑，四个角的色温略有差别
        context.fill(Path(rect), with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.035, green: 0.045, blue: 0.094), location: 0.0),
                .init(color: Color(red: 0.024, green: 0.030, blue: 0.068), location: 0.45),
                .init(color: Color(red: 0.010, green: 0.012, blue: 0.030), location: 1.0)
            ]),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: size.width * 0.7, y: size.height)))

        // 两团星云（紫、青），非常淡，只是让底色不平
        drawNebula(in: context, rect: rect,
                   center: CGPoint(x: size.width * 0.16, y: size.height * 0.30),
                   radius: size.width * 0.75,
                   color: Color(red: 0.36, green: 0.24, blue: 0.62), alpha: 0.13)
        drawNebula(in: context, rect: rect,
                   center: CGPoint(x: size.width * 0.92, y: size.height * 0.72),
                   radius: size.width * 0.62,
                   color: Color(red: 0.12, green: 0.42, blue: 0.58), alpha: 0.10)

        drawMilkyWay(in: context, rect: rect)
        drawStars(in: context, rect: rect, time: time)
        drawMoon(in: context, rect: rect, faint: false)
    }

    // MARK: - 浅色：清晨的纸

    private func drawDaylight(in context: GraphicsContext, rect: CGRect) {
        context.fill(Path(rect), with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.996, green: 0.984, blue: 0.960), location: 0.0),
                .init(color: Color(red: 0.968, green: 0.962, blue: 0.958), location: 0.5),
                .init(color: Color(red: 0.912, green: 0.922, blue: 0.940), location: 1.0)
            ]),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: rect.width, y: rect.height)))

        // 左上一点暖光，像窗外天亮了
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: rect.width * 0.22))
            layer.fill(
                Path(ellipseIn: CGRect(x: -rect.width * 0.25, y: -rect.height * 0.20,
                                       width: rect.width * 0.95, height: rect.width * 0.95)),
                with: .radialGradient(
                    Gradient(colors: [Color(red: 1.0, green: 0.94, blue: 0.82).opacity(0.85), .clear]),
                    center: CGPoint(x: rect.width * 0.22, y: rect.height * 0.16),
                    startRadius: 0, endRadius: rect.width * 0.55))
        }
    }

    // MARK: - 星云 / 银河

    private func drawNebula(in context: GraphicsContext, rect: CGRect,
                            center: CGPoint, radius: CGFloat, color: Color, alpha: Double) {
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: radius * 0.35))
            layer.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: color.opacity(alpha), location: 0),
                        .init(color: color.opacity(alpha * 0.35), location: 0.55),
                        .init(color: .clear, location: 1)
                    ]),
                    center: center, startRadius: 0, endRadius: radius))
        }
    }

    private func drawMilkyWay(in context: GraphicsContext, rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: rect.width * 0.055))
            layer.translateBy(x: center.x, y: center.y)
            layer.rotate(by: .degrees(-26))
            // 一条很扁的斜带，中间亮两边淡
            for (index, width) in [1.0, 0.62, 0.34].enumerated() {
                let w = rect.width * 0.95 * width
                let h = rect.width * 0.30 * width
                layer.fill(
                    Path(ellipseIn: CGRect(x: -w, y: -h / 2, width: w * 2, height: h)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Color(red: 0.80, green: 0.84, blue: 1.0)
                                .opacity(0.085 - Double(index) * 0.02), location: 0),
                            .init(color: Color(red: 0.62, green: 0.70, blue: 0.95)
                                .opacity(0.045 - Double(index) * 0.01), location: 0.6),
                            .init(color: .clear, location: 1)
                        ]),
                        center: .zero, startRadius: 0, endRadius: w))
            }
        }
    }

    // MARK: - 星点

    private func drawStars(in context: GraphicsContext, rect: CGRect, time: TimeInterval) {
        let parallax = ((centerLon - 105).truncatingRemainder(dividingBy: 360)) * 0.22
        var seed: UInt64 = 0x51ED_270B_9A3C_1F7F

        // 三层：越亮越少越大
        let layers: [(count: Int, minR: CGFloat, maxR: CGFloat, minA: Double, maxA: Double)] = [
            (170, 0.35, 0.75, 0.16, 0.42),
            (70, 0.60, 1.10, 0.30, 0.66),
            (20, 0.95, 1.65, 0.62, 0.95)
        ]

        for (layerIndex, layer) in layers.enumerated() {
            for _ in 0..<layer.count {
                let x = Double(nextRandom(&seed)) * Double(rect.width) + parallax * (0.4 + Double(layerIndex) * 0.3)
                let y = Double(nextRandom(&seed)) * Double(rect.height)
                let r = layer.minR + CGFloat(nextRandom(&seed)) * (layer.maxR - layer.minR)
                var alpha = layer.minA + nextRandom(&seed) * (layer.maxA - layer.minA)

                // 只有较亮的星闪，避免整片天空在抖
                if layerIndex > 0 {
                    let phase = nextRandom(&seed) * 6.283
                    alpha *= 0.82 + 0.18 * sin(time * 0.7 + phase)
                }

                let px = x.truncatingRemainder(dividingBy: Double(rect.width))
                let point = CGPoint(x: px < 0 ? px + Double(rect.width) : px, y: y)
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r,
                                           width: r * 2, height: r * 2)),
                    with: .color(.white.opacity(alpha)))

                // 亮星给一点十字光芒
                if layerIndex == 2, alpha > 0.80 {
                    let arm = r * 3.6
                    var cross = Path()
                    cross.move(to: CGPoint(x: point.x - arm, y: point.y))
                    cross.addLine(to: CGPoint(x: point.x + arm, y: point.y))
                    cross.move(to: CGPoint(x: point.x, y: point.y - arm))
                    cross.addLine(to: CGPoint(x: point.x, y: point.y + arm))
                    context.stroke(cross, with: .color(.white.opacity(0.16)), lineWidth: 0.5)
                }
            }
        }
    }

    // MARK: - 月亮

    private func drawMoon(in context: GraphicsContext, rect: CGRect, faint: Bool) {
        let base = min(rect.width, rect.height)
        let radius = base * (faint ? 0.042 : 0.052)
        let center = CGPoint(x: rect.width * 0.80, y: rect.height * (faint ? 0.14 : 0.17))
        let strength = faint ? 0.55 : 1.0

        // 光晕：三层，越外越淡
        for (index, scale) in [2.9, 1.9, 1.35].enumerated() {
            let r = radius * scale
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: radius * (1.4 - Double(index) * 0.32)))
                layer.fill(
                    Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                           width: r * 2, height: r * 2)),
                    with: .color(Color(red: 1.0, green: 0.97, blue: 0.88)
                        .opacity((faint ? 0.10 : 0.16) * strength / Double(index + 1))))
            }
        }

        let disc = CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)

        // 月面：左上受光
        context.fill(Path(ellipseIn: disc), with: .radialGradient(
            Gradient(stops: [
                .init(color: Color(red: 1.0, green: 0.995, blue: 0.975), location: 0),
                .init(color: Color(red: 0.965, green: 0.952, blue: 0.910), location: 0.45),
                .init(color: Color(red: 0.878, green: 0.862, blue: 0.812), location: 0.86),
                .init(color: Color(red: 0.800, green: 0.784, blue: 0.730), location: 1)
            ]),
            center: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.38),
            startRadius: 0, endRadius: radius * 1.45))

        // 环形山：几个软圆，位置固定，模拟月海的暗斑
        let craters: [(dx: Double, dy: Double, r: Double, a: Double)] = [
            (-0.30, -0.10, 0.26, 0.10),
            (0.18, -0.34, 0.18, 0.08),
            (0.28, 0.22, 0.22, 0.09),
            (-0.10, 0.38, 0.14, 0.07),
            (0.02, 0.06, 0.30, 0.06),
            (-0.44, 0.26, 0.12, 0.06)
        ]
        for crater in craters {
            let r = radius * crater.r
            let c = CGPoint(x: center.x + radius * crater.dx,
                            y: center.y + radius * crater.dy)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: r * 0.35))
                layer.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                           with: .color(Color(red: 0.62, green: 0.60, blue: 0.56)
                            .opacity(crater.a * strength)))
            }
        }

        // 月相：用一块暗椭圆从一侧盖过去，宽度随亮面比例变化
        let illumination = SolarPosition.moonIllumination(at: date)
        let shadowWidth = radius * 2 * (1 - illumination)
        if shadowWidth > 0.5 {
            let waxing = SolarPosition.moonPhase(at: date) < 0.5
            let shadowRect = CGRect(x: waxing ? disc.maxX - shadowWidth : disc.minX,
                                    y: disc.minY - radius * 0.02,
                                    width: shadowWidth,
                                    height: disc.height * 1.04)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: radius * 0.18))
                layer.clip(to: Path(ellipseIn: disc))
                layer.fill(Path(ellipseIn: shadowRect),
                           with: .color(Color(red: 0.045, green: 0.052, blue: 0.078)
                            .opacity(0.94)))
            }
        }

        // 边缘一圈薄亮，月亮才「浮」得起来
        context.stroke(Path(ellipseIn: disc),
                       with: .color(Color.white.opacity(faint ? 0.16 : 0.30)),
                       lineWidth: 0.7)
    }

    private func nextRandom(_ seed: inout UInt64) -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double((seed >> 33) & 0x7FFF_FFFF) / Double(0x7FFF_FFFF)
    }
}
