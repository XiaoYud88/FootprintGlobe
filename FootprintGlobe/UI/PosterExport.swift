import SwiftUI
import UIKit
import Photos

/// 足迹海报：把「我去过多少、走到哪儿」压成一张能发出去的图。
///
/// 做法是把地球（同一个 `GlobeView`，同一套投影和边界数据）画进一张固定的画布，
/// 再用 `ImageRenderer` 以 3 倍渲染出 PNG。不截屏、不拼视频，所以图片在任何尺寸下都清楚。
struct PosterData {
    var stats: TravelStats
    var provinces: [Region] = []
    var visitedProvinceCodes: Set<String> = []
    var visitedCities: [Region] = []
    var pendingCities: [Region] = []
    var countries: [WorldCountry] = []
    var center: GeoCoord = GeoCoord(lon: 105, lat: 30)
    var sun: GeoCoord = GeoCoord(lon: 0, lat: 0)
    var unlockedBadges: Int = 0
    var totalBadges: Int = BadgeCatalog.total
    var generatedAt: Date = Date()
    var version: String = "0.4.0"
}

// MARK: - 海报画布

struct PosterView: View {
    let data: PosterData

    /// 海报固定走深色，跟 App 当前主题无关——深底上的发光点更好看，也更像「一张图」
    private enum Palette {
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.66)
        static let textTertiary = Color.white.opacity(0.38)
        static let accent = Color(red: 0.62, green: 0.56, blue: 1.0)
        static let gold = Color(red: 0.98, green: 0.78, blue: 0.36)
        static let card = Color.white.opacity(0.055)
        static let hairline = Color.white.opacity(0.10)
    }

    private var stats: TravelStats { data.stats }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                globe
                numbers.padding(.top, 6)
                extremes.padding(.top, 16)
                coverage.padding(.top, 14)
                footer.padding(.top, 18)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 22)
        }
        .frame(width: 360)
    }

    // MARK: 背景

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.075, green: 0.085, blue: 0.165),
                                    Color(red: 0.020, green: 0.024, blue: 0.055),
                                    Color(red: 0.008, green: 0.010, blue: 0.026)],
                           startPoint: .top, endPoint: .bottom)
            // 顶部一层淡紫光，避免纯黑太闷
            RadialGradient(colors: [Color(red: 0.45, green: 0.36, blue: 0.95).opacity(0.20), .clear],
                           center: UnitPoint(x: 0.5, y: -0.05),
                           startRadius: 0, endRadius: 300)
            Canvas { context, size in
                var seed: UInt64 = 20_241_112
                for index in 0..<90 {
                    let x = nextRandom(&seed) * size.width
                    let y = nextRandom(&seed) * size.height
                    let alpha = 0.10 + nextRandom(&seed) * 0.42
                    let r = 0.5 + nextRandom(&seed) * 1.0
                    let rect = CGRect(x: x, y: y, width: r, height: r)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
                    _ = index
                }
            }
        }
        .ignoresSafeArea()
    }

    private func nextRandom(_ seed: inout UInt64) -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let value = (seed >> 11) & 0x1F_FFFF_FFFF_FFFF
        return Double(value) / Double(0x20_0000_0000_0000)
    }

    // MARK: 顶部

    private var header: some View {
        VStack(spacing: 7) {
            Text("FOOTPRINT GLOBE")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(3.4)
                .foregroundColor(Palette.textTertiary)

            Text(TravelRank.title(for: stats.cityCount))
                .font(.system(size: 31, weight: .heavy, design: .rounded))
                .foregroundColor(Palette.textPrimary)

            Text(subtitle)
                .font(.system(size: 11.5, weight: .regular, design: .rounded))
                .foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let first = stats.earliestYear {
            parts.append("自 \(first) 年起")
        }
        parts.append("\(stats.cityCount) 座城市")
        parts.append("\(stats.provinceCount) 个省级")
        return parts.joined(separator: " · ")
    }

    // MARK: 地球

    private var globe: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Palette.accent.opacity(0.22), .clear],
                                     center: .center, startRadius: 10, endRadius: 150))
                .frame(width: 300, height: 300)
                .blur(radius: 12)

            GlobeView(center: data.center,
                      radiusFactor: 0.45,
                      provinces: data.provinces,
                      visitedProvinceCodes: data.visitedProvinceCodes,
                      visitedCities: data.visitedCities,
                      pendingCities: data.pendingCities,
                      focus: nil,
                      countries: data.countries,
                      sun: data.sun,
                      appearance: .dark)
                .frame(width: 292, height: 292)
        }
        .padding(.top, 10)
    }

    // MARK: 四个数字

    private var numbers: some View {
        HStack(spacing: 8) {
            numberTile("\(stats.cityCount)", "城市")
            numberTile("\(stats.provinceCount)", "省级")
            numberTile("\(stats.storyCount)", "故事")
            numberTile("\(stats.photoCount)", "照片")
        }
    }

    private func numberTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundColor(Palette.textPrimary)
            Text(label)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundColor(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    // MARK: 四极

    private var extremes: some View {
        VStack(spacing: 8) {
            HStack {
                Text("四极")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(Palette.textTertiary)
                Spacer()
                if stats.yearSpan > 0 {
                    Text("记录跨度 \(stats.yearSpan) 年")
                        .font(.system(size: 9.5, weight: .regular, design: .rounded))
                        .foregroundColor(Palette.textTertiary)
                }
            }
            HStack(spacing: 8) {
                extremeTile("最北", stats.north)
                extremeTile("最南", stats.south)
                extremeTile("最东", stats.east)
                extremeTile("最西", stats.west)
            }
        }
    }

    private func extremeTile(_ title: String, _ city: ExtremeCity?) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundColor(Palette.textTertiary)
            Text(city?.region.name ?? "—")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(city == nil ? Palette.textTertiary : Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: 覆盖率

    private var coverage: some View {
        VStack(spacing: 9) {
            barRow("面积覆盖", detail: stats.areaRatioText, value: stats.areaRatio)
            barRow("徽章", detail: "\(data.unlockedBadges)/\(data.totalBadges)",
                   value: data.totalBadges > 0 ? Double(data.unlockedBadges) / Double(data.totalBadges) : 0)
        }
    }

    private func barRow(_ title: String, detail: String, value: Double) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(Palette.textSecondary)
                Spacer()
                Text(detail)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(Palette.accent)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.hairline)
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.accent.opacity(0.7), Palette.accent],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, geo.size.width * min(1, max(0, value))))
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: 底部

    private var footer: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 0.8)
            HStack {
                Text("足迹地球 \(data.version)")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundColor(Palette.textTertiary)
                Spacer()
                Text(data.generatedAt.formatted(.dateTime.year().month().day()))
                    .font(.system(size: 8.5, weight: .regular, design: .rounded))
                    .foregroundColor(Palette.textTertiary)
            }
        }
    }
}

