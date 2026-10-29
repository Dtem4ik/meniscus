import Foundation
import Observation

/// Which display shows the island.
nonisolated enum DisplayPreference: String, CaseIterable, Identifiable, Sendable {
    /// The screen with a camera housing, falling back to the built-in, then the main display.
    case notched
    /// The display that has the menu bar (System Settings → Displays → Main display).
    case main

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notched: String(localized: "Built-in display with notch")
        case .main: String(localized: "Main display")
        }
    }
}

nonisolated enum SettingsKey {
    static let showMenuBarIcon = "showMenuBarIcon"
    static let displayPreference = "displayPreference"
    static let expandOnHover = "expandOnHover"
    static let hapticsEnabled = "hapticsEnabled"
    static let showCalendar = "showCalendar"
    static let hiddenCalendarIDs = "calendar.hiddenCalendarIDs"
    static let showNowPlaying = "showNowPlaying"
    static let showShelf = "showShelf"
    static let showMeetingReminders = "activities.meetings"
    static let showLowBattery = "activities.lowBattery"
    static let showCharging = "activities.charging"
    static let showInputSource = "activities.inputSource"
    static let showCaptureConfirmation = "activities.captureSaved"
    static let showBluetoothDevices = "activities.bluetoothDevices"
    static let showDeviceLowBattery = "activities.deviceLowBattery"
    static let showTrackChange = "activities.trackChange"
    static let externalCLI = "external.cli"
    static let externalLinks = "external.links"
    static let externalIndicatorDelay = "external.indicatorDelay"
    static let externalSources = "external.sources"
    static let hideFromScreenCapture = "hideFromScreenCapture"
    static let slowAnimations = "developer.slowAnimations"
    static let showGeometryOverlay = "developer.showGeometryOverlay"
    static let forceVirtualNotch = "developer.forceVirtualNotch"
}

