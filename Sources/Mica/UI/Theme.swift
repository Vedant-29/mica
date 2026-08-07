import SwiftUI

/// Shared visual constants for the popover, so spacing and colour stay consistent
/// across the rows without each view inventing its own numbers.
enum Theme {
    /// Warm amber for the engaged state. Distinct from the system accent on purpose —
    /// this colour means "something is being hidden right now", and it shouldn't change
    /// meaning because someone set their Mac's accent to blue.
    static let accent = Color(red: 0.91, green: 0.55, blue: 0.20)

    static let popoverWidth: CGFloat = 300
    static let horizontalPadding: CGFloat = 14
    static let rowHeight: CGFloat = 40
    static let chipSize: CGFloat = 28
    static let chipCornerRadius: CGFloat = 8
}
