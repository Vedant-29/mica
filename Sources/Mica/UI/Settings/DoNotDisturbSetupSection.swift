import AppKit
import MicaCore
import SwiftUI

/// Do Not Disturb: the feature toggle plus a compact, scannable setup.
///
/// Setup is manual by necessity — macOS only turns Focus on through the Shortcuts
/// "Set Focus" action, and a generated copy imports broken. The UI keeps that from being a
/// wall of text: two status rows show whether each shortcut exists, the how-to lives in a
/// collapsible group, and the only verification is the user confirming the menu-bar moon,
/// since Focus state can't be read reliably on macOS 26.
struct DoNotDisturbSetupSection: View {
    @Bindable var environment: AppEnvironment

    private enum Test: Equatable { case idle, running, passed, failed }

    @State private var onFound = false
    @State private var offFound = false
    @State private var test: Test = .idle
    @State private var showSteps = false
    @State private var askMoon = false

    private var preferences: Preferences { environment.preferences }
    private var ready: Bool { onFound && offFound }

    var body: some View {
        Section("Do Not Disturb") {
            Toggle("Silence notifications while Mica is on", isOn: Binding(
                get: { preferences.isEnabled(.doNotDisturb) },
                set: { preferences.setEnabled($0, for: .doNotDisturb); environment.enabledFeaturesDidChange() }
            ))

            statusRow(ShortcutInstaller.onName, found: onFound)
            statusRow(ShortcutInstaller.offName, found: offFound)

            if ready {
                testRow
            } else {
                DisclosureGroup("How to make them", isExpanded: $showSteps) {
                    steps
                }
                HStack {
                    Button("Open Shortcuts") { openShortcuts() }
                    Spacer()
                    Button("Re-check") { refresh() }
                }
            }
        }
        .task { refresh() }
        .alert("Did the moon icon appear in your menu bar?", isPresented: $askMoon) {
            Button("Yes") { test = .passed; runOff() }
            Button("No", role: .cancel) { test = .failed; runOff() }
        } message: {
            Text("That's how macOS shows Do Not Disturb is on.")
        }
    }

    // MARK: - Rows

    private func statusRow(_ name: String, found: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: found ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(found ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
            Text(name)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(found ? .primary : .secondary)
            Spacer()
            if !found {
                Text("Missing").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var testRow: some View {
        switch test {
        case .idle:
            HStack {
                Text("Ready. Test it once to be sure.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Test") { runTest() }
            }
        case .running:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Watch your menu bar…").font(.callout).foregroundStyle(.secondary)
            }
        case .passed:
            Label("Working", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.callout)
        case .failed:
            VStack(alignment: .leading, spacing: 6) {
                Text("The “On” shortcut didn't turn Focus on. Delete it and remake it — “Set Focus” already defaults to the right setting.")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open Shortcuts") { openShortcuts() }
                    Button("Test Again") { runTest() }
                }
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 6) {
            step(1, "In Shortcuts, make a new shortcut and add the **Set Focus** action.")
            step(2, "It already reads *Do Not Disturb, On*. Name it **\(ShortcutInstaller.onName)**.")
            step(3, "Make another, switch it to *Off*, name it **\(ShortcutInstaller.offName)**.")
        }
        .padding(.vertical, 2)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
            Text(.init(text)).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    private func refresh() {
        Task {
            let installed = await Task.detached { ShortcutInstaller.findInstalled() }.value
            preferences.dndShortcutOnID = installed.on
            preferences.dndShortcutOffID = installed.off
            onFound = installed.on != nil
            offFound = installed.off != nil
            showSteps = !ready
            if !ready { test = .idle }
            environment.enabledFeaturesDidChange()
        }
    }

    /// The only honest check on macOS 26: run the on-shortcut and let the user's own eyes
    /// confirm the menu-bar moon. Focus state can't be read reliably from outside the app.
    private func runTest() {
        guard let onID = preferences.dndShortcutOnID else { return }
        test = .running
        Task {
            _ = await Task.detached { ShortcutsRunner.run(uuid: onID) }.value
            try? await Task.sleep(for: .seconds(1))
            askMoon = true
        }
    }

    private func runOff() {
        guard let offID = preferences.dndShortcutOffID else { return }
        Task { _ = await Task.detached { ShortcutsRunner.run(uuid: offID) }.value }
    }

    private func openShortcuts() {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.shortcuts"
        ) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}