/// User preferences, persisted in `UserDefaults`. The menu bar icon toggle uses `@AppStorage`
/// with `SettingsKey.showMenuBarIcon` directly because `MenuBarExtra` needs a binding at app level.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults: UserDefaults

    var displayPreference: DisplayPreference {
        didSet { defaults.set(displayPreference.rawValue, forKey: SettingsKey.displayPreference) }
    }
    var expandOnHover: Bool {
        didSet { defaults.set(expandOnHover, forKey: SettingsKey.expandOnHover) }
    }
    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: SettingsKey.hapticsEnabled) }
    }
    var showCalendar: Bool {
        didSet { defaults.set(showCalendar, forKey: SettingsKey.showCalendar) }
    }
    /// Calendars not to show in the island. Stored as hidden, so new calendars appear by default.
    var hiddenCalendarIDs: Set<String> {
        didSet { defaults.set(Array(hiddenCalendarIDs).sorted(), forKey: SettingsKey.hiddenCalendarIDs) }
    }
    var showNowPlaying: Bool {
        didSet { defaults.set(showNowPlaying, forKey: SettingsKey.showNowPlaying) }
    }
    /// The file shelf: drop target, shelf and its notch indicator. Off, file drags aren't watched.
    var showShelf: Bool {
        didSet { defaults.set(showShelf, forKey: SettingsKey.showShelf) }
    }

    // Live activities, each with its own switch.
    var showMeetingReminders: Bool {
        didSet { defaults.set(showMeetingReminders, forKey: SettingsKey.showMeetingReminders) }
    }
    var showLowBattery: Bool {
        didSet { defaults.set(showLowBattery, forKey: SettingsKey.showLowBattery) }
    }
    var showCharging: Bool {
        didSet { defaults.set(showCharging, forKey: SettingsKey.showCharging) }
    }
    var showInputSource: Bool {
        didSet { defaults.set(showInputSource, forKey: SettingsKey.showInputSource) }
    }
    var showCaptureConfirmation: Bool {
        didSet { defaults.set(showCaptureConfirmation, forKey: SettingsKey.showCaptureConfirmation) }
    }
    var showBluetoothDevices: Bool {
        didSet { defaults.set(showBluetoothDevices, forKey: SettingsKey.showBluetoothDevices) }
    }
    var showDeviceLowBattery: Bool {
        didSet { defaults.set(showDeviceLowBattery, forKey: SettingsKey.showDeviceLowBattery) }
    }
    var showTrackChange: Bool {
        didSet { defaults.set(showTrackChange, forKey: SettingsKey.showTrackChange) }
    }
    /// The command line tool and Shortcuts may show notices.
    var externalCLI: Bool {
        didSet { defaults.set(externalCLI, forKey: SettingsKey.externalCLI) }
    }
    /// `meniscus://` links may show notices; off by default, since any web page can open one.
    var externalLinks: Bool {
        didSet { defaults.set(externalLinks, forKey: SettingsKey.externalLinks) }
    }
    /// How long an external task runs before its indicator appears, in seconds.
    var externalIndicatorDelay: Double {
        didSet { defaults.set(externalIndicatorDelay, forKey: SettingsKey.externalIndicatorDelay) }
    }
    /// Leaves the island out of screenshots, recordings and screen sharing, where the system
    /// honors it. macOS can't tell apps when the screen is being shared, so this is the way to
    /// keep live activities out of a presentation.
    var hideFromScreenCapture: Bool {
        didSet { defaults.set(hideFromScreenCapture, forKey: SettingsKey.hideFromScreenCapture) }
    }
    var slowAnimations: Bool {
        didSet { defaults.set(slowAnimations, forKey: SettingsKey.slowAnimations) }
    }
    var showGeometryOverlay: Bool {
        didSet { defaults.set(showGeometryOverlay, forKey: SettingsKey.showGeometryOverlay) }
    }
    var forceVirtualNotch: Bool {
        didSet { defaults.set(forceVirtualNotch, forKey: SettingsKey.forceVirtualNotch) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            SettingsKey.showMenuBarIcon: true,
            SettingsKey.expandOnHover: true,
            SettingsKey.hapticsEnabled: true,
            SettingsKey.showCalendar: true,
            SettingsKey.showNowPlaying: true,
            SettingsKey.showShelf: true,
            SettingsKey.showMeetingReminders: true,
            SettingsKey.showLowBattery: true,
            SettingsKey.showCharging: true,
            SettingsKey.showInputSource: true,
            SettingsKey.showCaptureConfirmation: true,
            SettingsKey.showBluetoothDevices: true,
            SettingsKey.showDeviceLowBattery: true,
            SettingsKey.showTrackChange: true,
            SettingsKey.externalCLI: true,
            SettingsKey.externalLinks: false,
            SettingsKey.externalIndicatorDelay: 10.0,
            SettingsKey.hideFromScreenCapture: true,
        ])
        displayPreference = defaults.string(forKey: SettingsKey.displayPreference)
            .flatMap(DisplayPreference.init) ?? .notched
        expandOnHover = defaults.bool(forKey: SettingsKey.expandOnHover)
        hapticsEnabled = defaults.bool(forKey: SettingsKey.hapticsEnabled)
        showCalendar = defaults.bool(forKey: SettingsKey.showCalendar)
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: SettingsKey.hiddenCalendarIDs) ?? [])
        showNowPlaying = defaults.bool(forKey: SettingsKey.showNowPlaying)
        showShelf = defaults.bool(forKey: SettingsKey.showShelf)
        showMeetingReminders = defaults.bool(forKey: SettingsKey.showMeetingReminders)
        showLowBattery = defaults.bool(forKey: SettingsKey.showLowBattery)
        showCharging = defaults.bool(forKey: SettingsKey.showCharging)
        showInputSource = defaults.bool(forKey: SettingsKey.showInputSource)
        showCaptureConfirmation = defaults.bool(forKey: SettingsKey.showCaptureConfirmation)
        showBluetoothDevices = defaults.bool(forKey: SettingsKey.showBluetoothDevices)
        showDeviceLowBattery = defaults.bool(forKey: SettingsKey.showDeviceLowBattery)
        showTrackChange = defaults.bool(forKey: SettingsKey.showTrackChange)
        externalCLI = defaults.bool(forKey: SettingsKey.externalCLI)
        externalLinks = defaults.bool(forKey: SettingsKey.externalLinks)
        externalIndicatorDelay = defaults.double(forKey: SettingsKey.externalIndicatorDelay)
        hideFromScreenCapture = defaults.bool(forKey: SettingsKey.hideFromScreenCapture)
        slowAnimations = defaults.bool(forKey: SettingsKey.slowAnimations)
        showGeometryOverlay = defaults.bool(forKey: SettingsKey.showGeometryOverlay)
        forceVirtualNotch = defaults.bool(forKey: SettingsKey.forceVirtualNotch)
    }
}
