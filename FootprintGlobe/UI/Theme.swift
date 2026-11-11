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
