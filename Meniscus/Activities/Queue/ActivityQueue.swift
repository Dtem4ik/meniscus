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
        /// A new track started playing.
        case trackChange
        /// A notice from another app, script or shortcut.
        case externalBanner
        /// Another app's running tasks, one per source.
        case externalActivity

        /// Shown as a mini banner below the notch rather than on its sides.
        var isBanner: Bool {
            switch self {
            case .bluetoothDevice, .trackChange, .externalBanner: true
            default: false
            }
        }
    }

    /// Higher wins. Short activities outrank music; when they end, music comes back. The order
    /// is described in docs/external-api.md (section 6).
    nonisolated enum Priority: Int, Comparable, Sendable {
        /// Reminders that can wait, like files on the shelf.
        case background = 0
        /// A running external task's indicator, behind its own banners.
        case externalActivity = 44
        /// External `info` and `success` notices.
        case external = 45
        /// Lasting activities, like music.
        case ongoing = 50
        /// Music's own short notices, like a track change.
        case confirmation = 55
        case charging = 60
        /// External notices in the `attention` state.
        case externalAttention = 65
        /// Direct feedback to the user's own action: keyboard layout, "Saved", a device the user
        /// just connected.
        case directFeedback = 70
        case deviceLowBattery = 78
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
    /// Set for notices whose time starts when they are first shown, not when posted (external
    /// banners): the queue sets `expiresAt` then. Until shown, `showBy` limits the wait.
    var displayDuration: TimeInterval? = nil
    /// A notice never shown by this date is dropped.
    var showBy: Date? = nil
    /// Notices that wait in line show oldest first among equal priorities (banners of one
    /// source, one after another); everything else shows newest first.
    var waitsInLine = false

    /// Waiting for its first showing: its clock hasn't started.
    var isWaiting: Bool { displayDuration != nil && expiresAt == nil }

    func isExpired(at date: Date) -> Bool {
        if let expiresAt { return expiresAt <= date }
        if isWaiting, let showBy { return showBy <= date }
        return false
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

    /// The activity to show: highest priority, then most recently updated (oldest first for
    /// notices that wait in line).
    func current(at date: Date) -> LiveActivity? {
        activities
            .filter { !$0.isExpired(at: date) }
            .max { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                if lhs.waitsInLine, rhs.waitsInLine { return lhs.updatedAt > rhs.updatedAt }
                return lhs.updatedAt < rhs.updatedAt
            }
    }

    /// Starts the clock of a notice that waited: it is shown from `date`.
    mutating func startClock(of id: LiveActivity.ID, at date: Date) {
        guard let index = activities.firstIndex(where: { $0.id == id }),
              activities[index].isWaiting, let duration = activities[index].displayDuration else { return }
        activities[index].expiresAt = date.addingTimeInterval(duration)
    }

    /// The next moment `current(at:)` can change by itself. Schedule one wake-up for it
    /// instead of polling.
    func nextExpiration(after date: Date) -> Date? {
        activities.compactMap { $0.expiresAt ?? ($0.isWaiting ? $0.showBy : nil) }.filter { $0 > date }.min()
    }

    func contains(id: LiveActivity.ID) -> Bool {
        activities.contains { $0.id == id }
    }
}
