import AppKit
import MicaCore
import SwiftUI

/// Do Not Disturb: the feature toggle and its one-time setup, together.
///
/// macOS has no API a third-party app can call to change Focus, so Mica runs a Shortcut
/// from the user's own library.
///
/// The setup verifies itself. A generated shortcut can import perfectly and still do
/// nothing if the action parameters aren't what this macOS expects, and that failure is
/// invisible: the Shortcuts library is TCC-protected and signed shortcut files are
/// encrypted, so Mica cannot inspect what actually got imported. Running it and watching
/// for the Focus change is the only way to know, so it happens automatically rather than
/// waiting for the user to think of pressing Test.
struct DoNotDisturbSetupSection: View {
    @Bindable var environment: AppEnvironment

    private enum Step: Equatable {
        case needsSetup
        case creating
        case waitingForUser
        case checking
        case ready
        case needsManualFix
        case failed(String)
    }

    @State private var step: Step = .needsSetup
    @State private var isTesting = false
    @State private var hasDuplicates = false

    private var preferences: Preferences { environment.preferences }

    var body: some View {
        Section("Do Not Disturb") {
            Toggle("Silence notifications while Mica is on", isOn: Binding(
                get: { preferences.isEnabled(.doNotDisturb) },
                set: { preferences.setEnabled($0, for: .doNotDisturb); environment.enabledFeaturesDidChange() }
            ))

            switch step {
            case .needsSetup:
                Text("macOS only lets apps change Focus through a Shortcut. Mica will make two, one to turn Do Not Disturb on and one to turn it off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Set Up") { beginSetup() }

            case .creating:
                progress("Making the shortcuts, this takes a few seconds.")

            case .waitingForUser:
                Text("Shortcuts opened twice, once for each. Click Add Shortcut in both, then come back.")
                    .font(.callout)
                Button("I Added Them") { confirmAndVerify() }
                Button("Cancel") { step = .needsSetup }
                    .buttonStyle(.link)

            case .checking:
                progress("Checking that they work.")

            case .ready:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Ready").font(.callout)
                }
                HStack {
                    Button(isTesting ? "Testing" : "Test Again") { verify() }
                        .disabled(isTesting)
                    Button("Make Again") { step = .needsSetup }
                }
                if hasDuplicates {
                    Text("There is more than one shortcut with these names. Delete the extras in Shortcuts, otherwise Mica may run the wrong one.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

            case .needsManualFix:
                Text("The shortcuts were added but didn't change Focus. One thing to fix:")
                    .font(.callout)
                Text("In Shortcuts, open **\(ShortcutInstaller.onName)** and change **Off** to **On**.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open Shortcuts") { openShortcutsApp() }
                    Button(isTesting ? "Checking" : "Check Again") { verify() }
                        .disabled(isTesting)
                }

            case .failed(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { beginSetup() }
            }
        }
        .task { refresh() }
    }

    private func progress(_ message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(message).font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: - Flow

    private func beginSetup() {
        step = .creating
        Task {
            do {
                try await ShortcutInstaller.install()
                step = .waitingForUser
            } catch {
                step = .failed(String(describing: error))
            }
        }
    }

    private func confirmAndVerify() {
        Task {
            await locate()
            guard preferences.dndShortcutOnID != nil, preferences.dndShortcutOffID != nil else {
                step = .waitingForUser
                return
            }
            await runVerification()
        }
    }

    private func verify() {
        Task { await runVerification() }
    }

    /// Turns Focus on, watches for the change, then puts it back.
    private func runVerification() async {
        guard let onID = preferences.dndShortcutOnID,
              let offID = preferences.dndShortcutOffID else { return }

        isTesting = true
        step = .checking
        let monitor = environment.engagement.doNotDisturb

        // Start from a known state, otherwise "already on" reads as a failure.
        _ = await Task.detached { ShortcutsRunner.run(uuid: offID) }.value
        try? await Task.sleep(for: .seconds(1))

        let ran = await Task.detached { ShortcutsRunner.run(uuid: onID) }.value
        try? await Task.sleep(for: .seconds(1, milliseconds: 500))
        let turnedOn = monitor.isEnabled == true

        _ = await Task.detached { ShortcutsRunner.run(uuid: offID) }.value
        try? await Task.sleep(for: .seconds(1))

        step = (ran && turnedOn) ? .ready : .needsManualFix
        isTesting = false
    }

    private func refresh() {
        Task {
            await locate()
            let configured = preferences.dndShortcutOnID != nil && preferences.dndShortcutOffID != nil
            if configured, step == .needsSetup {
                // Already set up from a previous run; trust it rather than re-testing on
                // every visit to the tab, which would flick Focus on and off each time.
                step = .ready
            }
        }
    }

    private func locate() async {
        let all = await Task.detached { ShortcutsRunner.list() }.value
        hasDuplicates = all.filter { $0.name == ShortcutInstaller.onName }.count > 1
            || all.filter { $0.name == ShortcutInstaller.offName }.count > 1

        let installed = await Task.detached { ShortcutInstaller.findInstalled() }.value
        if let on = installed.on { preferences.dndShortcutOnID = on }
        if let off = installed.off { preferences.dndShortcutOffID = off }
        environment.enabledFeaturesDidChange()
    }

    private func openShortcutsApp() {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.shortcuts"
        ) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}

extension Duration {
    fileprivate static func seconds(_ whole: Int, milliseconds: Int) -> Duration {
        .milliseconds(whole * 1000 + milliseconds)
    }
}
