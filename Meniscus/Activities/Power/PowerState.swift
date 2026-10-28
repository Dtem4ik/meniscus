import Foundation

/// A snapshot of the internal battery.
nonisolated struct PowerState: Equatable, Sendable {
    /// 0...100.
    var level: Int
    /// Connected to a charger (it may be full or paused and not actually charging).
    var isOnACPower: Bool
    var isCharging: Bool
    var isCharged: Bool

    /// Reads one power source description from `IOPSGetPowerSourceDescription`.
    /// Returns `nil` for anything that isn't the internal battery (UPS, accessories).
    init?(powerSourceDescription description: [String: Any]) {
        guard description[Keys.type] as? String == Keys.internalBattery,
              let current = description[Keys.currentCapacity] as? Int,
              let max = description[Keys.maxCapacity] as? Int, max > 0
        else { return nil }
        level = Swift.min(Swift.max(Int((Double(current) / Double(max) * 100).rounded()), 0), 100)
        isOnACPower = description[Keys.powerSourceState] as? String == Keys.acPower
        isCharging = description[Keys.isCharging] as? Bool ?? false
        isCharged = description[Keys.isCharged] as? Bool ?? false
    }

    init(level: Int, isOnACPower: Bool, isCharging: Bool, isCharged: Bool = false) {
        self.level = level
        self.isOnACPower = isOnACPower
        self.isCharging = isCharging
        self.isCharged = isCharged
    }

    /// Keys from IOKit's IOPSKeys.h.
    private nonisolated enum Keys {
        static let type = "Type"
        static let internalBattery = "InternalBattery"
        static let currentCapacity = "Current Capacity"
        static let maxCapacity = "Max Capacity"
        static let powerSourceState = "Power Source State"
        static let acPower = "AC Power"
        static let isCharging = "Is Charging"
        static let isCharged = "Is Charged"
    }
}

/// A change worth a live activity.
nonisolated enum PowerEvent: Equatable, Sendable {
    case connected(level: Int)
    case disconnected(level: Int)
    case fullyCharged
}

nonisolated enum PowerEventDetector {
    /// Compares two consecutive snapshots. The first snapshot after launch (`previous == nil`)
    /// never produces an event, so launching on a charger doesn't show the charging animation.
    static func event(from previous: PowerState?, to current: PowerState) -> PowerEvent? {
        guard let previous else { return nil }
        if !previous.isOnACPower && current.isOnACPower { return .connected(level: current.level) }
        if previous.isOnACPower && !current.isOnACPower { return .disconnected(level: current.level) }
        if current.isOnACPower && !previous.isCharged && current.isCharged { return .fullyCharged }
        return nil
    }
}

/// Warns once per discharge at each threshold: 20% and 10%. Connecting a charger starts over.
nonisolated struct LowBatteryWarnings: Equatable, Sendable {
    static let thresholds = [20, 10]

    private(set) var warned: Set<Int> = []

    /// The threshold to warn about for this snapshot, if any. Falling past several thresholds at
    /// once (say, waking from sleep at 8%) warns only for the lowest.
    mutating func check(_ state: PowerState) -> Int? {
        guard !state.isOnACPower else {
            warned.removeAll()
            return nil
        }
        let reached = Self.thresholds.filter { state.level <= $0 }
        guard let lowest = reached.min(), !warned.contains(lowest) else { return nil }
        warned.formUnion(reached)
        return lowest
    }
}
