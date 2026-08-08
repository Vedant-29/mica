import KeyboardShortcuts
import MicaCore
import SwiftUI

struct SettingsRootView: View {
    @Bindable var environment: AppEnvironment
    @State var selectedTab: SettingsTab

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selection: $selectedTab)
            Divider()

            Group {
                switch selectedTab {
                case .general: GeneralSettingsView(environment: environment)
                case .features: FeaturesSettingsView(environment: environment)
                case .windows: WindowsSettingsView(environment: environment)
                case .triggers: TriggersSettingsView(environment: environment)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 600, height: 520)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @Bindable var environment: AppEnvironment

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    private var preferences: Preferences { environment.preferences }

    var body: some View {
        Form {
            Section("Turn On Automatically") {
                Toggle("When my screen is shared or recorded", isOn: binding(\.triggerScreenCapture))
                    .disabled(!ScreenCaptureMonitor.isSupported)
                Toggle("When a display is mirrored or extended", isOn: binding(\.triggerDisplayChange))
            }

            Section("Startup") {
                Toggle("Open Mica when you log in", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        if case .failure(let error) = LaunchAtLogin.setEnabled(enabled) {
                            launchError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        } else {
                            launchError = nil
                        }
                    }
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Keyboard Shortcut") {
                Toggle("Use a keyboard shortcut", isOn: Binding(
                    get: { preferences.hotkeyEnabled },
                    set: { preferences.hotkeyEnabled = $0 }
                ))
                KeyboardShortcuts.Recorder("Toggle Mica:", name: .toggleMica)
                    .disabled(!preferences.hotkeyEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<Preferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { preferences[keyPath: keyPath] },
            set: { preferences[keyPath: keyPath] = $0; environment.settingsDidChange() }
        )
    }
}

// MARK: - Features

struct FeaturesSettingsView: View {
    @Bindable var environment: AppEnvironment

    private var preferences: Preferences { environment.preferences }

    /// Hide Active Windows lives on its own tab, toggle included. Listing it here too,
    /// with a line telling the user to go elsewhere, is a redirect where a control
    /// should be.
    private var simpleFeatures: [Feature] {
        Feature.allCases.filter { $0 != .hideWindows && $0 != .doNotDisturb }
    }

    var body: some View {
        Form {
            Section("What Mica Hides") {
                ForEach(simpleFeatures) { feature in
                    Toggle(feature.displayName, isOn: binding(for: feature))
                }
            }

            DoNotDisturbSetupSection(environment: environment)
        }
        .formStyle(.grouped)
    }

    private func binding(for feature: Feature) -> Binding<Bool> {
        Binding(
            get: { preferences.isEnabled(feature) },
            set: { preferences.setEnabled($0, for: feature); environment.enabledFeaturesDidChange() }
        )
    }
}

// MARK: - Windows

struct WindowsSettingsView: View {
    @Bindable var environment: AppEnvironment

    private var preferences: Preferences { environment.preferences }

    var body: some View {
        Form {
            Section("Hide Active Windows") {
                Toggle("Hide windows while Mica is on", isOn: Binding(
                    get: { preferences.isEnabled(.hideWindows) },
                    set: { preferences.setEnabled($0, for: .hideWindows); environment.enabledFeaturesDidChange() }
                ))

                Picker("Hide:", selection: Binding(
                    get: { preferences.hideWindowsScope },
                    set: { preferences.hideWindowsScope = $0; environment.settingsDidChange() }
                )) {
                    ForEach(HideWindowsScope.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(!preferences.isEnabled(.hideWindows))
            }

            if preferences.hideWindowsScope.usesAppList {
                Section(preferences.hideWindowsScope.listCaption) {
                    AppGridView(
                        store: environment.windowApps,
                        emptyMessage: emptyMessage,
                        onChange: { environment.settingsDidChange() }
                    )
                    .disabled(!preferences.isEnabled(.hideWindows))
                }
            }
        }
        .formStyle(.grouped)
    }

    private var emptyMessage: String {
        switch preferences.hideWindowsScope {
        case .onlySelected: "Add the apps you want hidden."
        case .allExceptSelected: "Add the apps you want to stay visible."
        default: ""
        }
    }
}

// MARK: - Triggers

struct TriggersSettingsView: View {
    @Bindable var environment: AppEnvironment

    private var preferences: Preferences { environment.preferences }

    var body: some View {
        Form {
            Section("Trigger Apps") {
                Toggle("Turn on when one of these is running", isOn: binding(\.triggerApps))
                AppGridView(
                    store: environment.triggerApps,
                    showsAction: true,
                    emptyMessage: "Add apps that should turn Mica on.",
                    onChange: { environment.settingsDidChange() }
                )
                .disabled(!preferences.triggerApps)
            }

            Section("Excluded Apps") {
                Toggle("Never turn on while one of these is running", isOn: binding(\.exclusionsEnabled))
                AppGridView(
                    store: environment.excludedApps,
                    emptyMessage: "Add apps that should block Mica.",
                    onChange: { environment.settingsDidChange() }
                )
                .disabled(!preferences.exclusionsEnabled)
            }

            Section("Schedule") {
                Toggle("Turn on during a daily time window", isOn: binding(\.triggerSchedule))
                DatePicker("From", selection: timeBinding(\.scheduleStartMinutes), displayedComponents: .hourAndMinute)
                    .disabled(!preferences.triggerSchedule)
                DatePicker("Until", selection: timeBinding(\.scheduleEndMinutes), displayedComponents: .hourAndMinute)
                    .disabled(!preferences.triggerSchedule)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<Preferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { preferences[keyPath: keyPath] },
            set: { preferences[keyPath: keyPath] = $0; environment.settingsDidChange() }
        )
    }

    /// `DatePicker` wants a `Date`; the preference is minutes past midnight, which is
    /// immune to time-zone and daylight-saving drift.
    private func timeBinding(_ keyPath: ReferenceWritableKeyPath<Preferences, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = preferences[keyPath: keyPath]
                return Calendar.current.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()
                ) ?? Date()
            },
            set: {
                preferences[keyPath: keyPath] = ScheduleWindow.minutes(from: $0)
                environment.settingsDidChange()
            }
        )
    }
}
