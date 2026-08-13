import SwiftUI

/// Dark, "darkroom" inspired palette: near-black backgrounds, warm amber accent.
enum Theme {
    static let background = Color(light: Color(hex: 0xF7F5F1), dark: Color(hex: 0x0B0B0D))
    static let surface = Color(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x16161A))
    static let surfaceElevated = Color(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x1F1F24))
    static let accent = Color(light: Color(hex: 0xC9752B), dark: Color(hex: 0xF2A65A))
    static let accentSoft = accent.opacity(0.16)
    static let textPrimary = Color(light: Color(hex: 0x1C1B1A), dark: Color(hex: 0xF5F2EE))
    static let textSecondary = Color(light: Color(hex: 0x6B6560), dark: Color(hex: 0x9A948C))
    static let divider = Color(light: Color(hex: 0xE5E1DA), dark: Color(hex: 0x2A2A30))
    static let danger = Color(light: Color(hex: 0xB3432B), dark: Color(hex: 0xE07356))
    static let favorite = Color(hex: 0xE0533D)

    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 14
}

extension Color {
    init(light: Color, dark: Color) {
        self = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}