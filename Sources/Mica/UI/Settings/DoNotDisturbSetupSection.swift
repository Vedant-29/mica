import AppKit
import MicaCore
import SwiftUI

/// Do Not Disturb: the feature toggle plus its one-time setup.
///
/// macOS has no API a third-party app can call to change Focus, so Mica runs a Shortcut
/// from the user's library. Setup is confirmed by running the shortcut and checking the
/// Focus daemon's log — the one detection method that works on macOS 26 — rather than by
/// trusting the import, which can silently produce a shortcut that does nothing.
struct DoNotDisturbSetupSection: View {
    @Bindable var environment: AppEnvironment

    private enum Step: Equatable {
        case checking
        case notReady
        case creating
        case waitingForUser
        case verifying
        case ready
        case notWorking
    }

    @State private var step: Step = .checking
    @State private var showManualSteps = false

    private var preferences: Preferences { environment.preferences }

    var body: some View {
        Section("Do Not Disturb") {
            Toggle("Silence notifications while Mica is on", isOn: Binding(
                get: { preferences.isEnabled(.doNotDisturb) },
                set: { preferences.setEnabled($0, for: .doNotDisturb); environment.enabledFeaturesDidChange() }
            ))

            switch step {
            case .checking:
                progress("Checking setup.")

            case .notReady:
                Text("macOS only lets apps change Focus through a Shortcut. Set one up once:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Create Automatically") { createAutomatically() }
                Button(showManualSteps ? "Hide Manual Steps" : "Create Manually") {
                    showManualSteps.toggle()
                }
                .buttonStyle(.link)
                if showManualSteps { manualSteps }

            case .creating:
                progress("Making the shortcuts, this takes a few seconds.")

            case .waitingForUser:
                Text("Shortcuts opened twice, once for each. Click Add Shortcut in both, then come back.")
                    .font(.callout)
                Button("I Added Them") { locateThenVerify() }
                Button("Cancel") { step = .notReady }
                    .buttonStyle(.link)

            case .verifying:
                progress("Turning Do Not Disturb on and off to confirm it works.")

            case .ready:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Ready").font(.callout)
                }
                Button("Test Again") { verify() }

            case .notWorking:
                Text("The shortcut was added but didn't turn Focus on. Fix it in one step:")
                    .font(.callout)
                Text("In Shortcuts, open **\(ShortcutInstaller.onName)** and make it read **Turn Do Not Disturb On until Turned Off** — the state must be **On**, not Off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open Shortcuts") { openShortcuts() }
                    Button("Check Again") { verify() }
                }
            }

            if hasDuplicateShortcuts {
                Text("More than one shortcut has these names. Delete the extras in Shortcuts so Mica runs the right one.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await initialCheck() }
    }

    // MARK: - Pieces

    private func progress(_ message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(message).font(.callout).foregroundStyle(.secondary)
        }
    }

    private var manualSteps: some View {
        VStack(alignment: .leading, spacing: 4) {
            step("1.", "Open Shortcuts and click + for a new shortcut.")
            step("2.", "Search for “Set Focus” and add it.")
            step("3.", "Make it read “Turn Do Not Disturb On until Turned Off”.")
            step("4.", "Name it exactly **\(ShortcutInstaller.onName)**.")
            step("5.", "Make a second one set to **Off**, named **\(ShortcutInstaller.offName)**.")
            HStack {
                Button("Open Shortcuts") { openShortcuts() }
                Button("I Made Them") { locateThenVerify() }
            }
            .padding(.top, 2)
        }
        .padding(.top, 4)
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(number).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            Text(.init(text)).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Flow

    @State private var hasDuplicateShortcuts = false

    private func initialCheck() async {
        await locate()
        if preferences.dndShortcutOnID != nil, preferences.dndShortcutOffID != nil {
            // Shortcuts exist from a previous session. Trust them rather than toggling
            // Focus on every visit to the tab; the user can Test Again if unsure.
            step = .ready
        } else {
            step = .notReady
        }
    }

    private func createAutomatically() {
        step = .creating
        Task {
            do {
                try await ShortcutInstaller.install()
                step = .waitingForUser
            } catch {
                step = .notReady
            }
        }
    }

    private func locateThenVerify() {
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

    private func runVerification() async {
        guard let onID = preferences.dndShortcutOnID,
              let offID = preferences.dndShortcutOffID else { return }
        step = .verifying
        let worked = await DNDActivationCheck.verify(onID: onID, offID: offID)
        // Keep the in-session state honest for engage/release.
        environment.engagement.doNotDisturb.noteChangedByMica(to: false)
        step = worked ? .ready : .notWorking
    }

    private func locate() async {
        let all = await Task.detached { ShortcutsRunner.list() }.value
        hasDuplicateShortcuts = all.filter { $0.name == ShortcutInstaller.onName }.count > 1
            || all.filter { $0.name == ShortcutInstaller.offName }.count > 1

        let installed = await Task.detached { ShortcutInstaller.findInstalled() }.value
        preferences.dndShortcutOnID = installed.on
        preferences.dndShortcutOffID = installed.off
        environment.enabledFeaturesDidChange()
    }

    private func openShortcuts() {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.shortcuts"
        ) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}
