import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

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
        // Stands in when the wallpaper can't be read — a picture-in-picture desktop, a
        // dynamic wallpaper mid-transition, or a file the sandbox won't open.
        backgroundColor = .windowBackgroundColor
        isReleasedWhenClosed = false
        displaysWhenScreenProfileChanges = true

        // `frame`, not `visibleFrame` — the cover should extend under the menu bar too.
        setFrame(screen.frame, display: true)

        installBlurredWallpaper(for: screen)
    }

    /// Covers the screen with a heavily blurred copy of the wallpaper rather than a flat
    /// fill.
    ///
    /// A plain grey rectangle reads as a broken display, and on a call it draws more
    /// attention than the wallpaper did. Blurring keeps the colour and mood of the desk
    /// while destroying everything identifiable in it — which is all the feature ever
    /// promised.
    func refreshBlurredWallpaper(for screen: NSScreen) {
        installBlurredWallpaper(for: screen)
    }

    private func installBlurredWallpaper(for screen: NSScreen) {
        guard let image = Self.blurredWallpaper(for: screen) else { return }

        let view = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
        // The blur is rendered at the screen's aspect ratio already; filling avoids
        // letterboxing if the wallpaper's own ratio differs.
        view.imageScaling = .scaleAxesIndependently
        view.image = image
        view.autoresizingMask = [.width, .height]
        contentView = view
    }

    private static func blurredWallpaper(for screen: NSScreen) -> NSImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let source = CIImage(contentsOf: url)
        else { return nil }

        // Scaled to the screen, so the same blur reads identically on a laptop panel and a
        // 5K display. Tuned by eye at the point where the large shapes of a photo stop
        // being readable — a lighter blur still gives away roughly what the picture is,
        // which is the thing the feature is meant to prevent.
        let radius = max(40, screen.frame.height * 0.08)

        // Gaussian blur samples beyond the image bounds, which without a clamp leaves the
        // edges fading to transparent and the desktop showing through them.
        let blurred = source
            .clampedToExtent()
            .applyingGaussianBlur(sigma: radius)
            .cropped(to: source.extent)

        let context = CIContext()
        guard let cgImage = context.createCGImage(blurred, from: source.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: screen.frame.size)
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
                // Re-blur at the new size: a cover that moved to a different display
                // would otherwise stretch the old screen's render across it.
                existing.refreshBlurredWallpaper(for: screen)
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
