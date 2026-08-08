import Foundation

/// The six privacy effects, in the order they appear in the popover.
///
/// Raw values are stable identifiers: they key both the `UserDefaults` entries and the
/// per-effect payloads inside the crash-recovery snapshot, so renaming one would orphan
/// a user's settings *and* silently drop a pending restore. Change display strings, never these.
public nonisolated enum Feature: String, CaseIterable, Codable, Sendable, Identifiable {
    case doNotDisturb
    case hideWindows
    case hideDock
    case hideMenuBarIcons
    case hideWallpaper
    case hideDesktopItems

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .doNotDisturb: "Do Not Disturb"
        case .hideWindows: "Hide Active Windows"
        case .hideDock: "Hide Dock"
        case .hideMenuBarIcons: "Hide Menu Bar Icons"
        case .hideWallpaper: "Hide Wallpaper"
        case .hideDesktopItems: "Hide Desktop Icons & Widgets"
        }
    }

    public var symbolName: String {
        switch self {
        case .doNotDisturb: "moon.fill"
        case .hideWindows: "macwindow.on.rectangle"
        case .hideDock: "dock.arrow.down.rectangle"
        case .hideMenuBarIcons: "menubar.rectangle"
        case .hideWallpaper: "photo"
        case .hideDesktopItems: "lock.desktopcomputer"
        }
    }

    /// Extra context surfaced behind an ⓘ in the popover, for the features whose
    /// behaviour isn't self-evident from the label alone.
    public var note: String? {
        switch self {
        case .hideMenuBarIcons:
            "Hides every icon to the left of Mica's ‹ marker. Hold ⌘ and drag icons to move them."
        default:
            nil
        }
    }

    /// Whether this effect changes state that outlives the process.
    ///
    /// The wallpaper cover and the menu bar spacer are windows and status items owned by
    /// this process — if Mica dies they vanish with it, so replaying them on next launch
    /// would be meaningless. Only the persistent four go into the crash snapshot, which
    /// keeps the pre-mutation blocking write small.
    public var mutatesPersistentSystemState: Bool {
        switch self {
        case .hideWallpaper, .hideMenuBarIcons: false
        case .doNotDisturb, .hideWindows, .hideDock, .hideDesktopItems: true
        }
    }

    /// Engage order. The desktop is covered *before* windows are hidden, so hiding a
    /// window never flashes the wallpaper underneath it. Disengage walks this in reverse,
    /// which conveniently restores windows before the cover is removed.
    public static let engageOrder: [Feature] = [
        .hideMenuBarIcons, .hideDock, .hideDesktopItems, .hideWallpaper, .hideWindows, .doNotDisturb,
    ]

    public static var disengageOrder: [Feature] { engageOrder.reversed() }
}

/// Which windows `Hide Active Windows` acts on.
public nonisolated enum HideWindowsScope: String, CaseIterable, Codable, Sendable {
    case all
    case exceptFrontmost
    /// Hide only a chosen set — everything else stays on screen.
    case onlySelected
    /// Hide everything but a chosen set.
    case allExceptSelected

    public var displayName: String {
        switch self {
        case .all: "All windows"
        case .exceptFrontmost: "All except frontmost"
        case .onlySelected: "Only these apps"
        case .allExceptSelected: "All except these apps"
        }
    }

    /// Whether this scope reads the user's chosen app list.
    public var usesAppList: Bool {
        switch self {
        case .all, .exceptFrontmost: false
        case .onlySelected, .allExceptSelected: true
        }
    }

    public var listCaption: String {
        switch self {
        case .onlySelected: "Hide only these apps:"
        case .allExceptSelected: "Hide everything except these apps:"
        case .all, .exceptFrontmost: ""
        }
    }
}
