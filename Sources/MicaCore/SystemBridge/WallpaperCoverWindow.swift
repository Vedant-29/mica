import AppKit

/// A borderless window that sits directly on top of the wallpaper.
///
/// The level is the whole trick. On this machine the wallpaper is a Dock-owned window at
/// -2147483624 and the desktop icons are a Finder window at -2147483603, so a cover at
/// `.desktopWindow` (-2147483623) lands cleanly between them: the wallpaper is hidden and
/// the icons still show. That's what keeps "Hide Wallpaper" and "Hide Desktop Icons &
/// Widgets" independent rather than one implying the other.
final class WallpaperCoverWindow: NSWindow {

    init(screen: NSScreen) {
        // The `screen:` overload is a convenience initializer and can't be called from a
        // subclass. Not a loss: `screen.frame` is already in global coordinates, so the
        // `setFrame` below places the window on the right display anyway.
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

        // Follow the user across Spaces without animating, and stay out of ⌘` cycling
        // and the Window menu. `.fullScreenNone` keeps it from being dragged into a
        // full-screen Space.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]

        // Without this the cover swallows every desktop click, including right-clicks.
        ignoresMouseEvents = true

        // A shadow at desktop level draws a visible dark band along the screen edges.
        hasShadow = false
        isOpaque = true
        backgroundColor = .windowBackgroundColor
        isReleasedWhenClosed = false
        displaysWhenScreenProfileChanges = true

        // `frame`, not `visibleFrame` — the cover should extend under the menu bar too.
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// An accessory application that isn't active has `orderFront(_:)` deferred, so the
    /// cover would silently never appear.
    func show() { orderFrontRegardless() }
}

/// Owns one cover window per display and keeps that set in step with the hardware.
final class WallpaperCoverController {

    private var windows: [CGDirectDisplayID: WallpaperCoverWindow] = [:]
    private var screenObserver: (any NSObjectProtocol)?
    private var rebuildWork: DispatchWorkItem?

    var isShowing: Bool { !windows.isEmpty }

    func show() {
        rebuild()
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        }
    }

    func hide() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        rebuildWork?.cancel()
        rebuildWork = nil
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
    }

    /// A single display change fires this notification several times, and again on wake.
    /// Rebuilding on each one strobes the cover, so they're coalesced.
    private func scheduleRebuild() {
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func rebuild() {
        var live: Set<CGDirectDisplayID> = []

        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            live.insert(id)

            if let existing = windows[id] {
                existing.setFrame(screen.frame, display: true)
                existing.show()
            } else {
                let window = WallpaperCoverWindow(screen: screen)
                windows[id] = window
                window.show()
            }
        }

        // Tear down covers for displays that went away.
        for (id, window) in windows where !live.contains(id) {
            window.orderOut(nil)
            windows[id] = nil
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
