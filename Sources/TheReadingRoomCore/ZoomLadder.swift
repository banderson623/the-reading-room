import Foundation

/// The zoom steps ⌘+ and ⌘- move between.
///
/// A ladder rather than a fixed increment: the steps stay sensible at both ends
/// (10% is a lot at 50% and nothing at 300%), and there's no floating-point
/// drift to accumulate.
public enum ZoomLadder {
    public static let levels: [Double] = [
        0.5, 0.67, 0.75, 0.85, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0, 2.5, 3.0,
    ]

    public static var minimum: Double { levels.first! }
    public static var maximum: Double { levels.last! }

    /// Comparisons use a small tolerance so a level that is already exact
    /// doesn't match itself and stall.
    private static let epsilon = 0.001

    public static func next(above level: Double) -> Double {
        levels.first { $0 > level + epsilon } ?? maximum
    }

    public static func next(below level: Double) -> Double {
        levels.last { $0 < level - epsilon } ?? minimum
    }

    public static func clamp(_ level: Double) -> Double {
        min(max(level, minimum), maximum)
    }

    public static func percent(_ level: Double) -> String {
        "\(Int((level * 100).rounded()))%"
    }
}
