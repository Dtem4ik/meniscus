import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    @AppStorage(SettingsKey.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some View {
        Form {
            Section {
                Toggle("Open when the pointer rests on the notch", isOn: $settings.expandOnHover)
                Toggle("Haptic feedback on the trackpad", isOn: $settings.hapticsEnabled)
            }
            Section {
                Toggle("Show the next calendar event", isOn: $settings.showCalendar)
                    .onChange(of: settings.showCalendar) { _, isOn in
                        let calendar = ActivityServices.shared.calendar
                        if isOn { calendar.start() } else { calendar.stop() }
                    }
            } footer: {
                Text("Calendar access is requested the first time you open the island with this on.")
                    .foregroundStyle(.secondary)
            }
            if settings.showCalendar {
                CalendarSelectionSection(settings: settings, calendar: ActivityServices.shared.calendar)
            }
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
                Picker("Show on", selection: $settings.displayPreference) {
                    ForEach(DisplayPreference.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show icon in the menu bar", isOn: $showMenuBarIcon)
            } footer: {
                if !showMenuBarIcon {
                    Text("To open Settings, open Meniscus again from the Applications folder or Spotlight.")
                        .foregroundStyle(.secondary)
                }
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
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
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
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
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
