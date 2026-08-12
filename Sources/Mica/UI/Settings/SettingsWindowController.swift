import AppKit
import MicaCore
import SwiftUI

enum SettingsTab: String, CaseIterable, Hashable {
    case general
    case features
    case windows
    case triggers

    var title: String {
        switch self {
        case .general: "General"
        case .features: "Features"
        case .windows: "Windows"
        case .triggers: "Triggers"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .features: "eye.slash"
        case .windows: "macwindow.on.rectangle"
        case .triggers: "bolt"
        }
    }
}

/// Owns the settings window.
///
/// A hand-managed `NSWindow` rather than SwiftUI's `Settings` scene, because
/// `openSettings()` does not reliably work from inside a `MenuBarExtra` — and for a
/// menu-bar-only app there is no application menu to fall back on, so a failure there
/// leaves the settings genuinely unreachable. This route always works.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let environment: AppEnvironment
    private var selectedTab: SettingsTab = .general

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func show(tab: SettingsTab? = nil) {
        if let tab { selectedTab = tab }

        // An accessory app is never active, so without this the window opens behind
        // whatever the user was looking at.
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            if tab != nil { rebuildContent() }
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mica Settings"
        window.delegate = self
        // Transparent so the title bar and the tab strip below it read as one surface
        // rather than two stacked edges. The title itself stays: hiding it left the
        // window anonymous, which matters for an app whose settings are easy to mistake
        // for a pane of macOS System Settings.
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        // Keeping the instance alive across closes preserves scroll position and the
        // selected tab, and avoids re-running the Shortcuts lookup on every open.
        window.isReleasedWhenClosed = false
        window.center()
        // Deliberately left capturable.
        //
        // This window used to set `sharingType = .none`, so that a screen-privacy app's
        // own configuration couldn't appear in the share you were configuring it for.
        // Every version of that rule turned out worse than the thing it prevented:
        // unconditionally, it made the window impossible to screenshot at all, which costs
        // bug reports and documentation and protects nothing while no one is watching.
        // Tying it to engagement was no better — `On` means permanently engaged, and under
        // `Auto` pressing ⌘⇧5 is itself a capture, so the window would exclude itself from
        // the very screenshot being taken.
        //
        // Nothing here is secret: toggles, a hotkey and a list of apps. And Mica already
        // has a general answer for windows that shouldn't be in a share — Hide Active
        // Windows — which is a better place for this than a private rule only this one
        // window obeys.

        self.window = window
        rebuildContent()
        window.makeKeyAndOrderFront(nil)
    }

    private func rebuildContent() {
        window?.contentViewController = NSHostingController(
            rootView: SettingsRootView(environment: environment, selectedTab: selectedTab)
        )
    }

    func windowWillClose(_ notification: Notification) {
        // Drop back out of the foreground; a menu bar app has no business staying active.
        NSApp.hide(nil)
    }
}
