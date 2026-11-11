import SwiftUI

enum Theme {
    /// 品牌紫：去过的地方
    static let brand = Color(red: 0.42, green: 0.36, blue: 0.98)
    static let brandLight = Color(red: 0.62, green: 0.56, blue: 1.0)
    static let brandDim = Color(red: 0.42, green: 0.36, blue: 0.98).opacity(0.24)
    /// 想去：青
    static let wish = Color(red: 0.20, green: 0.82, blue: 0.75)
    /// 待确认：琥珀
    static let pending = Color(red: 0.95, green: 0.68, blue: 0.16)

    static let ocean = Color(red: 0.043, green: 0.055, blue: 0.086)
    static let oceanDeep = Color(red: 0.02, green: 0.025, blue: 0.045)
    static let land = Color(red: 0.16, green: 0.18, blue: 0.23)
    static let landDim = Color(red: 0.10, green: 0.12, blue: 0.16)
    static let border = Color(red: 0.40, green: 0.45, blue: 0.58)
    static let graticule = Color(red: 0.30, green: 0.36, blue: 0.50)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)

    static let card = Color(red: 0.09, green: 0.10, blue: 0.14)

    static func fill(for status: VisitStatus?) -> Color {
        switch status {
        case .visited: return brand.opacity(0.26)
        case .wishlist: return wish.opacity(0.18)
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
    }

    /// 字号体系：标题 / 副标题 / 标签 / 正文 / 注释，只允许这五档。
    enum Typo {
        static func title() -> Font { .system(size: 22, weight: .bold, design: .rounded) }
        static func subtitle() -> Font { .system(size: 11.5, weight: .medium, design: .rounded) }
        static func label() -> Font { .system(size: 13, weight: .semibold, design: .rounded) }
        static func body() -> Font { .system(size: 12.5, weight: .regular, design: .rounded) }
        static func caption() -> Font { .system(size: 11, weight: .regular, design: .rounded) }
        static func number() -> Font { .system(size: 15, weight: .bold, design: .rounded) }
    }
}
