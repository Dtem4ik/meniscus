import Foundation
import Observation

/// Holds the live activities and publishes the one to show. Wakes up only when the current
/// activity can change: when something is posted or removed, and when the next transient
/// activity expires.
@Observable
final class ActivityCenter {
    private(set) var current: LiveActivity?

    @ObservationIgnored private var queue = ActivityQueue()
    @ObservationIgnored private var expirationTask: Task<Void, Never>?
    @ObservationIgnored private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func post(_ activity: LiveActivity) {
        queue.post(activity)
        update()
    }

    /// Posts an activity that disappears after `duration`.
    func postTransient(id: String, kind: LiveActivity.Kind, duration: TimeInterval, priority: LiveActivity.Priority = .alert) {
        let date = now()
        post(LiveActivity(id: id, kind: kind, priority: priority, updatedAt: date, expiresAt: date.addingTimeInterval(duration)))
    }

    func remove(id: LiveActivity.ID) {
        queue.remove(id: id)
        update()
    }

    private func update() {
        let date = now()
        queue.removeExpired(at: date)
        let next = queue.current(at: date)
        if next != current { current = next }

        expirationTask?.cancel()
        guard let expiration = queue.nextExpiration(after: date) else { return }
        let delay = expiration.timeIntervalSince(date)
        expirationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.update()
        }
    }
}
