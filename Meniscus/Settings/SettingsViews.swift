import AppKit
import SwiftUI

/// Every Settings tab scrolls and grows with the window, which can be resized.
extension View {
    func settingsPage() -> some View {
        formStyle(.grouped)
            .frame(minWidth: 480, maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
    }
}

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    @AppStorage(SettingsKey.showMenuBarIcon) private var showMenuBarIcon = true
    @State private var opensAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, isOn in
                        loginError = LaunchAtLogin.set(isOn)
                        opensAtLogin = LaunchAtLogin.isEnabled
                    }
                if let loginError {
                    Text(loginError).foregroundStyle(.red)
                }
                Toggle("Show icon in the menu bar", isOn: $showMenuBarIcon)
            } footer: {
                if !showMenuBarIcon {
                    Text("To open Settings, open Meniscus again from the Applications folder or Spotlight.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("Show on", selection: $settings.displayPreference) {
                    ForEach(DisplayPreference.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Open when the pointer rests on the notch", isOn: $settings.expandOnHover)
                Toggle("Haptic feedback on the trackpad", isOn: $settings.hapticsEnabled)
            }
            Section {
                Toggle("Hide from screenshots and screen sharing", isOn: $settings.hideFromScreenCapture)
            } footer: {
                Text("macOS doesn't tell apps when the screen is shared, so to keep the island out of a presentation it can be left out of screenshots, recordings and screen sharing (where the system honors it). Turn this off to take a screenshot of the island.")
                    .foregroundStyle(.secondary)
            }
        }
        .settingsPage()
    }
}

struct LiveActivitiesSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Upcoming meetings", isOn: $settings.showMeetingReminders)
                    .onChange(of: settings.showMeetingReminders) { ActivityServices.shared.updateCalendar(settings: settings) }
                Toggle("Low battery", isOn: $settings.showLowBattery)
                Toggle("Charging", isOn: $settings.showCharging)
                Toggle("Keyboard layout", isOn: $settings.showInputSource)
                    .onChange(of: settings.showInputSource) { ActivityServices.shared.updateInputSource(settings: settings) }
                Toggle("Quick capture saved", isOn: $settings.showCaptureConfirmation)
                Toggle("Bluetooth devices", isOn: $settings.showBluetoothDevices)
                    .onChange(of: settings.showBluetoothDevices) { ActivityServices.shared.updateBluetoothDevices(settings: settings) }
                Toggle("Bluetooth device low battery", isOn: $settings.showDeviceLowBattery)
                    .onChange(of: settings.showDeviceLowBattery) { ActivityServices.shared.updateBluetoothDevices(settings: settings) }
            } footer: {
                Text("Short notices in the closed notch: a meeting 5 minutes ahead and when it starts (Join for Zoom, Meet and Teams is in the open island), the battery at 20% and 10%, the charger, a new keyboard layout, a saved quick capture, a Bluetooth headset, mouse, keyboard or gamepad connecting (with its battery) and at 20% and 10%. AirPods and other Apple devices are left to macOS's own window. They stay hidden while an app is in full screen.")
                    .foregroundStyle(.secondary)
            }
        }
        .settingsPage()
    }
}

struct MusicSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Show what's playing", isOn: $settings.showNowPlaying)
                    .onChange(of: settings.showNowPlaying) { _, isOn in
                        let nowPlaying = ActivityServices.shared.nowPlaying
                        if isOn { nowPlaying.start() } else { nowPlaying.stop() }
                    }
            } footer: {
                NowPlayingStatus(availability: ActivityServices.shared.nowPlaying.availability)
            }
            Section {
                LabeledContent {
                    Button("License") { Acknowledgements.open("mediaremote-adapter-LICENSE") }
                        .buttonStyle(.link)
                } label: {
                    Text(verbatim: "mediaremote-adapter")
                }
            } header: {
                Text("Acknowledgements")
            } footer: {
                Text("Reads what's playing on this Mac. BSD 3-Clause License, © Jonas van den Berg and contributors.")
                    .foregroundStyle(.secondary)
            }
        }
        .settingsPage()
    }
}

