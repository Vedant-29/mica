import AppKit
import MicaCore
import SwiftUI

struct AppsSettingsView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        Form {
            Section("Trigger Apps") {
                Text("Get reminded, or activate when the following apps are running:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                AppListEditor(store: environment.triggerApps, showsAction: true) {
                    environment.settingsDidChange()
                }
            }

            Section("Excluded Apps") {
                Text("Do not activate when the following apps are running:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                AppListEditor(store: environment.excludedApps, showsAction: false) {
                    environment.settingsDidChange()
                }

                Text("Exclusions apply in Auto only. Switching Mica On always wins.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !environment.notifier.systemNotificationsAvailable {
                Section {
                    Text("""
                        Reminders use Mica's own banner rather than a system notification. \
                        macOS only grants notification access to apps signed with a notarized \
                        Developer ID, which a locally-built app isn't. The banner works the \
                        same way and needs no permission.
                        """)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// A list of apps with add and remove, and optionally the Activate / Remind me choice.
struct AppListEditor: View {
    @Bindable var store: AppListStore
    let showsAction: Bool
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.entries.isEmpty {
                Text("No apps yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(store.entries) { entry in
                    HStack(spacing: 8) {
                        Image(nsImage: AppIconCache.icon(forBundleID: entry.bundleID))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(entry.displayName)
                            .font(.system(size: 12))
                        Spacer(minLength: 8)

                        if showsAction {
                            Picker("", selection: Binding(
                                get: { entry.action },
                                set: { store.setAction($0, for: entry.bundleID); onChange() }
                            )) {
                                ForEach(TriggerAction.allCases) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }

                        Button {
                            store.remove(bundleID: entry.bundleID)
                            onChange()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Remove \(entry.displayName)")
                    }
                }
            }

            Button {
                if let entry = AppPicker.choose() {
                    store.add(entry)
                    onChange()
                }
            } label: {
                Label("Add App…", systemImage: "plus")
            }
        }
    }
}

/// Picks an application bundle.
///
/// An open panel rather than a list of running apps: it can reach anything installed, not
/// only what happens to be running right now, which is the common case when configuring
/// this ahead of time.
enum AppPicker {
    static func choose() -> AppEntry? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Add"

        // The panel belongs to an accessory app, which would otherwise open behind
        // whatever the user was looking at.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return nil }

        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        return AppEntry(bundleID: bundleID, displayName: name)
    }
}

enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(forBundleID bundleID: String) -> NSImage {
        if let cached = cache[bundleID] { return cached }

        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSWorkspace.shared.icon(for: .application)
        }
        cache[bundleID] = image
        return image
    }
}
