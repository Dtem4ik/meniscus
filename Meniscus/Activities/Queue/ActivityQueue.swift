import Foundation

/// A live activity the collapsed notch can show, like charging or now playing.
nonisolated struct LiveActivity: Identifiable, Equatable, Sendable {
    nonisolated enum Kind: String, Equatable, Sendable {
        case charging
        case nowPlaying
        /// Files are waiting on the shelf.
        case shelf
        /// A file is being dragged: the notch says it takes drops.
        case dropHint
        /// A calendar event starts in a few minutes.
        case meeting
        /// The battery fell to a warning threshold.
        case lowBattery
        /// The keyboard input source changed.
        case inputSource
        /// A quick capture was saved.
        case captureSaved
        /// A third-party Bluetooth device connected or disconnected.
        case bluetoothDevice
        /// A third-party Bluetooth device's battery fell to a warning threshold.
        case deviceLowBattery
    }

    /// Higher wins. Short activities outrank music; when they end, music comes back.
    nonisolated enum Priority: Int, Comparable, Sendable {
        /// Reminders that can wait, like files on the shelf.
        case background = 0
        /// Lasting activities, like music.
        case ongoing = 50
        /// Short confirmations, like a saved quick capture.
        case confirmation = 55
        case inputSource = 60
        case charging = 70
        case deviceLowBattery = 75
        case lowBattery = 80
        case meeting = 90
        /// The user is doing something with the notch right now, like dragging a file to it.
        case interaction = 100

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// One activity per id; posting the same id again updates it in place.
    var id: String
    var kind: Kind
    var priority: Priority
    /// When the activity was posted or last updated; breaks priority ties (newest wins).
    var updatedAt: Date
    /// Transient activities disappear on their own; `nil` means until removed.
    var expiresAt: Date?

    func isExpired(at date: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= date
    }
}

/// Decides which live activity the collapsed notch shows. Pure value type: time is passed in,
/// so the rules are unit tested without clocks or timers.
nonisolated struct ActivityQueue: Equatable, Sendable {
    private(set) var activities: [LiveActivity] = []

    /// Adds the activity, or replaces the one with the same id.
    mutating func post(_ activity: LiveActivity) {
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index] = activity
        } else {
            activities.append(activity)
        }
    }

    mutating func remove(id: LiveActivity.ID) {
        activities.removeAll { $0.id == id }
    }

    mutating func removeExpired(at date: Date) {
        activities.removeAll { $0.isExpired(at: date) }
    }

    /// The activity to show: highest priority, then most recently updated.
    func current(at date: Date) -> LiveActivity? {
        activities
            .filter { !$0.isExpired(at: date) }
            .max { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                return lhs.updatedAt < rhs.updatedAt
            }
    }

    /// The next moment `current(at:)` can change by itself. Schedule one wake-up for it
    /// instead of polling.
    func nextExpiration(after date: Date) -> Date? {
        activities.compactMap(\.expiresAt).filter { $0 > date }.min()
    }
}