struct CalendarSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Show the next calendar event", isOn: $settings.showCalendar)
                    .onChange(of: settings.showCalendar) { ActivityServices.shared.updateCalendar(settings: settings) }
            } footer: {
                Text("Calendar access is requested the first time you open the island with this on.")
                    .foregroundStyle(.secondary)
            }
            if settings.showCalendar || settings.showMeetingReminders {
                CalendarSelectionSection(settings: settings, calendar: ActivityServices.shared.calendar)
            }
        }
        .settingsPage()
    }
}

struct ShelfSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Keep dropped files on a shelf", isOn: $settings.showShelf)
            } footer: {
                Text("Drag files to the notch to keep them at hand. Off, Meniscus doesn't watch file drags at all; files already on the shelf come back when you turn it on again.")
                    .foregroundStyle(.secondary)
            }
        }
        .settingsPage()
    }
}

/// Explains, in Settings, whether what's playing can be shown and why not.
private struct NowPlayingStatus: View {
    let availability: NowPlayingService.Availability

    var body: some View {
        switch availability {
        case .off:
            Text("Shows what any app is playing, with its artwork and controls.")
                .foregroundStyle(.secondary)
        case .checking:
            Text("Checking…")
                .foregroundStyle(.secondary)
        case .available:
            Text("Shows what any app is playing, with its artwork and controls. Click the app's icon to switch to it.")
                .foregroundStyle(.secondary)
        case .unavailable(let reason):
            Label(reason.explanation, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.secondary)
        }
    }
}

/// Licenses of bundled third-party code, shipped in Contents/Resources/Acknowledgements.
enum Acknowledgements {
    static func open(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Acknowledgements") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Tools for tuning the island on a real screen. Visible in every build while the app is pre-1.0.
struct DeveloperSettingsView: View {
    @Bindable var settings: AppSettings
    var copyGeometry: () -> String?

    @State private var didCopy = false

    var body: some View {
        Form {
            Section("Tuning") {
                Toggle("Slow animations (×\(Int((1 / Motion.slowMotionFactor).rounded())))", isOn: $settings.slowAnimations)
                Toggle("Outline the computed notch in red", isOn: $settings.showGeometryOverlay)
                Toggle("Use a virtual notch on this screen", isOn: $settings.forceVirtualNotch)
                Button("Simulate Charging") { ActivityServices.shared.simulateCharging() }
                Button("Simulate Low Battery") { ActivityServices.shared.simulateLowBattery() }
                Button("Simulate Upcoming Meeting") { ActivityServices.shared.calendar.simulateStartingSoon() }
                Button("Simulate Bluetooth Device") { ActivityServices.shared.simulateBluetoothDevice() }
                Button("Simulate Device Low Battery") { ActivityServices.shared.simulateDeviceLowBattery() }
                Button("Bluetooth Diagnostics") { ActivityServices.shared.copyBluetoothDiagnostics() }
                    .help(Text("Copies every battery value each source reports, per device, to the clipboard."))
            }
            Section {
                Button {
                    guard let report = copyGeometry() else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    didCopy = true
                } label: {
                    didCopy ? Text("Copied") : Text("Copy Geometry Report")
                }
            } footer: {
                Text("Screen numbers behind the notch outline. Paste them into a bug report.")
                    .foregroundStyle(.secondary)
            }
        }
        .settingsPage()
    }
}

/// Which calendars the island shows, grouped by account.
private struct CalendarSelectionSection: View {
    @Bindable var settings: AppSettings
    let calendar: CalendarService

    var body: some View {
        if calendar.access == .granted {
            ForEach(CalendarGrouping.bySource(calendar.calendars), id: \.source) { group in
                Section(group.source.isEmpty ? String(localized: "Other") : group.source) {
                    ForEach(group.calendars) { info in
                        Toggle(isOn: binding(for: info.id)) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(info.color.map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue) } ?? .accentColor)
                                    .frame(width: 8, height: 8)
                                Text(info.title)
                            }
                        }
                    }
                }
            }
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding {
            !settings.hiddenCalendarIDs.contains(id)
        } set: { isShown in
            if isShown {
                settings.hiddenCalendarIDs.remove(id)
            } else {
                settings.hiddenCalendarIDs.insert(id)
            }
            calendar.refresh()
        }
    }
}
