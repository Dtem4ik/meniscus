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
        ])
        displayPreference = defaults.string(forKey: SettingsKey.displayPreference)
            .flatMap(DisplayPreference.init) ?? .notched
        expandOnHover = defaults.bool(forKey: SettingsKey.expandOnHover)
        hapticsEnabled = defaults.bool(forKey: SettingsKey.hapticsEnabled)
        showCalendar = defaults.bool(forKey: SettingsKey.showCalendar)
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: SettingsKey.hiddenCalendarIDs) ?? [])
        showNowPlaying = defaults.bool(forKey: SettingsKey.showNowPlaying)
        slowAnimations = defaults.bool(forKey: SettingsKey.slowAnimations)
        showGeometryOverlay = defaults.bool(forKey: SettingsKey.showGeometryOverlay)
        forceVirtualNotch = defaults.bool(forKey: SettingsKey.forceVirtualNotch)
    }
}
