import MicaCore
import SwiftUI

/// The menu bar panel: header with the mode control, the six feature rows, then
/// Settings and Quit.
struct PopoverRootView: View {
    @Bindable var environment: AppEnvironment

    @Environment(\.openSettings) private var openSettings

    private var preferences: Preferences { environment.preferences }

    var body: some View {
        VStack(spacing: 0) {
            header
            StatusBannerView(
                decision: environment.engagement.decision,
                capturerName: environment.engagement.capturerName
            )
            divider
            featureList
            divider
            footer
        }
        .frame(width: Theme.popoverWidth)
        .padding(.vertical, 6)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Mica")
                .font(.system(size: 15, weight: .semibold))
            Text("⌥⌘S")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            ModeSegmentedControl(mode: Binding(
                get: { preferences.mode },
                set: { preferences.mode = $0; environment.modeDidChange() }
            ))
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var featureList: some View {
        VStack(spacing: 0) {
            ForEach(Feature.allCases) { feature in
                FeatureToggleRow(
                    feature: feature,
                    isEnabled: preferences.isEnabled(feature),
                    // A failing effect says so on its own row rather than failing silently
                    // or taking the other five down with it — but only once you've asked
                    // for it. Warning about a feature that's switched off is just noise,
                    // and it reads as though something is broken when nothing is.
                    problem: preferences.isEnabled(feature)
                        ? environment.coordinator.errors[feature]
                            ?? environment.coordinator.effects[feature]?.unavailableReason
                        : nil
                ) {
                    preferences.setEnabled(!preferences.isEnabled(feature), for: feature)
                    environment.enabledFeaturesDidChange()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            MenuActionRow(title: "Settings", symbolName: "gearshape") {
                // An accessory app is never the active app, so a window opened from the
                // menu bar surfaces behind whatever the user was looking at unless we
                // activate first.
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            MenuActionRow(title: "Quit Mica", symbolName: "xmark.square") {
                environment.terminate()
            }
        }
        .padding(.top, 4)
    }

    private var divider: some View {
        Divider().padding(.horizontal, Theme.horizontalPadding)
    }
}
