import Foundation

/// Clamps a value between a minimum and maximum.
/// - Parameters:
///   - value: The value to clamp.
///   - minValue: The minimum allowed value.
///   - maxValue: The maximum allowed value.
/// - Returns: The clamped value.
func clamp(_ value: Double, _ minValue: Double, _ maxValue: Double) -> Double {
    return min(max(value, minValue), maxValue)
} 