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
        switch appearance {
        case .light:
            drawDaylight(in: context, rect: rect, paper: false)
            drawMoon(in: context, rect: rect, faint: true)
        case .paper:
            drawDaylight(in: context, rect: rect, paper: true)
            drawPaperGrain(in: context, rect: rect)
            drawMoon(in: context, rect: rect, faint: true)
        case .dark:
            drawNight(in: context, size: size, rect: rect, time: time, neon: false)
        case .neon:
            drawNight(in: context, size: size, rect: rect, time: time, neon: true)
        case .ink:
            drawInk(in: context, rect: rect)
        }
    }

    // MARK: - 水墨：宣纸 + 远山 + 朱印

    private func drawInk(in context: GraphicsContext, rect: CGRect) {
        // 宣纸：中间亮、四角略暗，像纸被灯光从上方照着
        context.fill(Path(rect), with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.980, green: 0.976, blue: 0.965), location: 0.0),
                .init(color: Color(red: 0.957, green: 0.953, blue: 0.941), location: 0.55),
                .init(color: Color(red: 0.910, green: 0.906, blue: 0.894), location: 1.0)
            ]),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: rect.width * 0.6, y: rect.height)))

        // 三层远山：越远越淡、越糊，像毛笔蘸水扫出来的
        drawInkRidge(in: context, rect: rect, baseY: 0.90, height: 0.16,
                     alpha: 0.16, blur: 9, seed: 0x1A31_5C07)
        drawInkRidge(in: context, rect: rect, baseY: 0.96, height: 0.13,
                     alpha: 0.22, blur: 6, seed: 0x2A3F)
        drawInkRidge(in: context, rect: rect, baseY: 1.04, height: 0.11,
                     alpha: 0.30, blur: 3, seed: 0x51C7)

        // 一轮淡墨日：几乎只是个影子
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: rect.width * 0.012))
            layer.fill(
                Path(ellipseIn: CGRect(x: rect.width * 0.66, y: rect.height * 0.10,
                                       width: rect.width * 0.20, height: rect.width * 0.20)),
                with: .radialGradient(
                    Gradient(colors: [Color(red: 0.42, green: 0.42, blue: 0.44).opacity(0.16),
                                      Color(red: 0.42, green: 0.42, blue: 0.44).opacity(0.05)]),
                    center: CGPoint(x: rect.width * 0.76, y: rect.height * 0.10 + rect.width * 0.10),
                    startRadius: 0, endRadius: rect.width * 0.13))
        }

        // 右下角一方朱印，只有这一点颜色
        let seal = CGRect(x: rect.width - 46, y: rect.height - 52, width: 26, height: 26)
        context.fill(Path(roundedRect: seal, cornerRadius: 3),
                     with: .color(Color(red: 0.70, green: 0.20, blue: 0.16).opacity(0.82)))
        var mark = Path()
        mark.move(to: CGPoint(x: seal.minX + 7, y: seal.midY))
        mark.addLine(to: CGPoint(x: seal.maxX - 7, y: seal.midY))
        mark.move(to: CGPoint(x: seal.midX, y: seal.minY + 6))
        mark.addLine(to: CGPoint(x: seal.midX, y: seal.maxY - 6))
        context.stroke(mark, with: .color(Color(red: 0.99, green: 0.96, blue: 0.94).opacity(0.85)),
                       lineWidth: 1.6)
    }

    /// 一条起伏的山脊线，填到画面底部
    private func drawInkRidge(in context: GraphicsContext, rect: CGRect, baseY: Double,
                              height: Double, alpha: Double, blur: Double, seed base: UInt64) {
        var seed = base
        var path = Path()
        let startY = rect.height * baseY
        path.move(to: CGPoint(x: 0, y: startY))
        let steps = 26
        var frequencies: [Double] = []
        for _ in 0..<steps { frequencies.append(nextRandom(&seed)) }
        let amplitude = rect.height * height
        for index in 0...steps {
            let x = rect.width * Double(index) / Double(steps)
            let wave = sin(Double(index) * 0.9 + frequencies[index] * 2.4) * 0.55
                + sin(Double(index) * 0.37 + frequencies[index] * 5.1) * 0.45
            path.addLine(to: CGPoint(x: x, y: startY - amplitude * wave))
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: blur))
            layer.fill(path, with: .color(Color(red: 0.16, green: 0.16, blue: 0.17).opacity(alpha)))
        }
    }

    // MARK: - 夜晚：深空 / 霓虹

    private func drawNight(in context: GraphicsContext, size: CGSize, rect: CGRect,
                           time: TimeInterval, neon: Bool) {
        // 底色：不是纯黑，四个角的色温略有差别；霓虹版换成偏紫的底
        let stops: [Gradient.Stop] = neon
            ? [.init(color: Color(red: 0.055, green: 0.024, blue: 0.110), location: 0.0),
               .init(color: Color(red: 0.028, green: 0.014, blue: 0.070), location: 0.45),
               .init(color: Color(red: 0.008, green: 0.005, blue: 0.028), location: 1.0)]
            : [.init(color: Color(red: 0.035, green: 0.045, blue: 0.094), location: 0.0),
               .init(color: Color(red: 0.024, green: 0.030, blue: 0.068), location: 0.45),
               .init(color: Color(red: 0.010, green: 0.012, blue: 0.030), location: 1.0)]
        context.fill(Path(rect), with: .linearGradient(
            Gradient(stops: stops),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: size.width * 0.7, y: size.height)))

        // 两团星云，非常淡，只是让底色不平
        drawNebula(in: context, rect: rect,
                   center: CGPoint(x: size.width * 0.16, y: size.height * 0.30),
                   radius: size.width * 0.75,
                   color: neon ? Color(red: 1.0, green: 0.24, blue: 0.72)
                               : Color(red: 0.36, green: 0.24, blue: 0.62),
                   alpha: neon ? 0.16 : 0.13)
        drawNebula(in: context, rect: rect,
                   center: CGPoint(x: size.width * 0.92, y: size.height * 0.72),
                   radius: size.width * 0.62,
                   color: neon ? Color(red: 0.10, green: 0.94, blue: 0.86)
                               : Color(red: 0.12, green: 0.42, blue: 0.58),
                   alpha: neon ? 0.14 : 0.10)

        drawMilkyWay(in: context, rect: rect, neon: neon)
        drawStars(in: context, rect: rect, time: time, neon: neon)
        drawMoon(in: context, rect: rect, faint: false)
    }

    // MARK: - 浅色：清晨的纸 / 牛皮纸

    private func drawDaylight(in context: GraphicsContext, rect: CGRect, paper: Bool) {
        let stops: [Gradient.Stop] = paper
            ? [.init(color: Color(red: 0.980, green: 0.965, blue: 0.925), location: 0.0),
               .init(color: Color(red: 0.957, green: 0.933, blue: 0.874), location: 0.5),
               .init(color: Color(red: 0.898, green: 0.863, blue: 0.784), location: 1.0)]
            : [.init(color: Color(red: 0.996, green: 0.984, blue: 0.960), location: 0.0),
               .init(color: Color(red: 0.968, green: 0.962, blue: 0.958), location: 0.5),
               .init(color: Color(red: 0.912, green: 0.922, blue: 0.940), location: 1.0)]
        context.fill(Path(rect), with: .linearGradient(
            Gradient(stops: stops),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: rect.width, y: rect.height)))

        // 左上一点暖光，像窗外天亮了
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: rect.width * 0.22))
            layer.fill(
                Path(ellipseIn: CGRect(x: -rect.width * 0.25, y: -rect.height * 0.20,
                                       width: rect.width * 0.95, height: rect.width * 0.95)),
                with: .radialGradient(
                    Gradient(colors: [Color(red: 1.0, green: 0.94, blue: 0.82)
                        .opacity(paper ? 0.95 : 0.85), .clear]),
                    center: CGPoint(x: rect.width * 0.22, y: rect.height * 0.16),
                    startRadius: 0, endRadius: rect.width * 0.55))
        }
    }

    /// 纸纹：几百个极淡的褐点，让「纸质地图」看着像真纸而不是纯色块
    private func drawPaperGrain(in context: GraphicsContext, rect: CGRect) {
        var seed: UInt64 = 0x0FA1_7E3C_5B2D_9911
        for _ in 0..<420 {
            let x = CGFloat(nextRandom(&seed)) * rect.width
            let y = CGFloat(nextRandom(&seed)) * rect.height
            let r = 0.4 + CGFloat(nextRandom(&seed)) * 0.9
            let alpha = 0.018 + nextRandom(&seed) * 0.030
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                         with: .color(Color(red: 0.36, green: 0.28, blue: 0.16).opacity(alpha)))
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

    private func drawMilkyWay(in context: GraphicsContext, rect: CGRect, neon: Bool) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let band = neon ? Color(red: 0.70, green: 0.60, blue: 1.0)
                        : Color(red: 0.80, green: 0.84, blue: 1.0)
        let bandDim = neon ? Color(red: 0.92, green: 0.36, blue: 0.86)
                           : Color(red: 0.62, green: 0.70, blue: 0.95)
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
                            .init(color: band.opacity((neon ? 0.11 : 0.085) - Double(index) * 0.02),
                                  location: 0),
                            .init(color: bandDim.opacity((neon ? 0.06 : 0.045) - Double(index) * 0.01),
                                  location: 0.6),
                            .init(color: .clear, location: 1)
                        ]),
                        center: .zero, startRadius: 0, endRadius: w))
            }
        }
    }

    // MARK: - 星点

    private func drawStars(in context: GraphicsContext, rect: CGRect,
                           time: TimeInterval, neon: Bool) {
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
                let starColor = neon ? Color(red: 0.80, green: 1.0, blue: 0.98) : .white
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r,
                                           width: r * 2, height: r * 2)),
                    with: .color(starColor.opacity(alpha)))

                // 亮星给一点十字光芒
                if layerIndex == 2, alpha > 0.80 {
                    let arm = r * 3.6
                    var cross = Path()
                    cross.move(to: CGPoint(x: point.x - arm, y: point.y))
                    cross.addLine(to: CGPoint(x: point.x + arm, y: point.y))
                    cross.move(to: CGPoint(x: point.x, y: point.y - arm))
                    cross.addLine(to: CGPoint(x: point.x, y: point.y + arm))
                    context.stroke(cross, with: .color(starColor.opacity(0.16)), lineWidth: 0.5)
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
