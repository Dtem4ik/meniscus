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
    }

    /// Higher wins. Transient alerts outrank ongoing activities.
    nonisolated enum Priority: Int, Comparable, Sendable {
        case background = 0
        case ongoing = 50
        case alert = 100

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
