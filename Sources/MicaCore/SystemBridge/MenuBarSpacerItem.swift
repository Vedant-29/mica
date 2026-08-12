import AppKit

/// A status item that hides its neighbours by growing.
///
/// macOS lays the menu bar out right-to-left, so an item wide enough to fill the bar
/// pushes everything to its left off the edge of the screen. This is the technique
/// Bartender, Ice and Hidden Bar all use, and it needs no permissions at all — Ice only
/// requires Accessibility because it goes further and *rearranges* other apps' items.
///
/// The spacer has to sit to the left of Mica's own icon, which is why it shows a `‹`
/// while idle: it's a handle the user can ⌘-drag into position. Nothing stops that drag
/// crossing to the wrong side of the icon, so the collapse is guarded at both ends —
/// see `moveClearOfOwnIconIfNeeded()` and `verifyOwnIconSurvived()`.
final class MenuBarSpacerController {

    /// macOS caps `NSStatusItem.length`; anything longer is clamped.
    private static let maximumLength: CGFloat = 10_000
    private static let minimumLength: CGFloat = 500
    private static let idleLength: CGFloat = 20

    private static let autosaveName = "MicaSpacer"

    /// Clearance left between the rescued spacer and Mica's icon, so the two don't end up
    /// close enough that the next drag lands on the wrong side again.
    private static let rescueGap: CGFloat = 12

    /// How long the menu bar needs to re-lay-out before its frames mean anything.
    private static let settleDelay: TimeInterval = 0.3

    private var item: NSStatusItem?
    private(set) var isCollapsed = false

    /// Mica's own menu bar item, handed over by the app layer.
    ///
    /// `MenuBarExtra` builds this itself and SwiftUI never surfaces it, so it arrives via
    /// `MenuBarExtraAccess`'s introspection callback. Finding it by sifting `NSApp.windows`
    /// for menu-bar-shaped geometry was tried first and matched nothing on macOS 26, where
    /// the item is an `NSSceneStatusItem` — which failed silently, in the one place a
    /// silent failure locks the user out of the app.
    private weak var ownItem: NSStatusItem?

    /// Mica's own icon as it sat immediately before the last collapse. Recorded because
    /// once the spacer grows, an icon that got pushed off the edge can no longer be
    /// measured — only missed.
    private var ownIconFrameBeforeCollapse: CGRect?

    /// Whether the spacer has already been moved once for the current collapse, so a
    /// reposition that doesn't help can't turn into an endless collapse/undo loop.
    private var rescueAttempted = false

    /// Called when a collapse had to be undone because it would have hidden Mica's own
    /// icon. Lets the UI explain why the menu bar didn't change.
    var onCollapseAborted: (() -> Void)?

    var isInstalled: Bool { item != nil }

    /// Called by the app layer once `MenuBarExtra` has built Mica's own status item.
    func setOwnStatusItem(_ item: NSStatusItem?) {
        ownItem = item
    }

    /// The spacer exists whenever the feature is switched on, not only while engaged —
    /// otherwise there'd be no handle to position before it matters.
    func setInstalled(_ installed: Bool) {
        guard installed != isInstalled else { return }

        if installed {
            createItem()
        } else {
            removeItem()
            isCollapsed = false
            ownIconFrameBeforeCollapse = nil
        }
    }

    func setCollapsed(_ collapsed: Bool) {
        guard collapsed != isCollapsed else { return }

        if collapsed {
            // Best-effort, and frequently a no-op: engagement often happens moments after
            // launch, when the status items exist but the menu bar has not laid them out
            // and every frame still reads as zero. The real safeguard is the check *after*
            // the collapse, which runs on geometry that has settled.
            moveClearOfOwnIconIfNeeded()
            ownIconFrameBeforeCollapse = ownIconFrame()

            if ownIconFrameBeforeCollapse == nil {
                // The guard below is now inert. Better to say so than to repeat the silent
                // no-op that let this ship the first time.
                Log.effects.error(
                    "Mica's own status item is unknown; collapsing without the self-hide guard"
                )
            }
        } else {
            ownIconFrameBeforeCollapse = nil
            rescueAttempted = false
        }

        isCollapsed = collapsed
        applyLength()

        if collapsed { verifyOwnIconSurvived() }
    }

    // MARK: - Item lifecycle