// MARK: - 渲染 & 分享

enum PosterRenderer {
    /// 渲染成 PNG 图片。固定深色渲染，画完把主题还原回去。
    @MainActor
    static func render(_ data: PosterData) -> UIImage? {
        let previous = Theme.mode
        Theme.mode = .dark
        defer { Theme.mode = previous }

        let renderer = ImageRenderer(content: PosterView(data: data))
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// 系统分享面板
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 海报预览 + 分享 / 存相册
struct PosterSheet: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false
    @State private var saved = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                ScrollView {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }

                HStack(spacing: 10) {
                    actionButton(saved ? "已存入相册" : "存到相册",
                                 symbol: saved ? "checkmark.circle.fill" : "photo.badge.plus") {
                        saveToAlbum()
                    }
                    actionButton("分享", symbol: "square.and.arrow.up") {
                        showShare = true
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .background(Theme.oceanDeep.ignoresSafeArea())
            .navigationTitle("足迹海报")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(Theme.Typo.label())
                }
            }
            .sheet(isPresented: $showShare) {
                ActivityView(items: [image])
            }
            .alert("没能存进相册", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } })) {
                Button("好", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
        .preferredColorScheme(Theme.colorScheme)
    }

    private func actionButton(_ title: String, symbol: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Layout.controlHeight)
                .background(Theme.brand.opacity(0.9),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(.white)
        }
        .buttonStyle(.plain)
    }

    private func saveToAlbum() {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                errorText = "没有相册写入权限。可以到「设置 → 足迹地球 → 照片」里打开，或者直接用「分享」存到别处。"
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                saved = true
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
