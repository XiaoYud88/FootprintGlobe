import SwiftUI

/// 外观模式：只做「深色 / 浅色」两套，由用户在设置里手动切换（不跟随系统）。
enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "深色"
        case .light: return "浅色"
        }
    }

    var symbol: String {
        switch self {
        case .dark: return "moon.stars.fill"
        case .light: return "sun.max.fill"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .dark: return .dark
        case .light: return .light
        }
    }
}

/// 主题：一套色板 + 两套取值。
///
/// 用法不变：视图里继续写 `Theme.brand` / `Theme.textSecondary`，
/// 切换外观时只改 `Theme.mode`，整棵视图树重建一次即可换肤。
enum Theme {
    /// 当前外观（由 AppModel 在启动和切换时写入）
    nonisolated(unsafe) static var mode: AppearanceMode = .dark

    static var isLight: Bool { mode == .light }

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
        cardElevated: Color(red: 0.13, green: 0.14, blue: 0.19)
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
        cardElevated: .white
    )

    static var current: Palette { mode == .light ? lightPalette : darkPalette }

    // MARK: - 语义色（对外 API 保持不变）

    /// 品牌紫：去过的地方
    static var brand: Color { current.brand }
    static var brandLight: Color { current.brandLight }
    static var brandDim: Color { current.brandDim }
    /// 想去：青
    static var wish: Color { current.wish }
    /// 待确认：琥珀
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

    /// 玻璃浮层的描边（深浅两套都要淡，不能发光过头）
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
