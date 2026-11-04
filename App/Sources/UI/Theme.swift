import SwiftUI

public enum WheelTheme {
    public static let navy = Color(red: 0.0, green: 0.24, blue: 0.42) // #003D6C
    public static let cream = Color(red: 0.996, green: 0.965, blue: 0.918) // #FEF6EA
    public static let cyanGlow = Color(red: 0.0, green: 0.75, blue: 0.95)

    public static let sectorCount: Int = 8
    public static let wheelDiameter: CGFloat = 480
    public static let outerRadius: CGFloat = wheelDiameter / 2
    public static let innerRadius: CGFloat = outerRadius * 0.48
}
