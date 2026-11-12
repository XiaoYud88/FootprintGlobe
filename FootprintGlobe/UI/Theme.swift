import SwiftUI

/// 外观模式：现在有五套（深空 / 日光 / 纸质地图 / 霓虹夜航 / 水墨），由用户在设置里手动切换。
enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case dark
    case light
    case paper
    case neon
    case ink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "深空"
        case .light: return "日光"
        case .paper: return "纸质地图"
        case .neon: return "霓虹夜航"
        case .ink: return "水墨"
        }
    }

    /// 分段控件里用短名，五个放得下
    var shortTitle: String {
        switch self {
        case .dark: return "深空"
        case .light: return "日光"
        case .paper: return "纸图"
        case .neon: return "霓虹"
        case .ink: return "水墨"
        }
    }

    var symbol: String {
        switch self {
        case .dark: return "moon.stars.fill"
        case .light: return "sun.max.fill"
        case .paper: return "map.fill"
        case .neon: return "sparkles"
        case .ink: return "paintbrush.pointed.fill"
        }
    }

    /// 一句话说明，设置页的 footer 用
    var hint: String {
        switch self {
        case .dark: return "深蓝夜空 + 发光城市，默认主题"
        case .light: return "米白纸面 + 深色文字，白天看着最舒服"
        case .paper: return "仿旧地图的牛皮纸色，像一本旅行手帐"
        case .neon: return "紫黑底 + 青色霓虹，晚上看最带感"
        case .ink: return "宣纸底 + 墨色远山 + 朱砂印记，像一幅没画完的山水"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .dark, .neon: return .dark
        case .light, .paper, .ink: return .light
        }
    }

    /// 「底色是浅的」——决定明暗描边、暗角强度这些二选一的取值
    var isLight: Bool {
        switch self {
        case .light, .paper, .ink: return true
        case .dark, .neon: return false
        }
    }
}

/// 主题：四套色板，视图里只写语义色（`Theme.brand` / `Theme.textSecondary`），
/// 切换外观时只改 `Theme.mode`，整棵视图树重建一次即可换肤。
enum Theme {
    /// 当前外观（由 AppModel 在启动和切换时写入）
    nonisolated(unsafe) static var mode: AppearanceMode = .dark

    static var isLight: Bool { mode.isLight }

    static var colorScheme: ColorScheme { mode.colorScheme }

    // MARK: - 色板定义

    struct Palette {
        let brand: Color
        let brandLight: Color
        let brandDim: Color
        let wish: Color
        let pending: Color
        let gold: Color

        let ocean: Color
        let oceanDeep: Color
        let land: Color
        let landDim: Color
        let border: Color
        let graticule: Color

        let textPrimary: Color
        let textSecondary: Color
        let textTertiary: Color

        let card: Color
        let cardElevated: Color

        /// 球体本体的上下渐变（不是海洋色，球比纸面深一点才有体积）
        let globeTop: Color
        let globeBottom: Color
        /// 大气辉光
        let atmosphere: Color
    }

    static let darkPalette = Palette(
        brand: Color(red: 0.42, green: 0.36, blue: 0.98),
        brandLight: Color(red: 0.62, green: 0.56, blue: 1.0),
        brandDim: Color(red: 0.42, green: 0.36, blue: 0.98).opacity(0.24),
        wish: Color(red: 0.20, green: 0.82, blue: 0.75),
        pending: Color(red: 0.95, green: 0.68, blue: 0.16),
        gold: Color(red: 0.98, green: 0.78, blue: 0.36),

        ocean: Color(red: 0.043, green: 0.055, blue: 0.086),
        oceanDeep: Color(red: 0.02, green: 0.025, blue: 0.045),
        land: Color(red: 0.16, green: 0.18, blue: 0.23),
        landDim: Color(red: 0.10, green: 0.12, blue: 0.16),
        border: Color(red: 0.40, green: 0.45, blue: 0.58),
        graticule: Color(red: 0.30, green: 0.36, blue: 0.50),

        textPrimary: .white,
        textSecondary: Color.white.opacity(0.62),
        textTertiary: Color.white.opacity(0.38),

        card: Color(red: 0.09, green: 0.10, blue: 0.14),
        cardElevated: Color(red: 0.13, green: 0.14, blue: 0.19),

        globeTop: Color(red: 0.075, green: 0.115, blue: 0.185),
        globeBottom: Color(red: 0.030, green: 0.052, blue: 0.105),
        atmosphere: Color(red: 0.32, green: 0.52, blue: 1.0)
    )

