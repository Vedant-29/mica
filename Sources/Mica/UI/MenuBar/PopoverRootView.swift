import MicaCore
import SwiftUI

/// The menu bar panel: header with the mode control, the six feature rows, then
/// Settings and Quit.
struct PopoverRootView: View {
    @Bindable var preferences: Preferences

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
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
            ModeSegmentedControl(mode: $preferences.mode)
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
                    isEnabled: preferences.isEnabled(feature)
                ) {
                    preferences.setEnabled(!preferences.isEnabled(feature), for: feature)
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
                NSApp.terminate(nil)
            }
        }
        .padding(.top, 4)
    }

    private var divider: some View {
        Divider().padding(.horizontal, Theme.horizontalPadding)
    }
}
