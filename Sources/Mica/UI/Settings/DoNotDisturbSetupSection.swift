import AppKit
import MicaCore
import SwiftUI

/// Do Not Disturb: the feature toggle plus a small one-time setup.
///
/// macOS only lets an app change Focus by running a Shortcut, so setup creates two of them
/// and then confirms they work by running the on-shortcut and watching the Focus daemon's
/// log — the one detection method that works on macOS 26. Nothing is reported as "Ready"
/// unless Focus actually changed.
struct DoNotDisturbSetupSection: View {
    @Bindable var environment: AppEnvironment

    private enum Step: Equatable {
        case checking, notReady, creating, waiting, verifying, ready, notWorking
    }

    @State private var step: Step = .checking

    private var preferences: Preferences { environment.preferences }

    var body: some View {
        Section("Do Not Disturb") {
            Toggle("Silence notifications while Mica is on", isOn: Binding(
                get: { preferences.isEnabled(.doNotDisturb) },
                set: { preferences.setEnabled($0, for: .doNotDisturb); environment.enabledFeaturesDidChange() }
            ))

            switch step {
            case .checking:
                busy("Checking setup")

            case .notReady:
                Text("macOS needs a Shortcut to change Focus. Mica can make it for you.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Set Up") { create() }

            case .creating:
                busy("Making the shortcuts")

            case .waiting:
                Text("Click Add Shortcut in each window that opened, then:")
                    .font(.callout)
                Button("Done") { verify() }
                labelQuirkNote

            case .verifying:
                busy("Testing")

            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout)
                labelQuirkNote

            case .notWorking:
                Text("The shortcut didn't turn Focus on. Open it in Shortcuts and make sure it reads “Turn Do Not Disturb On”, then check again.")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open Shortcuts") { openShortcuts() }
                    Button("Check Again") { verify() }
                }
            }
        }
        .task { await load() }
    }

    private func busy(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
    }

    /// Pre-empts the single biggest source of confusion here. The Shortcuts editor
    /// mislabels this action as "Turn Do Not Disturb Off" even though it turns Focus on —
    /// a cosmetic quirk of how it re-renders the action. Mica confirms the real behaviour
    /// against the Focus daemon, so the label can be safely ignored.
    private var labelQuirkNote: some View {
        Text("The Shortcuts app may show this as “Off” — that's a display glitch in Shortcuts. Mica checks that it really turns Focus on.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Flow

    private func load() async {
        await locate()
        step = configured ? .ready : .notReady
    }

    private func create() {
        step = .creating
        Task {
            do {
                try await ShortcutInstaller.install()
                step = .waiting
            } catch {
                step = .notReady
            }
        }
    }

    private func verify() {
        Task {
            await locate()
            guard configured else { step = .waiting; return }
            step = .verifying
            let worked = await DNDActivationCheck.verify(
                onID: preferences.dndShortcutOnID!,
                offID: preferences.dndShortcutOffID!
            )
            step = worked ? .ready : .notWorking
        }
    }

    private var configured: Bool {
        preferences.dndShortcutOnID != nil && preferences.dndShortcutOffID != nil
    }

    private func locate() async {
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
