import AppKit
import MicaCore
import SwiftUI

/// One-time setup for Do Not Disturb.
///
/// This exists because macOS 26 offers no reachable API for setting Focus — the private
/// service is gated behind an Apple-only entitlement, and the Intents API is read-only.
/// Running a Shortcut is the one route that works without permission prompts, and a
/// Shortcut has to live in the user's own library.
struct DoNotDisturbSetupSection: View {
    @Bindable var environment: AppEnvironment

    @State private var shortcuts: [ShortcutsRunner.Shortcut] = []
    @State private var status: String?
    @State private var isBusy = false

    private var preferences: Preferences { environment.preferences }

    private var isConfigured: Bool {
        preferences.dndShortcutOnID != nil && preferences.dndShortcutOffID != nil
    }

    var body: some View {
        Section("Do Not Disturb") {
            Text("""
                macOS doesn't let apps turn Focus on directly, so Mica runs two Shortcuts. \
                Create them below — you'll be asked to confirm each one — or pick Shortcuts \
                you've already made.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Create Shortcuts") { createShortcuts() }
                    .disabled(isBusy)
                Button("Test") { runTest() }
                    .disabled(isBusy || !isConfigured)
                Button("Refresh") { reload() }
                    .disabled(isBusy)
            }

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(status.hasPrefix("✓") ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Turn on:", selection: shortcutBinding(\.dndShortcutOnID)) {
                Text("None").tag(String?.none)
                ForEach(shortcuts) { Text($0.name).tag(String?.some($0.uuid)) }
            }
            Picker("Turn off:", selection: shortcutBinding(\.dndShortcutOffID)) {
                Text("None").tag(String?.none)
                ForEach(shortcuts) { Text($0.name).tag(String?.some($0.uuid)) }
            }

            Button("Open Shortcuts app") {
                if let url = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: "com.apple.shortcuts"
                ) {
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                }
            }
        }
        .task { reload() }
    }

    private func createShortcuts() {
        isBusy = true
        status = "Opening Shortcuts — choose Add Shortcut for each of the two, then press Refresh."
        Task.detached {
            do {
                try ShortcutInstaller.install()
            } catch {
                await MainActor.run { status = String(describing: error) }
            }
            await MainActor.run { isBusy = false }
        }
    }

    /// Runs the on shortcut and checks Focus actually changed, then puts it back.
    ///
    /// Worth doing explicitly: a shortcut can import perfectly and still not toggle
    /// anything if the action's parameters aren't what this macOS expects, and silently
    /// doing nothing is the one failure mode the user would never spot on their own.
    private func runTest() {
        guard let onID = preferences.dndShortcutOnID,
              let offID = preferences.dndShortcutOffID else { return }

        isBusy = true
        status = "Testing…"
        let monitor = environment.engagement.doNotDisturb

        Task {
            let ranOn = await Task.detached { ShortcutsRunner.run(uuid: onID) }.value
            try? await Task.sleep(for: .seconds(1))
            let becameEnabled = monitor.isEnabled == true

            _ = await Task.detached { ShortcutsRunner.run(uuid: offID) }.value
            try? await Task.sleep(for: .seconds(1))

            status = if !ranOn {
                "The shortcut didn't run. Open it in the Shortcuts app and check it has a Set Focus action."
            } else if becameEnabled {
                "✓ Working — Do Not Disturb switched on and back off."
            } else {
                """
                The shortcut ran but Focus didn't change. Open it in the Shortcuts app and \
                make sure the action is Set Focus → Do Not Disturb → On.
                """
            }
            isBusy = false
        }
    }

    private func reload() {
        // Shells out to `shortcuts list`, so keep it off the main thread.
        Task.detached {
            let found = ShortcutsRunner.list()
            let installed = ShortcutInstaller.findInstalled()
            await MainActor.run {
                shortcuts = found
                // Auto-select anything the installer created, so a successful Add needs
                // no further fiddling with the pickers.
                if preferences.dndShortcutOnID == nil, let on = installed.on {
                    preferences.dndShortcutOnID = on
                }
                if preferences.dndShortcutOffID == nil, let off = installed.off {
                    preferences.dndShortcutOffID = off
                }
                environment.enabledFeaturesDidChange()
            }
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
