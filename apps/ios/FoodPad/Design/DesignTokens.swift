import SwiftUI

// Primitive values stay here. Views consume only the semantic aliases below.
private enum ColorRamp {
    static let neutral = ["FAFCFC", "F7F8F8", "EBEFEF", "DBE1E1", "A4ACAC", "687373", "4F5959", "3B4444", "232929", "161B1B", "0A0D0D"].map(Color.init(hex:))
    static let emerald = ["ECFDF5", "D1FAE5", "A7F3D0", "6EE7B7", "34D399", "10B981", "059669", "047857", "065F46", "064E3B", "022C22"].map(Color.init(hex:))
    static let red = ["FEF2F2", "FEE2E2", "FECACA", "FCA5A5", "F87171", "EF4444", "DC2626", "B91C1C", "991B1B", "7F1D1D", "450A0A"].map(Color.init(hex:))
    static let amber = ["FFFBEB", "FEF3C7", "FDE68A", "FCD34D", "FBBF24", "F59E0B", "D97706", "B45309", "92400E", "78350F", "451A03"].map(Color.init(hex:))
    static let green = ["F0FDF4", "DCFCE7", "BBF7D0", "86EFAC", "4ADE80", "22C55E", "16A34A", "15803D", "166534", "14532D", "052E16"].map(Color.init(hex:))
}

enum AppColor {
    static let background = ColorRamp.neutral[1]
    static let surface = Color.white
    static let textPrimary = ColorRamp.neutral[9]
    static let textSecondary = ColorRamp.neutral[5]
    static let border = ColorRamp.neutral[2]
    static let brand = ColorRamp.emerald[7]
    static let brandSubtle = ColorRamp.emerald[0]
    static let onBrand = Color.white
    static let error = ColorRamp.red[7]
    static let errorSubtle = ColorRamp.red[0]
    static let onError = Color.white
    static let warning = ColorRamp.amber[7]
    static let warningSubtle = ColorRamp.amber[0]
    static let onWarning = Color.white
    static let success = ColorRamp.green[7]
    static let successSubtle = ColorRamp.green[0]
    static let onSuccess = Color.white
    static let favourite = ColorRamp.amber[4]
}

private enum SpacingScale {
    static let values: [Double] = [0, 2, 4, 6, 8, 10, 12, 14, 16, 20, 24, 28, 32, 36, 40, 44, 48, 56, 64, 80, 96]
}

private enum RadiusScale {
    static let values: [Double] = [0, 2, 4, 6, 8, 12, 16, 20, 24, 32, 9_999]
}

private enum TypeScale {
    static let sizes: [Double] = [12, 14, 16, 18, 20, 24, 30, 36, 48, 60, 72, 96, 128]
    static let lineHeights: [Double] = [12, 16, 20, 24, 28, 32, 36, 40, 44, 48]
    static let tracking: [Double] = [-0.05, -0.025, 0, 0.025, 0.05, 0.1]
}

private struct ShadowToken {
    let y: Double
    let blur: Double
    let opacity: Double
}

private enum ElevationScale {
    static let values = [
        ShadowToken(y: 1, blur: 3, opacity: 0.02), ShadowToken(y: 1, blur: 5, opacity: 0.03),
        ShadowToken(y: 1, blur: 7, opacity: 0.04), ShadowToken(y: 2, blur: 12, opacity: 0.05),
        ShadowToken(y: 4, blur: 20, opacity: 0.06), ShadowToken(y: 8, blur: 32, opacity: 0.08),
        ShadowToken(y: 16, blur: 48, opacity: 0.12),
    ]
}

enum AppFont {
    static func regular(_ size: Double) -> Font { .custom("Geist-Regular", size: size) }
    static func medium(_ size: Double) -> Font { .custom("Geist-Medium", size: size) }
    static func semibold(_ size: Double) -> Font { .custom("Geist-SemiBold", size: size) }
    static func bold(_ size: Double) -> Font { .custom("Geist-Bold", size: size) }
}

enum JournalToken {
    static let zeroGap = SpacingScale.values[0]
    static let screenInset = SpacingScale.values[8]
    static let contentTop = SpacingScale.values[8]
    static let sectionGap = SpacingScale.values[6]
    static let dayGap = SpacingScale.values[6]
    static let rowGap = SpacingScale.values[6]
    static let rowVertical = SpacingScale.values[7]
    static let emptyTop = SpacingScale.values[10]
    static let emptyGap = SpacingScale.values[4]
    static let bodyMeasureInset = SpacingScale.values[11]
    static let footerTop = SpacingScale.values[7]
    static let footerBottom = SpacingScale.values[12]
    static let actionGap = SpacingScale.values[4]
    static let actionPadding = SpacingScale.values[8]
    static let actionRadius = RadiusScale.values[10]
    static let cardRadius = RadiusScale.values[8]
    static let skeletonRadius = RadiusScale.values[4]
    static let headingSize = TypeScale.sizes[3]
    static let bodySize = TypeScale.sizes[1]
    static let actionSize = TypeScale.sizes[2]
    static let skeletonHeight = SpacingScale.values[15]
    static let energyWidth = SpacingScale.values[19]
}

private extension Color {
    init(hex: String) {
        let value = UInt64(hex, radix: 16)!
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255,
            opacity: 1
        )
    }
}