    private func createItem() {
        let item = NSStatusBar.system.statusItem(withLength: Self.idleLength)
        // Persists the user's ⌘-drag position across launches.
        item.autosaveName = Self.autosaveName
        item.button?.title = "‹"
        item.button?.toolTip = "Menu bar icons to the left of this are hidden while Mica is on"
        self.item = item
        applyLength()
    }

    private func removeItem() {
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    private func applyLength() {
        guard let item else { return }
        item.button?.title = isCollapsed ? "" : "‹"
        item.length = isCollapsed ? Self.collapsedLength() : Self.idleLength
    }

    // MARK: - Not hiding ourselves

    /// Moves the spacer back to the left of Mica's icon if the user has ⌘-dragged it to
    /// the wrong side.
    ///
    /// Collapsing with the spacer to the right of the icon hides Mica from its own menu
    /// bar, and that is not a cosmetic problem: no icon means no popover, no Settings and
    /// no way to switch the mode back, on a machine whose Dock, desktop icons and
    /// wallpaper have just been hidden too. The only way out is the ⌥⌘S hotkey, which
    /// the user has to both know about and still have bound.
    private func moveClearOfOwnIconIfNeeded() {
        guard let spacerFrame = item?.button?.window?.frame,
              let iconFrame = ownIconFrame(),
              spacerFrame.minX > iconFrame.minX
        else { return }

        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(iconFrame) })
            ?? NSScreen.main
        else { return }

        // `NSStatusItem` exposes no API for setting position, but it stores the ⌘-drag
        // under a well-known default keyed by `autosaveName` and reads it back when the
        // item is created. It's a distance from the right edge of the screen, so larger
        // sits further left.
        //
        // The item is torn down *before* the write, not after: removing it flushes its
        // current position to that same key, which would otherwise overwrite the value
        // just written and leave the spacer exactly where it was.
        let position = screen.frame.maxX - iconFrame.minX + Self.rescueGap
        removeItem()
        UserDefaults.standard.set(
            Double(position),
            forKey: "NSStatusItem Preferred Position \(Self.autosaveName)"
        )
        createItem()

        Log.effects.notice(
            "spacer sat right of Mica's icon; moved to \(position, privacy: .public) before collapsing"
        )
    }

    /// Backs out of a collapse that swallowed Mica's own icon, and tries once to fix the
    /// cause before giving up.
    ///
    /// This is where the work actually happens, because it is the first point at which the
    /// geometry can be trusted. `NSStatusItem` frames are all zero until the menu bar lays
    /// out, and engagement routinely beats that — so a pre-flight check reads nothing
    /// useful, while here the displaced icon reports a real (negative) position.
    ///
    /// The sequence is: undo, let the bar settle so the icon returns to its true spot,
    /// move the spacer clear of it, then retry. One retry only; a second failure gives up
    /// with the collapse undone. An app the user cannot reach is far worse than a feature
    /// that declines to work.
    private func verifyOwnIconSurvived() {
        guard ownIconFrameBeforeCollapse != nil else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isCollapsed else { return }
                guard !self.ownIconIsReachable() else { return }

                // Undo first: while collapsed, every measurement is of a displaced bar.
                self.isCollapsed = false
                self.applyLength()

                guard !self.rescueAttempted else {
                    Log.effects.error("collapse would have hidden Mica's own icon; undone")
                    self.onCollapseAborted?()
                    return
                }
                self.rescueAttempted = true

                DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, !self.isCollapsed else { return }
                        self.moveClearOfOwnIconIfNeeded()
                        self.setCollapsed(true)
                    }
                }
            }
        }
    }

    /// Where Mica's own icon currently sits.
    private func ownIconFrame() -> CGRect? {
        ownItem?.button?.window?.frame
    }

    /// Whether Mica's icon is still somewhere the user can click it.
    ///
    /// An icon pushed past the left edge keeps a frame, so containment is the test rather
    /// than mere existence. A missing frame counts as unreachable too — this is only ever
    /// asked after a frame was read successfully before the collapse.
    private func ownIconIsReachable() -> Bool {
        guard let frame = ownIconFrame() else { return false }
        return NSScreen.screens.contains { screen in
            screen.frame.intersects(frame) && frame.minX >= screen.frame.minX
        }
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
