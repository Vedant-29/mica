import KeyboardShortcuts
import MicaCore
import SwiftUI

struct SettingsRootView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        TabView {
            GeneralSettingsView(environment: environment)
                .tabItem { Label("General", systemImage: "gearshape") }
            FeaturesSettingsView(environment: environment)
                .tabItem { Label("Features", systemImage: "eye.slash") }
            AppsSettingsView(environment: environment)
                .tabItem { Label("Apps", systemImage: "app.badge") }
            ScheduleSettingsView(environment: environment)
                .tabItem { Label("Schedule", systemImage: "clock") }
            ShortcutSettingsView(environment: environment)
                .tabItem { Label("Shortcut", systemImage: "command") }
        }
        .frame(width: 520, height: 430)
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
            Section("Screen Share") {
                Toggle(
                    "Activate when screen is shared or recorded",
                    isOn: binding(\.triggerScreenCapture)
                )
                .disabled(!ScreenCaptureMonitor.isSupported)

                if !ScreenCaptureMonitor.isSupported {
                    Text("This version of macOS no longer reports when the screen is being captured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Screen Mirroring") {
                Toggle(
                    "Activate when screen is mirrored or extended",
                    isOn: binding(\.triggerDisplayChange)
                )
            }

            Section("Login") {
                Toggle("Open Mica upon startup", isOn: $launchAtLogin)
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

    var body: some View {
        Form {
            Section {
                ForEach(Feature.allCases) { feature in
                    Toggle(feature.displayName, isOn: Binding(
                        get: { preferences.isEnabled(feature) },
                        set: { preferences.setEnabled($0, for: feature); environment.enabledFeaturesDidChange() }
                    ))

                    if feature == .hideWindows, preferences.isEnabled(.hideWindows) {
                        Picker("Hide", selection: Binding(
                            get: { preferences.hideWindowsScope },
                            set: { preferences.hideWindowsScope = $0; environment.settingsDidChange() }
                        )) {
                            ForEach(HideWindowsScope.allCases, id: \.self) {
                                Text($0.displayName).tag($0)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .padding(.leading, 20)
                    }

                    if let reason = environment.coordinator.effects[feature]?.unavailableReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            DoNotDisturbSetupSection(environment: environment)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Schedule

struct ScheduleSettingsView: View {
    @Bindable var environment: AppEnvironment

    private var preferences: Preferences { environment.preferences }

    var body: some View {
        Form {
            Section {
                Toggle("Activate during the following time window", isOn: Binding(
                    get: { preferences.triggerSchedule },
                    set: { preferences.triggerSchedule = $0; environment.settingsDidChange() }
                ))

                DatePicker("From", selection: timeBinding(\.scheduleStartMinutes), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: timeBinding(\.scheduleEndMinutes), displayedComponents: .hourAndMinute)
            }
            .disabled(!preferences.triggerSchedule)

            Section {
                Text("A window ending before it starts runs overnight — 22:00 until 06:00 covers the small hours.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
            set: { date in
                preferences[keyPath: keyPath] = ScheduleWindow.minutes(from: date)
                environment.settingsDidChange()
            }
        )
    }
}

// MARK: - Shortcut

struct ShortcutSettingsView: View {
    @Bindable var environment: AppEnvironment

    private var preferences: Preferences { environment.preferences }

    var body: some View {
        Form {
            Section {
                Toggle("Trigger Mica with a keyboard shortcut", isOn: Binding(
                    get: { preferences.hotkeyEnabled },
                    set: { preferences.hotkeyEnabled = $0 }
                ))
                KeyboardShortcuts.Recorder("Shortcut:", name: .toggleMica)
                    .disabled(!preferences.hotkeyEnabled)
            }

            Section {
                Text("""
                    While Mica is On or Off, the shortcut switches between them. While it's \
                    set to Auto, the shortcut overrides whatever the triggers decided — and \
                    that override clears itself once the trigger goes away, so the next \
                    screen share still turns Mica on.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
