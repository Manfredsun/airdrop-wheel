import SwiftUI

public enum WheelTheme {
    // Brand Palette
    public static let cream = Color(red: 0.996, green: 0.965, blue: 0.918) // #FEF6EA
    public static let navy = Color(red: 0.0, green: 0.239, blue: 0.424)   // #003D6C
    public static let electricCyan = Color(red: 0.0, green: 0.706, blue: 0.847) // #00B4D8
    public static let cyanGlow = electricCyan
    public static let lightAccent = Color(red: 0.08, green: 0.38, blue: 0.68)

    // Geometry & Layout
    public static let sectorCount: Int = 8
    public static let wheelDiameter: CGFloat = 540.0
    public static let outerRadius: CGFloat = wheelDiameter / 2.0 // 270.0
    public static let innerRadius: CGFloat = 140.0
    public static let hubDiameter: CGFloat = 280.0
    public static let outerRimWidth: CGFloat = 6.0
    public static let centerDeadZone: CGFloat = 140.0

    // Appearance helpers
    public static func ringBackgroundColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color(red: 0.0, green: 0.12, blue: 0.22).opacity(0.82)
        } else {
            return Color(red: 0.996, green: 0.975, blue: 0.945).opacity(0.86)
        }
    }

    public static func dividerColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.24)
        } else {
            return navy.opacity(0.22)
        }
    }

    public static func textColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? cream : navy
    }

    public static func secondaryTextColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? cream.opacity(0.65) : navy.opacity(0.65)
    }

    public static func accentColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? electricCyan : navy
    }

    public static func hubBackgroundColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color(red: 0.0, green: 0.08, blue: 0.16).opacity(0.88)
        } else {
            return cream.opacity(0.92)
        }
    }
}
