import AppKit
import MicaCore
import SwiftUI

/// Do Not Disturb: the feature toggle plus a short guide to create the two shortcuts it
/// runs.
///
/// The setup is entirely manual and by design. macOS only turns Focus on through the
/// Shortcuts "Set Focus" action, and that action works correctly only when created in the
/// Shortcuts app — a generated copy imports broken. The saving grace is that "Set Focus"
/// already defaults to "Do Not Disturb On until Turned Off", so the on-shortcut is just
/// "add the action and name it". Mica detects the two shortcuts by name; it makes no
/// claim about whether they work, because the honest test is the user seeing Focus turn
/// on when Mica engages.
struct DoNotDisturbSetupSection: View {
    @Bindable var environment: AppEnvironment

    private enum Confirm: Equatable { case untested, testing, working, broken }

    @State private var onFound = false
    @State private var offFound = false
    @State private var confirm: Confirm = .untested

    private var preferences: Preferences { environment.preferences }
    private var ready: Bool { onFound && offFound }

    var body: some View {
        Section("Do Not Disturb") {
            Toggle("Silence notifications while Mica is on", isOn: Binding(
                get: { preferences.isEnabled(.doNotDisturb) },
                set: { preferences.setEnabled($0, for: .doNotDisturb); environment.enabledFeaturesDidChange() }
            ))

            if ready {
                readyBody
            } else {
                guide
            }
        }
        .task { refresh() }
        .alert("Did the moon icon appear in your menu bar?", isPresented: $askMoon) {
            Button("Yes, it worked") { finishTest(worked: true) }
            Button("No", role: .cancel) { finishTest(worked: false) }
        } message: {
            Text("That's how macOS shows Do Not Disturb is on.")
        }
    }

    @ViewBuilder
    private var readyBody: some View {
        switch confirm {
        case .untested:
            Label("Both shortcuts found", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.callout)
            Text("Test it once to be sure it works.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Test It") { runTest() }

        case .testing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Turning Focus on — watch your menu bar…")
                    .font(.callout).foregroundStyle(.secondary)
            }

        case .working:
            Label("Working", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.callout)

        case .broken:
            Text("If the moon didn't appear, the “On” shortcut isn't set to turn Do Not Disturb on. Open it in Shortcuts, delete it, and remake it — “Set Focus” defaults to the right thing.")
                .font(.callout).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Shortcuts") { openShortcuts() }
                Button("Test Again") { runTest() }
            }
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("macOS only lets an app change Focus through a Shortcut. Make these two once — it takes about a minute.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            shortcutRow(
                found: onFound,
                name: ShortcutInstaller.onName,
                detail: "Add the “Set Focus” action. It already reads “Do Not Disturb On until Turned Off” — leave it. Name the shortcut exactly this."
            )
            shortcutRow(
                found: offFound,
                name: ShortcutInstaller.offName,
                detail: "Add “Set Focus”, click “On” and change it to “Off”. Name it exactly this."
            )

            HStack {
                Button("Open Shortcuts") { openShortcuts() }
                Button("I Made Them") { refresh() }
            }
            .padding(.top, 2)
        }
    }

    private func shortcutRow(found: Bool, name: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: found ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(found ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                .font(.callout)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.callout.weight(.medium))
                if !found {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @State private var askMoon = false

    private func refresh() {
        Task {
            let installed = await Task.detached { ShortcutInstaller.findInstalled() }.value
            preferences.dndShortcutOnID = installed.on
            preferences.dndShortcutOffID = installed.off
            onFound = installed.on != nil
            offFound = installed.off != nil
            environment.enabledFeaturesDidChange()
        }
    }

    /// The only honest test: run the on-shortcut and let the user's own eyes confirm the
    /// menu-bar moon. Reading Focus state from outside the app has proven unreliable on
    /// macOS 26, so the human is the oracle.
    private func runTest() {
        guard let onID = preferences.dndShortcutOnID else { return }
        confirm = .testing
        Task {
            _ = await Task.detached { ShortcutsRunner.run(uuid: onID) }.value
            // Give the menu-bar indicator a moment to appear before asking.
            try? await Task.sleep(for: .seconds(1))
            askMoon = true
        }
    }

    private func finishTest(worked: Bool) {
        confirm = worked ? .working : .broken
        if let offID = preferences.dndShortcutOffID {
            Task { _ = await Task.detached { ShortcutsRunner.run(uuid: offID) }.value }
        }
    }

    private func openShortcuts() {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.shortcuts"
        ) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}
