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
            // Promoted from the Triggers tab: this is the pair almost everyone actually
            // sets, and burying them behind a tab left this page looking half-finished.
            Section("Turn on automatically") {
                Toggle("When my screen is shared or recorded", isOn: binding(\.triggerScreenCapture))
                    .disabled(!ScreenCaptureMonitor.isSupported)
                if !ScreenCaptureMonitor.isSupported {
                    Text("This version of macOS no longer reports when the screen is being captured.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Toggle("When a display is mirrored or extended", isOn: binding(\.triggerDisplayChange))
                Text("Fires whenever a second display is attached, so leave this off at a desk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("These only apply in Auto. App and schedule rules are on the Triggers tab.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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

                Text("""
                    In On or Off, the shortcut switches between them. In Auto it overrides \
                    whatever the triggers decided — and that override clears itself once the \
                    trigger goes away, so the next screen share still turns Mica on.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    /// Hide Active Windows has its own tab, since it is the one most people actually
    /// configure and it needs the room.
    private var featuresShownHere: [Feature] {
        Feature.allCases.filter { $0 != .hideWindows }
    }

    var body: some View {
        Form {
            Section("What Mica hides") {
                Toggle(Feature.hideWindows.displayName, isOn: binding(for: .hideWindows))
                Text("Configured on the Windows tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(featuresShownHere) { feature in
                    Toggle(feature.displayName, isOn: binding(for: feature))

                    if let note = feature.note, preferences.isEnabled(feature) {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if preferences.isEnabled(feature),
                       let reason = environment.coordinator.effects[feature]?.unavailableReason {
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

            Section {
                Text("""
                    Mica hides applications, it doesn't close them — nothing you have open is \
                    lost, and everything comes back exactly as it was. An app you'd already \
                    hidden yourself stays hidden.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Section {
                Text("Screen sharing and display triggers live on the General tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Schedule") {
                Toggle("During a daily time window", isOn: binding(\.triggerSchedule))
                DatePicker("From", selection: timeBinding(\.scheduleStartMinutes), displayedComponents: .hourAndMinute)
                    .disabled(!preferences.triggerSchedule)
                DatePicker("Until", selection: timeBinding(\.scheduleEndMinutes), displayedComponents: .hourAndMinute)
                    .disabled(!preferences.triggerSchedule)
                Text("A window ending before it starts runs overnight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Trigger Apps") {
                Toggle("When one of these apps is running", isOn: binding(\.triggerApps))
                AppGridView(
                    store: environment.triggerApps,
                    showsAction: true,
                    emptyMessage: "Add apps that should turn Mica on.",
                    onChange: { environment.settingsDidChange() }
                )
                .disabled(!preferences.triggerApps)
                Text("Activate turns Mica on by itself. Remind me just offers a prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Excluded Apps") {
                Toggle("Never activate while one of these is running", isOn: binding(\.exclusionsEnabled))
                AppGridView(
                    store: environment.excludedApps,
                    emptyMessage: "Add apps that should block automatic activation.",
                    onChange: { environment.settingsDidChange() }
                )
                .disabled(!preferences.exclusionsEnabled)
                Text("Applies in Auto only. Switching Mica On always wins.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !environment.notifier.systemNotificationsAvailable {
                    Text("""
                        Reminders use Mica's own banner rather than a system notification, \
                        because macOS only grants notification access to apps signed with a \
                        notarized Developer ID.
                        """)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
