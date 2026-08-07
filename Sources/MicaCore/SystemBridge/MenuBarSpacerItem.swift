import AppKit

/// A status item that hides its neighbours by growing.
///
/// macOS lays the menu bar out right-to-left, so an item wide enough to fill the bar
/// pushes everything to its left off the edge of the screen. This is the technique
/// Bartender, Ice and Hidden Bar all use, and it needs no permissions at all — Ice only
/// requires Accessibility because it goes further and *rearranges* other apps' items.
///
/// The spacer has to sit to the left of Mica's own icon, which is why it shows a `‹`
/// while idle: it's a handle the user can ⌘-drag into position.
final class MenuBarSpacerController {

    /// macOS caps `NSStatusItem.length`; anything longer is clamped.
    private static let maximumLength: CGFloat = 10_000
    private static let minimumLength: CGFloat = 500
    private static let idleLength: CGFloat = 20

    private var item: NSStatusItem?
    private(set) var isCollapsed = false

    var isInstalled: Bool { item != nil }

    /// The spacer exists whenever the feature is switched on, not only while engaged —
    /// otherwise there'd be no handle to position before it matters.
    func setInstalled(_ installed: Bool) {
        guard installed != isInstalled else { return }

        if installed {
            let item = NSStatusBar.system.statusItem(withLength: Self.idleLength)
            // Persists the user's ⌘-drag position across launches.
            item.autosaveName = "MicaSpacer"
            item.button?.title = "‹"
            item.button?.toolTip = "Menu bar icons to the left of this are hidden while Mica is on"
            self.item = item
            applyLength()
        } else {
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            isCollapsed = false
        }
    }

    func setCollapsed(_ collapsed: Bool) {
        guard collapsed != isCollapsed else { return }
        isCollapsed = collapsed
        applyLength()
    }

    private func applyLength() {
        guard let item else { return }
        item.button?.title = isCollapsed ? "" : "‹"
        item.length = isCollapsed ? Self.collapsedLength() : Self.idleLength
    }

    /// How wide the spacer has to be to push everything left of it off-screen.
    ///
    /// One length applies to every attached display's menu bar, so on macOS 26 it's sized
    /// against the *widest* screen to guarantee coverage everywhere. macOS 27 inverts
    /// this: an item reaching half the display width is silently discarded rather than
    /// clamped, so there the safe size is a fraction of the *narrowest* screen.
    private static func collapsedLength() -> CGFloat {
        let widths = NSScreen.screens.map(\.frame.width)

        if #available(macOS 27.0, *) {
            let narrowest = widths.min() ?? 1440
            return narrowest * 0.45
        } else {
            let widest = widths.max() ?? 1728
            return max(minimumLength, min(widest * 2, maximumLength))
        }
    }
}
