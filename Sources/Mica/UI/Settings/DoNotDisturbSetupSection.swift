import AppKit
import MicaCore
import SwiftUI

/// Do Not Disturb setup.
///
/// macOS has no API a third-party app can call to turn Focus on, so Mica runs a Shortcut
/// from the user's own library. That is unavoidable, which makes it worth presenting as a
/// short guided flow with a visible state rather than a row of buttons the user has to
/// work out the order of.
struct DoNotDisturbSetupSection: View {
    @Bindable var environment: AppEnvironment

    private enum Step {
        case needsSetup
        case waitingForUser
        case ready
    }

    @State private var step: Step = .needsSetup
    @State private var shortcuts: [ShortcutsRunner.Shortcut] = []
    @State private var testResult: String?
    @State private var isTesting = false

    private var preferences: Preferences { environment.preferences }

    var body: some View {
        Section("Do Not Disturb") {
            switch step {
            case .needsSetup:
                Text("macOS only lets apps turn on Focus through a Shortcut. Mica can create it for you.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Set Up") { beginSetup() }
                    .controlSize(.large)

            case .waitingForUser:
                Label("Click Add Shortcut in the two windows that just opened.", systemImage: "1.circle.fill")
                    .font(.callout)
                Button("Done, Check Again") { refresh() }
                    .controlSize(.large)
                Button("Cancel") { step = .needsSetup }
                    .buttonStyle(.link)

            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
                HStack {
                    Button(isTesting ? "Testing..." : "Test") { runTest() }
                        .disabled(isTesting)
                    Button("Set Up Again") { step = .needsSetup }
                }
                if let testResult {
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(testResult.hasPrefix("Works")
                            ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task { refresh() }
    }

    private func beginSetup() {
        step = .waitingForUser
        testResult = nil
        Task.detached {
            try? ShortcutInstaller.install()
        }
    }

    private func refresh() {
        Task.detached {
            let found = ShortcutsRunner.list()
            let installed = ShortcutInstaller.findInstalled()
            await MainActor.run {
                shortcuts = found
                if let on = installed.on { preferences.dndShortcutOnID = on }
                if let off = installed.off { preferences.dndShortcutOffID = off }
                step = (preferences.dndShortcutOnID != nil && preferences.dndShortcutOffID != nil)
                    ? .ready
                    : (step == .waitingForUser ? .waitingForUser : .needsSetup)
                environment.enabledFeaturesDidChange()
            }
        }
    }

    /// Runs the shortcut and checks Focus actually changed.
    ///
    /// A shortcut can import perfectly and still do nothing if the action's parameters
    /// aren't what this macOS expects, and silently doing nothing is the one failure the
    /// user would never spot on their own.
    private func runTest() {
        guard let onID = preferences.dndShortcutOnID,
              let offID = preferences.dndShortcutOffID else { return }

        isTesting = true
        testResult = nil
        let monitor = environment.engagement.doNotDisturb

        Task {
            let ran = await Task.detached { ShortcutsRunner.run(uuid: onID) }.value
            try? await Task.sleep(for: .seconds(1))
            let changed = monitor.isEnabled == true

            _ = await Task.detached { ShortcutsRunner.run(uuid: offID) }.value
            try? await Task.sleep(for: .seconds(1))

            testResult = if ran && changed {
                "Works. Do Not Disturb turned on and back off."
            } else {
                "The shortcut ran but Focus did not change. Open it in Shortcuts and set the action to Do Not Disturb, On."
            }
            isTesting = false
        }
    }
}