    static let lightPalette = Palette(
        brand: Color(red: 0.34, green: 0.27, blue: 0.86),
        brandLight: Color(red: 0.47, green: 0.39, blue: 0.95),
        brandDim: Color(red: 0.34, green: 0.27, blue: 0.86).opacity(0.16),
        wish: Color(red: 0.04, green: 0.56, blue: 0.50),
        pending: Color(red: 0.80, green: 0.51, blue: 0.06),
        gold: Color(red: 0.72, green: 0.53, blue: 0.13),

        ocean: Color(red: 0.965, green: 0.945, blue: 0.906),
        oceanDeep: Color(red: 0.937, green: 0.910, blue: 0.851),
        land: Color(red: 0.878, green: 0.847, blue: 0.780),
        landDim: Color(red: 0.827, green: 0.792, blue: 0.714),
        border: Color(red: 0.478, green: 0.435, blue: 0.349),
        graticule: Color(red: 0.706, green: 0.667, blue: 0.576),

        textPrimary: Color(red: 0.106, green: 0.129, blue: 0.180),
        textSecondary: Color(red: 0.106, green: 0.129, blue: 0.180).opacity(0.66),
        textTertiary: Color(red: 0.106, green: 0.129, blue: 0.180).opacity(0.42),

        card: Color(red: 0.996, green: 0.988, blue: 0.973),
        cardElevated: .white,

        globeTop: Color(red: 0.800, green: 0.860, blue: 0.920),
        globeBottom: Color(red: 0.860, green: 0.900, blue: 0.930),
        atmosphere: Color(red: 0.55, green: 0.72, blue: 1.0)
    )

    /// 纸质地图：牛皮纸 + 墨线 + 砖红标记，像把地球画在一张老地图上
    static let paperPalette = Palette(
        brand: Color(red: 0.706, green: 0.286, blue: 0.196),
        brandLight: Color(red: 0.827, green: 0.412, blue: 0.278),
        brandDim: Color(red: 0.706, green: 0.286, blue: 0.196).opacity(0.18),
        wish: Color(red: 0.157, green: 0.470, blue: 0.416),
        pending: Color(red: 0.741, green: 0.510, blue: 0.106),
        gold: Color(red: 0.639, green: 0.451, blue: 0.125),

        ocean: Color(red: 0.957, green: 0.929, blue: 0.867),
        oceanDeep: Color(red: 0.925, green: 0.890, blue: 0.812),
        land: Color(red: 0.867, green: 0.812, blue: 0.690),
        landDim: Color(red: 0.906, green: 0.867, blue: 0.769),
        border: Color(red: 0.451, green: 0.361, blue: 0.235),
        graticule: Color(red: 0.729, green: 0.667, blue: 0.529),

        textPrimary: Color(red: 0.196, green: 0.151, blue: 0.098),
        textSecondary: Color(red: 0.196, green: 0.151, blue: 0.098).opacity(0.68),
        textTertiary: Color(red: 0.196, green: 0.151, blue: 0.098).opacity(0.44),

        card: Color(red: 0.980, green: 0.961, blue: 0.914),
        cardElevated: Color(red: 1.0, green: 0.988, blue: 0.957),

        globeTop: Color(red: 0.914, green: 0.867, blue: 0.765),
        globeBottom: Color(red: 0.847, green: 0.792, blue: 0.671),
        atmosphere: Color(red: 0.706, green: 0.573, blue: 0.353)
    )

