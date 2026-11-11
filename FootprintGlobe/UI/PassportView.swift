import SwiftUI

/// 护照页：把「我去过多少、走到哪、拿到了什么」一次说清楚。
///
/// 这是 M1 新加的一整屏（不是塞在设置里），读完要让人有成就感：
/// 顶部是称号 + 距离下一级还差多少，中间是四个数字和四极，下面是徽章墙和省份进度。
struct PassportView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var onlyUnlocked = false

    private var stats: TravelStats { app.stats }
    private var badges: [BadgeState] { app.badges(for: stats) }

    private var shownBadges: [BadgeState] {
        onlyUnlocked ? badges.filter { $0.unlocked } : badges
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Layout.sectionGap) {
                    rankCard
                    numbersRow
                    extremesCard
                    coverageCard
                    regionCard
                    badgeWall
                    provinceProgressCard
                    footerNote
                }
                .padding(.horizontal, Theme.Layout.pagePadding)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .background(Theme.oceanDeep.ignoresSafeArea())
            .navigationTitle("足迹护照")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .font(Theme.Typo.label())
                }
            }
        }
        .preferredColorScheme(Theme.colorScheme)
    }

    // MARK: - 顶部称号

    private var rankCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(TravelRank.title(for: stats.cityCount))
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("足迹地球 · 第 \(max(1, stats.earliestYear ?? 1)) 年起")
                        .font(Theme.Typo.caption())
                        .foregroundColor(.white.opacity(0.72))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(stats.cityCount)")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("座城市")
                        .font(Theme.Typo.caption())
                        .foregroundColor(.white.opacity(0.72))
                }
            }

            if let next = TravelRank.nextThreshold(for: stats.cityCount) {
                VStack(alignment: .leading, spacing: 5) {
                    ProgressBar(value: Double(stats.cityCount) / Double(next))
                        .frame(height: 6)
                    Text("再走 \(next - stats.cityCount) 座城市，升级为「\(TravelRank.title(for: next))」")
                        .font(Theme.Typo.caption())
                        .foregroundColor(.white.opacity(0.8))
                }
            } else {
                Text("已经走到称号体系的顶端，接下来只是更多故事。")
                    .font(Theme.Typo.caption())
                    .foregroundColor(.white.opacity(0.8))
            }

            HStack(spacing: 6) {
                Image(systemName: "rosette")
                    .font(.system(size: 11, weight: .bold))
                Text("徽章 \(unlockedCount)/\(BadgeCatalog.total)")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.18), in: Capsule())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.brand, Theme.brandDim],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Theme.Layout.cardRadius, style: .continuous))
        .shadow(color: Theme.brand.opacity(0.35), radius: 14, y: 6)
    }

    private var unlockedCount: Int { badges.filter { $0.unlocked }.count }

    // MARK: - 四个数字

    private var numbersRow: some View {
        HStack(spacing: 8) {
            numberTile("城市", "\(stats.cityCount)", "building.2.fill", Theme.brandLight)
            numberTile("省级", "\(stats.provinceCount)", "map.fill", Theme.wish)
            numberTile("故事", "\(stats.storyCount)", "text.book.closed.fill", Theme.pending)
            numberTile("照片", "\(stats.photoCount)", "photo.stack.fill", Theme.gold)
        }
    }

    private func numberTile(_ title: String, _ value: String,
                            _ symbol: String, _ tint: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
            Text(value)
                .font(Theme.Typo.bigNumber())
                .foregroundColor(Theme.textPrimary)
            Text(title)
                .font(Theme.Typo.caption())
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Layout.innerRadius,
                                                     style: .continuous))
    }

    // MARK: - 四极

    private var extremesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("四极", trailing: stats.yearSpan > 0 ? "记录跨度 \(stats.yearSpan) 年" : nil)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)], spacing: 8) {
                extremeTile("最北", stats.north, "arrow.up", axis: .lat)
                extremeTile("最南", stats.south, "arrow.down", axis: .lat)
                extremeTile("最东", stats.east, "arrow.right", axis: .lon)
                extremeTile("最西", stats.west, "arrow.left", axis: .lon)
            }
        }
        .themeCard()
    }

    private enum Axis { case lat, lon }

    private func extremeTile(_ title: String, _ city: ExtremeCity?,
                             _ symbol: String, axis: Axis) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            }
            .foregroundColor(Theme.textTertiary)

            Text(city?.region.name ?? "—")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(city == nil ? Theme.textTertiary : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let city {
                let c = city.region.center
                Text(axis == .lat
                     ? String(format: "%.1f°%@", abs(c.lat), c.lat >= 0 ? "N" : "S")
                     : String(format: "%.1f°%@", abs(c.lon), c.lon >= 0 ? "E" : "W"))
                    .font(Theme.Typo.caption())
                    .foregroundColor(Theme.textSecondary)
            } else {
                Text("还没记录")
                    .font(Theme.Typo.caption())
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.landDim.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - 覆盖率

    private var coverageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("覆盖率", trailing: "已点亮 \(stats.areaText)")

            ratioRow("城市", value: stats.cityRatio,
                     detail: "\(stats.cityCount)/\(stats.totalCityCount)")
            ratioRow("省级", value: stats.provinceRatio,
                     detail: "\(stats.provinceCount)/\(stats.totalProvinceCount)")
            ratioRow("面积", value: stats.areaRatio,
                     detail: stats.areaRatioText)

            Text("面积按球面多边形算，分母是中国 + 日本的可点亮面积；南极、北极单独算。")
                .font(Theme.Typo.caption())
                .foregroundColor(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .themeCard()
    }

    private func ratioRow(_ title: String, value: Double, detail: String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(Theme.Typo.label())
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Text(detail)
                    .font(Theme.Typo.caption())
                    .foregroundColor(Theme.textSecondary)
            }
            ProgressBar(value: value)
                .frame(height: 5)
        }
    }

    // MARK: - 特殊地区

    private var regionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("特别的地方", trailing: nil)

            regionRow(title: "日本",
                      symbol: "sailboat.fill",
                      detail: stats.japanCount > 0
                        ? "已点亮 \(stats.japanCount) / \(app.boundary.japanCities.count) 都道府县"
                        : "47 个都道府县，一个都还没记",
                      reached: stats.japanCount > 0,
                      region: app.boundary.japanProvince)

            regionRow(title: "南极洲",
                      symbol: "pawprint.fill",
                      detail: stats.hasAntarctica ? "已记录" : "第七大陆，还没去过",
                      reached: stats.hasAntarctica,
                      region: app.boundary.antarcticaCity ?? app.boundary.antarcticaProvince)

            regionRow(title: "北极地区",
                      symbol: "moon.stars.fill",
                      detail: stats.hasArctic ? "已记录" : "极夜、极光、北冰洋",
                      reached: stats.hasArctic,
                      region: app.boundary.arcticCity)
        }
        .themeCard()
    }

    private func regionRow(title: String, symbol: String, detail: String,
                           reached: Bool, region: Region?) -> some View {
        Button {
            guard let region else { return }
            app.fly(to: region)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(reached ? Theme.brandLight : Theme.textTertiary)
                    .frame(width: 26, height: 26)
                    .background(Theme.landDim, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Theme.Typo.label())
                        .foregroundColor(Theme.textPrimary)
                    Text(detail)
                        .font(Theme.Typo.caption())
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 徽章墙

    private var badgeWall: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("徽章", trailing: "\(unlockedCount)/\(BadgeCatalog.total)")
                Spacer(minLength: 8)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { onlyUnlocked.toggle() }
                } label: {
                    Text(onlyUnlocked ? "看全部" : "只看已得")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.brandLight)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Theme.landDim, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                      spacing: 10) {
                ForEach(shownBadges) { state in
                    badgeCell(state)
                }
            }

            if shownBadges.isEmpty {
                Text("还没有解锁的徽章，去点亮第一座城市吧。")
                    .font(Theme.Typo.caption())
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
            }
        }
        .themeCard()
    }

    private func badgeCell(_ state: BadgeState) -> some View {
        let tint = tierColor(state.definition.tier)
        return VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(state.unlocked ? tint.opacity(0.20) : Theme.landDim)
                    .frame(width: 44, height: 44)
                Circle()
                    .stroke(state.unlocked ? tint.opacity(0.85) : Theme.hairline, lineWidth: 1.2)
                    .frame(width: 44, height: 44)
                Image(systemName: state.definition.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(state.unlocked ? tint : Theme.textTertiary)
                if !state.unlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.textTertiary)
                        .offset(x: 15, y: 15)
                }
            }
            Text(state.definition.title)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundColor(state.unlocked ? Theme.textPrimary : Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(state.unlocked ? state.definition.detail : state.progressText)
                .font(.system(size: 8.5, weight: .regular, design: .rounded))
                .foregroundColor(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !state.unlocked, state.progress > 0 {
                ProgressBar(value: state.progress)
                    .frame(height: 2.5)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tierColor(_ tier: Int) -> Color {
        switch tier {
        case 3: return Theme.gold
        case 2: return Theme.textSecondary
        default: return Color(red: 0.80, green: 0.53, blue: 0.34)   // 铜
        }
    }

    // MARK: - 省份进度

    private var provinceProgressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("省份进度",
                        trailing: stats.fullProvinces.isEmpty
                            ? nil
                            : "全省点亮 \(stats.fullProvinces.count) 个")

            ForEach(stats.provinceProgress.prefix(40)) { row in
                VStack(spacing: 3) {
                    HStack {
                        Text(row.region.name)
                            .font(Theme.Typo.caption())
                            .foregroundColor(row.visited > 0 ? Theme.textPrimary : Theme.textSecondary)
                        if row.isFull {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 9))
                                .foregroundColor(Theme.gold)
                        }
                        Spacer()
                        Text(row.total > 0 ? "\(row.visited)/\(row.total)" : "—")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.textTertiary)
                    }
                    ProgressBar(value: row.ratio)
                        .frame(height: 3.5)
                }
            }
        }
        .themeCard()
    }

    private var footerNote: some View {
        Text("徽章只在本地判定，不上传任何数据。照片最多每城 3 张，且不会出现在地球和地图上。")
            .font(Theme.Typo.caption())
            .foregroundColor(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    // MARK: - 工具

    private func sectionTitle(_ text: String, trailing: String?) -> some View {
        HStack {
            Text(text)
                .font(Theme.Typo.caption())
                .foregroundColor(Theme.textSecondary)
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(Theme.Typo.caption())
                    .foregroundColor(Theme.brandLight)
            }
        }
    }
}

/// 统一的细进度条，护照页里到处都在用。
struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.landDim)
                Capsule()
                    .fill(LinearGradient(colors: [Theme.brand, Theme.brandLight],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(2, geo.size.width * min(1, max(0, value))))
            }
        }
    }
}
