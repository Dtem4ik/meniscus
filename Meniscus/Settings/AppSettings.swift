import Foundation
import Observation

/// How the expanded island turns from the black notch into Liquid Glass.
/// Three experiments to compare on a real screen; pick one in the Developer menu.
nonisolated enum IslandStyle: String, CaseIterable, Identifiable, Sendable {
    /// The whole island stays black like Dynamic Island; only controls inside are glass.
    case obsidian
    /// A black band around the notch flows into a glass panel below it.
    case meniscus
    /// The notch stays as is; a separate glass drop flows out from under it.
    case droplet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .obsidian: "A · Obsidian"
        case .meniscus: "B · Meniscus"
        case .droplet: "C · Droplet"
        }
    }
}

/// Which display shows the island.
nonisolated enum DisplayPreference: String, CaseIterable, Identifiable, Sendable {
    /// The screen with a camera housing, falling back to the built-in, then the main display.
    case notched
    /// The display that has the menu bar (System Settings → Displays → Main display).
    case main

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notched: "Built-in display with notch"
        case .main: "Main display"
        }
    }
}

nonisolated enum SettingsKey {
    static let showMenuBarIcon = "showMenuBarIcon"
    static let islandStyle = "islandStyle"
    static let displayPreference = "displayPreference"
    static let expandOnHover = "expandOnHover"
    static let hapticsEnabled = "hapticsEnabled"
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

    var islandStyle: IslandStyle {
        didSet { defaults.set(islandStyle.rawValue, forKey: SettingsKey.islandStyle) }
    }
    var displayPreference: DisplayPreference {
        didSet { defaults.set(displayPreference.rawValue, forKey: SettingsKey.displayPreference) }
    }
    var expandOnHover: Bool {
        didSet { defaults.set(expandOnHover, forKey: SettingsKey.expandOnHover) }
    }
    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: SettingsKey.hapticsEnabled) }
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
        ])
        islandStyle = defaults.string(forKey: SettingsKey.islandStyle).flatMap(IslandStyle.init) ?? .meniscus
        displayPreference = defaults.string(forKey: SettingsKey.displayPreference)
            .flatMap(DisplayPreference.init) ?? .notched
        expandOnHover = defaults.bool(forKey: SettingsKey.expandOnHover)
        hapticsEnabled = defaults.bool(forKey: SettingsKey.hapticsEnabled)
        slowAnimations = defaults.bool(forKey: SettingsKey.slowAnimations)
        showGeometryOverlay = defaults.bool(forKey: SettingsKey.showGeometryOverlay)
        forceVirtualNotch = defaults.bool(forKey: SettingsKey.forceVirtualNotch)
    }
}
