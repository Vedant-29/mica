import AppKit
import MicaCore
import SwiftUI

/// One-time setup for Do Not Disturb.
///
/// This exists because macOS 26 offers no reachable API for setting Focus — the private
/// service is gated behind an Apple-only entitlement, and the Intents API is read-only.
/// Running a Shortcut is the one route that works without permission prompts, and a
/// Shortcut has to be created by the person who owns the Mac.
struct DoNotDisturbSetupSection: View {
    @Bindable var environment: AppEnvironment

    @State private var shortcuts: [ShortcutsRunner.Shortcut] = []

    private var preferences: Preferences { environment.preferences }

    var body: some View {
        Section("Do Not Disturb") {
            Text("""
                macOS doesn't let apps set Focus directly, so Mica runs two Shortcuts you \
                create once. In the Shortcuts app, make one containing a single \
                “Set Focus → Do Not Disturb → On” action, and another set to Off. Then \
                pick them here.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Turn on:", selection: shortcutBinding(\.dndShortcutOnID)) {
                Text("None").tag(String?.none)
                ForEach(shortcuts) { Text($0.name).tag(String?.some($0.uuid)) }
            }
            Picker("Turn off:", selection: shortcutBinding(\.dndShortcutOffID)) {
                Text("None").tag(String?.none)
                ForEach(shortcuts) { Text($0.name).tag(String?.some($0.uuid)) }
            }

            HStack {
                Button("Open Shortcuts") {
                    if let url = NSWorkspace.shared.urlForApplication(
                        withBundleIdentifier: "com.apple.shortcuts"
                    ) {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }
                }
                Button("Refresh List") { reload() }
            }

            if shortcuts.isEmpty {
                Text("No shortcuts found. Create them in the Shortcuts app, then refresh.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .task { reload() }
    }

    private func reload() {
        // Shells out to `shortcuts list`, so keep it off the main thread.
        Task.detached {
            let found = ShortcutsRunner.list()
            await MainActor.run { shortcuts = found }
        }
    }

    /// Shortcuts are stored by UUID, never by name: names collide, get renamed, and are
    /// localised, any of which would silently break the binding.
    private func shortcutBinding(
        _ keyPath: ReferenceWritableKeyPath<Preferences, String?>
    ) -> Binding<String?> {
        Binding(
            get: { preferences[keyPath: keyPath] },
            set: { preferences[keyPath: keyPath] = $0; environment.enabledFeaturesDidChange() }
        )
    }
}
