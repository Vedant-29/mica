import AppKit

/// Best-effort guess at *what* is capturing the screen.
///
/// The window server flag that detects capture is a single boolean with no attribution,
/// so this corroborates from cheaper public sources. It runs only at the moment capture
/// starts, never continuously, and it is display-only — nothing here ever gates whether
/// Mica engages, so a wrong or absent answer costs only a less specific sentence.
public nonisolated enum CaptureAttribution {

    /// Processes whose mere presence means a capture is happening.
    private static let capturingProcessNames: [(process: String, display: String)] = [
        ("screencapture", "Screenshot"),          // ⌘⇧5 and the command line tool
        ("CptHost", "Zoom"),                      // Zoom's screen-share helper
        ("OBS", "OBS"),
    ]

    /// Applications that own a visible screen-sharing toolbar while sharing.
    private static let sharingToolbarOwners: [String: String] = [
        "zoom.us": "Zoom",
        "Microsoft Teams": "Microsoft Teams",
        "MSTeams": "Microsoft Teams",
        "Slack": "Slack",
        "Discord": "Discord",
        "Webex": "Webex",
        "Google Chrome": "Chrome",
        "Arc": "Arc",
        "Safari": "Safari",
        "Firefox": "Firefox",
        "Microsoft Edge": "Edge",
        "Brave Browser": "Brave",
        "QuickTime Player": "QuickTime Player",
        "Screen Sharing": "Screen Sharing",
        "loginwindow": "Screen Sharing",
    ]

    /// Phrases browsers and conferencing apps put in their sharing-toolbar window titles.
    private static let sharingTitleFragments = [
        "is sharing your screen", "sharing your screen", "stop sharing",
        "is sharing a tab", "is sharing a window", "you are sharing", "you're sharing",
        "zoom share", "as_toolbar", "sharing toolbar", "screen sharing",
    ]

    public static func likelyCapturer() -> String? {
        if let name = fromWindowTitles() { return name }
        if let name = fromProcesses() { return name }
        return nil
    }

    /// Window *titles* need Screen Recording permission to read; owner names do not.
    /// Without the grant `kCGWindowName` is simply absent, so this degrades to nil
    /// rather than failing — which is why it isn't the only strategy.
    private static func fromWindowTitles() -> String? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windows {
            guard let title = (window["kCGWindowName"] as? String)?.lowercased(), !title.isEmpty else {
                continue
            }
            guard sharingTitleFragments.contains(where: title.contains) else { continue }

            let owner = window["kCGWindowOwnerName"] as? String ?? ""
            return sharingToolbarOwners[owner] ?? owner
        }
        return nil
    }

    private static func fromProcesses() -> String? {
        let running = NSWorkspace.shared.runningApplications

        for candidate in capturingProcessNames {
            let isRunning = running.contains { app in
                app.localizedName == candidate.process
                    || app.executableURL?.lastPathComponent == candidate.process
            }
            if isRunning { return candidate.display }
        }
        return nil
    }
}
