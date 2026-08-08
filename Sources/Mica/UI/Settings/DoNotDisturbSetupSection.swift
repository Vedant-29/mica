import AppKit
import MicaCore
import SwiftUI

/// Do Not Disturb: the feature toggle and its one-time setup, together.
///
/// macOS has no API a third-party app can call to change Focus, so Mica runs a Shortcut
/// from the user's own library. That is unavoidable, which makes it worth presenting as a
/// short flow with a visible state rather than a row of buttons whose order you have to
/// work out.
struct DoNotDisturbSetupSection: View {
    @Bindable var environment: AppEnvironment

    private enum Step: Equatable {
        case needsSetup
        case creating
        case waitingForUser
        case ready
        case failed(String)
    }

    @State private var step: Step = .needsSetup
    @State private var testResult: String?
    @State private var isTesting = false

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
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Making the shortcuts, this takes a few seconds.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

            case .waitingForUser:
                Text("Shortcuts opened twice, once for each. Click Add Shortcut in both, then come back.")
                    .font(.callout)
                Button("I Added Them") { refresh() }
                Button("Cancel") { step = .needsSetup }
                    .buttonStyle(.link)

            case .ready:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Ready").font(.callout)
                }
                HStack {
                    Button(isTesting ? "Testing" : "Test") { runTest() }
                        .disabled(isTesting)
                    Button("Make Again") { step = .needsSetup }
                }
                if let testResult {
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(testResult.hasPrefix("Works")
                            ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                        .fixedSize(horizontal: false, vertical: true)
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

    private func beginSetup() {
        step = .creating
        testResult = nil
        Task {
            do {
                try await ShortcutInstaller.install()
                step = .waitingForUser
            } catch {
                step = .failed(String(describing: error))
            }
        }
    }

    private func refresh() {
        Task.detached {
            let installed = ShortcutInstaller.findInstalled()
            await MainActor.run {
                if let on = installed.on { preferences.dndShortcutOnID = on }
                if let off = installed.off { preferences.dndShortcutOffID = off }

                let configured = preferences.dndShortcutOnID != nil && preferences.dndShortcutOffID != nil
                if configured {
                    step = .ready
                } else if step != .waitingForUser && step != .creating {
                    step = .needsSetup
                }
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