    /// 霓虹夜航：紫黑底 + 青色发光，晚上关灯看最漂亮
    static let neonPalette = Palette(
        brand: Color(red: 0.184, green: 0.937, blue: 0.847),
        brandLight: Color(red: 0.549, green: 1.0, blue: 0.949),
        brandDim: Color(red: 0.184, green: 0.937, blue: 0.847).opacity(0.20),
        wish: Color(red: 1.0, green: 0.353, blue: 0.725),
        pending: Color(red: 1.0, green: 0.808, blue: 0.286),
        gold: Color(red: 1.0, green: 0.878, blue: 0.478),

        ocean: Color(red: 0.031, green: 0.020, blue: 0.071),
        oceanDeep: Color(red: 0.012, green: 0.008, blue: 0.035),
        land: Color(red: 0.114, green: 0.078, blue: 0.212),
        landDim: Color(red: 0.075, green: 0.051, blue: 0.149),
        border: Color(red: 0.451, green: 0.302, blue: 0.851),
        graticule: Color(red: 0.353, green: 0.224, blue: 0.655),

        textPrimary: .white,
        textSecondary: Color.white.opacity(0.66),
        textTertiary: Color.white.opacity(0.40),

        card: Color(red: 0.075, green: 0.051, blue: 0.129),
        cardElevated: Color(red: 0.114, green: 0.078, blue: 0.188),

        globeTop: Color(red: 0.094, green: 0.055, blue: 0.196),
        globeBottom: Color(red: 0.035, green: 0.020, blue: 0.086),
        atmosphere: Color(red: 0.184, green: 0.937, blue: 0.847)
    )

    /// 水墨：宣纸 + 淡墨 + 朱砂。比「纸质地图」更素，红只剩一点点，像画上的落款印章
    static let inkPalette = Palette(
        brand: Color(red: 0.596, green: 0.196, blue: 0.169),
        brandLight: Color(red: 0.741, green: 0.263, blue: 0.216),
        brandDim: Color(red: 0.596, green: 0.196, blue: 0.169).opacity(0.14),
        wish: Color(red: 0.267, green: 0.322, blue: 0.310),
        pending: Color(red: 0.639, green: 0.522, blue: 0.235),
        gold: Color(red: 0.588, green: 0.451, blue: 0.176),

        ocean: Color(red: 0.961, green: 0.957, blue: 0.945),
        oceanDeep: Color(red: 0.925, green: 0.922, blue: 0.908),
        land: Color(red: 0.851, green: 0.847, blue: 0.835),
        landDim: Color(red: 0.898, green: 0.894, blue: 0.882),
        border: Color(red: 0.302, green: 0.302, blue: 0.302),
        graticule: Color(red: 0.694, green: 0.686, blue: 0.671),

        textPrimary: Color(red: 0.118, green: 0.118, blue: 0.129),
        textSecondary: Color(red: 0.118, green: 0.118, blue: 0.129).opacity(0.64),
        textTertiary: Color(red: 0.118, green: 0.118, blue: 0.129).opacity(0.40),

        card: Color(red: 0.988, green: 0.984, blue: 0.973),
        cardElevated: Color(red: 1.0, green: 0.996, blue: 0.988),

        globeTop: Color(red: 0.898, green: 0.894, blue: 0.882),
        globeBottom: Color(red: 0.824, green: 0.820, blue: 0.808),
        atmosphere: Color(red: 0.549, green: 0.580, blue: 0.596)
    )

    static var current: Palette {
        switch mode {
        case .dark: return darkPalette
        case .light: return lightPalette
        case .paper: return paperPalette
        case .neon: return neonPalette
        case .ink: return inkPalette
        }
    }

    // MARK: - 语义色（对外 API 保持不变）

    /// 品牌色：去过的地方
    static var brand: Color { current.brand }
    static var brandLight: Color { current.brandLight }
    static var brandDim: Color { current.brandDim }
    /// 想去
    static var wish: Color { current.wish }
    /// 待确认
    static var pending: Color { current.pending }
    /// 徽章金
    static var gold: Color { current.gold }

    static var ocean: Color { current.ocean }
    static var oceanDeep: Color { current.oceanDeep }
    static var land: Color { current.land }
    static var landDim: Color { current.landDim }
    static var border: Color { current.border }
    static var graticule: Color { current.graticule }

    static var textPrimary: Color { current.textPrimary }
    static var textSecondary: Color { current.textSecondary }
    static var textTertiary: Color { current.textTertiary }

