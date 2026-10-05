import SwiftUI

// MARK: - Colors

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    /// 动态颜色（浅色/深色）
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }

    // 品牌
    static let vPrimary = Color(hex: 0xE8322A)          // 赛道红
    static let vPrimaryDark = Color(hex: 0xC4261F)
    static let vPrimarySoft = dynamic(light: 0xFDECEB, dark: 0x3A1B19)
    static let vGold = Color(hex: 0xF5A524)               // 领先 / 高亮
    static let vGreen = Color(hex: 0x1DB06A)
    static let vBlue = Color(hex: 0x3478F6)
    static let vCarbon = Color(hex: 0x1C1C1E)

    // 背景与分层
    static let vBackground = dynamic(light: 0xF6F7F9, dark: 0x000000)
    static let vSurface = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let vSurfaceElevated = dynamic(light: 0xFFFFFF, dark: 0x2C2C2E)
    static let vFill = dynamic(light: 0xF0F1F4, dark: 0x2C2C2E)
    static let vFillStrong = dynamic(light: 0xE4E6EB, dark: 0x3A3A3C)
    static let vSeparator = dynamic(light: 0xEBECF0, dark: 0x38383A)

    // 文本
    static let vText = dynamic(light: 0x111318, dark: 0xF5F5F7)
    static let vTextSecondary = dynamic(light: 0x5C6270, dark: 0xA1A1A6)
    static let vTextTertiary = dynamic(light: 0x9AA0AD, dark: 0x6E6E73)
    static let vPrice = Color(hex: 0xE8322A)
}

// MARK: - Typography

extension Font {
    static func vTitle(_ size: CGFloat = 20) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static let vLargeTitle = Font.system(size: 28, weight: .heavy, design: .rounded)
    static let vHeadline = Font.system(size: 17, weight: .semibold)
    static let vBody = Font.system(size: 15, weight: .regular)
    static let vBodyMedium = Font.system(size: 15, weight: .medium)
    static let vCaption = Font.system(size: 12, weight: .regular)
    static let vCaptionMedium = Font.system(size: 12, weight: .medium)
    static let vMicro = Font.system(size: 10, weight: .medium)
    /// 价格字体：等宽数字
    static func vPrice(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded).monospacedDigit() }
    static func vMono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .rounded).monospacedDigit() }
}

// MARK: - Spacing & Radius

enum VSpace {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum VRadius {
    static let s: CGFloat = 6
    static let m: CGFloat = 10
    static let l: CGFloat = 14
    static let xl: CGFloat = 20
    static let pill: CGFloat = 999
}

// MARK: - Shadows

extension View {
    func vCardShadow() -> some View {
        shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 3)
    }
    func vFloatingShadow() -> some View {
        shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
    }
}

// MARK: - Gradients

enum VGradient {
    static let brand = LinearGradient(colors: [Color(hex: 0xFF5A4E), Color(hex: 0xE8322A)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let carbon = LinearGradient(colors: [Color(hex: 0x2B2D33), Color(hex: 0x111318)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let gold = LinearGradient(colors: [Color(hex: 0xFFC46B), Color(hex: 0xF5A524)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let imageScrim = LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
}