    static var card: Color { current.card }
    static var cardElevated: Color { current.cardElevated }

    static var globeTop: Color { current.globeTop }
    static var globeBottom: Color { current.globeBottom }
    static var atmosphere: Color { current.atmosphere }

    /// 玻璃浮层的描边（浅色系两套都要淡，不能发光过头）
    static var hairline: Color {
        isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.10)
    }

    static var hairlineSoft: Color {
        isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.06)
    }

    static func fill(for status: VisitStatus?) -> Color {
        switch status {
        case .visited: return brand.opacity(isLight ? 0.22 : 0.26)
        case .wishlist: return wish.opacity(isLight ? 0.16 : 0.18)
        case .none: return landDim.opacity(0.30)
        }
    }

    static func stroke(for status: VisitStatus?) -> Color {
        switch status {
        case .visited: return brand.opacity(0.95)
        case .wishlist: return wish.opacity(0.85)
        case .none: return border.opacity(0.35)
        }
    }

    static func statusText(_ status: VisitStatus?) -> String {
        switch status {
        case .visited: return "去过"
        case .wishlist: return "想去"
        case .none: return "没去过"
        }
    }

    static func statusColor(_ status: VisitStatus?) -> Color {
        switch status {
        case .visited: return brand
        case .wishlist: return wish
        case .none: return textTertiary
        }
    }
}

// MARK: - 设计令牌
//
// 界面元素以后只会越来越多（时间线、徽章、统计、分享…），所以从这里开始
// 所有间距 / 圆角 / 字号都只引用令牌，不再在各处手写数字。
// 好处：加新组件时是「往槽位里塞」，而不是「重排一遍界面」。
extension Theme {
    enum Layout {
        /// 页面左右留白（顶部标题、底部 dock、弹窗内容共用同一套）
        static let pagePadding: CGFloat = 18
        /// 卡片之间的竖向间距
        static let sectionGap: CGFloat = 12
        /// 卡片圆角
        static let cardRadius: CGFloat = 18
        /// 小圆角（输入框、内嵌块）
        static let innerRadius: CGFloat = 12
        /// 顶部/底部悬浮控件的高度
        static let controlHeight: CGFloat = 40
        /// 圆形图标按钮直径
        static let iconButton: CGFloat = 36
        /// 底部 dock 的内边距
        static let dockPadding: CGFloat = 6
        /// 列表行内元素间距
        static let rowGap: CGFloat = 10
        /// 浮动控件与安全区的额外间距
        static let floatGap: CGFloat = 10
        /// 每个城市最多几张照片
        static let maxPhotosPerCity: Int = 3
        /// 头像直径（资料卡 / 首页都用这一档）
        static let avatar: CGFloat = 44
    }

    /// 字号体系：标题 / 副标题 / 标签 / 正文 / 注释，只允许这几档。
    enum Typo {
        static func largeTitle() -> Font { .system(size: 30, weight: .bold, design: .rounded) }
        static func title() -> Font { .system(size: 22, weight: .bold, design: .rounded) }
        static func subtitle() -> Font { .system(size: 11.5, weight: .medium, design: .rounded) }
        static func label() -> Font { .system(size: 13, weight: .semibold, design: .rounded) }
        static func body() -> Font { .system(size: 12.5, weight: .regular, design: .rounded) }
        static func caption() -> Font { .system(size: 11, weight: .regular, design: .rounded) }
        static func number() -> Font { .system(size: 15, weight: .bold, design: .rounded) }
        static func bigNumber() -> Font { .system(size: 26, weight: .bold, design: .rounded) }
    }
}

// MARK: - 通用卡片修饰器

extension View {
    /// 标准卡片容器：后面加任何新卡片直接套这个，不用再写圆角和内边距。
    func themeCard(padding: CGFloat = 14, elevated: Bool = false) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(elevated ? Theme.cardElevated : Theme.card,
                        in: RoundedRectangle(cornerRadius: Theme.Layout.cardRadius,
                                             style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cardRadius, style: .continuous)
                    .stroke(Theme.hairlineSoft, lineWidth: 1)
            )
    }
}
