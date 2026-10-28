import Foundation

// The external API's requests and rules, independent of how they arrive (socket, link,
// Shortcuts). Pure value types, unit tested. Design: docs/external-api.md.

/// The three states a notice or activity can be in. Callers choose the state, never the look.
nonisolated enum NoticeState: String, Equatable, Sendable, CaseIterable {
    case info, success, attention

    /// An unknown state from a newer caller shows as `info`.
    init(wire: String?) {
        self = wire.flatMap(NoticeState.init(rawValue:)) ?? .info
    }

    /// How long its banner shows, and how long it may wait behind more important notices.
    var bannerDuration: TimeInterval { self == .attention ? 5 : 3 }
    var bannerWait: TimeInterval { self == .attention ? 120 : 15 }
}

/// Where a request came from. Links are anonymous; the others are trusted.
nonisolated enum APIChannel: String, Equatable, Sendable {
    case link, cli, shortcuts, developer

    var isTrusted: Bool { self != .link }
}

/// What a click on a trusted banner does.
nonisolated enum APIAction: Equatable, Sendable {
    case openURL(URL)
    case openFile(URL)
}

nonisolated struct NoticeText: Equatable, Sendable {
    var title: String
    var subtitle: String?
}

nonisolated enum APIOperation: Equatable, Sendable {
    case notify(NoticeText, state: NoticeState, action: APIAction?)
    case start(id: String, NoticeText, state: NoticeState, timeout: TimeInterval?)
    case update(id: String, title: String?, subtitle: String?, state: NoticeState?)
    case end(id: String, title: String?, subtitle: String?, state: NoticeState, quiet: Bool)
    case status

    /// For event order: at equal times, `end` wins over `update`, and `update` over `start`.
    var rank: Int {
        switch self {
        case .start: 0
        case .update: 1
        case .end: 2
        case .notify, .status: 0
        }
    }

    var activityID: String? {
        switch self {
        case .start(let id, _, _, _), .update(let id, _, _, _), .end(let id, _, _, _, _): id
        case .notify, .status: nil
        }
    }
}

nonisolated struct APIRequest: Equatable, Sendable {
    var version: Int
    /// When the event happened, if the caller said (activity events are ordered by it).
    var at: Date?
    var operation: APIOperation
}

nonisolated enum APIError: Error, Equatable, Sendable {
    case invalid(String)
    case unsupportedVersion(Int)

    var message: String {
        switch self {
        case .invalid(let reason): reason
        case .unsupportedVersion(let version): "API version \(version) isn't supported; this Meniscus supports \(APILimits.versions.map(String.init).joined(separator: ", "))"
        }
    }
}

nonisolated enum APILimits {
    static let versions = [1]
    static let titleLength = 60
    static let subtitleLength = 80
    static let idLength = 128
    static let defaultTimeout: TimeInterval = 30 * 60
    static let timeoutRange: ClosedRange<TimeInterval> = 60...(2 * 60 * 60)
    /// A socket message is one line of at most this many bytes.
    static let messageSize = 16 * 1024

    /// Control characters removed, cut to `limit` with an ellipsis.
    static func clean(_ text: String, limit: Int) -> String {
        let visible = String(String.UnicodeScalarView(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard visible.count > limit else { return visible }
        return String(visible.prefix(limit - 1)) + "…"
    }
}

extension APIRequest {
    /// Decodes one socket message (a JSON object). Unknown fields are ignored; an unknown state
    /// is `info`; an unknown action is dropped.
    static func decode(_ object: [String: Any], trusted: Bool) throws(APIError) -> APIRequest {
        let version = (object["v"] as? NSNumber)?.intValue ?? 1
        guard APILimits.versions.contains(version) else { throw .unsupportedVersion(version) }
        let at = (object["at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        let title = (object["title"] as? String).map { APILimits.clean($0, limit: APILimits.titleLength) }.flatMap { $0.isEmpty ? nil : $0 }
        let subtitle = (object["subtitle"] as? String).map { APILimits.clean($0, limit: APILimits.subtitleLength) }.flatMap { $0.isEmpty ? nil : $0 }
        let stateWire = object["state"] as? String

        func id() throws(APIError) -> String {
            guard let raw = object["id"] as? String else { throw .invalid("id is required") }
            let id = APILimits.clean(raw, limit: Int.max)
            guard !id.isEmpty, id.count <= APILimits.idLength else { throw .invalid("id must be 1 to \(APILimits.idLength) characters") }
            return id
        }

        let operation: APIOperation
        switch object["op"] as? String {
        case "notify":
            guard let title else { throw .invalid("title is required") }
            let action = trusted ? (object["open"] as? String).flatMap(Self.action(from:)) : nil
            operation = .notify(NoticeText(title: title, subtitle: subtitle), state: NoticeState(wire: stateWire), action: action)
        case "start":
            guard let title else { throw .invalid("title is required") }
            let timeout = (object["timeout"] as? NSNumber).map {
                min(max($0.doubleValue, APILimits.timeoutRange.lowerBound), APILimits.timeoutRange.upperBound)
            }
            operation = .start(id: try id(), NoticeText(title: title, subtitle: subtitle), state: NoticeState(wire: stateWire), timeout: timeout)
        case "update":
            operation = .update(id: try id(), title: title, subtitle: subtitle, state: stateWire.map { NoticeState(wire: $0) })
        case "end":
            let state = stateWire.map { NoticeState(wire: $0) } ?? .success
            operation = .end(id: try id(), title: title, subtitle: subtitle, state: state, quiet: object["quiet"] as? Bool ?? false)
        case "status":
            operation = .status
        default:
            throw .invalid("op must be notify, start, update, end or status")
        }
        return APIRequest(version: version, at: at, operation: operation)
    }

    /// `https` links open in the browser; absolute paths and file URLs open in their app. Anything
    /// else is dropped.
    static func action(from value: String) -> APIAction? {
        if value.hasPrefix("/") { return .openFile(URL(filePath: value)) }
        guard let url = URL(string: value) else { return nil }
        switch url.scheme?.lowercased() {
        case "https": return .openURL(url)
        case "file": return .openFile(url)
        default: return nil
        }
    }

    /// `meniscus://v1/notify?title=…&subtitle=…&state=…`. Links only `notify`, never act on a click.
    static func link(_ url: URL) throws(APIError) -> APIRequest {
        guard url.scheme?.lowercased() == "meniscus" else { throw .invalid("not a meniscus link") }
        guard let host = url.host(), host.hasPrefix("v"), let version = Int(host.dropFirst()) else {
            throw .invalid("links start with meniscus://v1/")
        }
        guard url.path() == "/notify" else { throw .invalid("links can only notify") }
        var object: [String: Any] = ["v": version, "op": "notify"]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            if ["title", "subtitle", "state"].contains(item.name), let value = item.value { object[item.name] = value }
        }
        return try decode(object, trusted: false)
    }
}

/// Puts asynchronous events back in order: for each source and id, an event older than the last
/// one applied is ignored, so a late `start` can't revive an activity already ended.
nonisolated struct EventOrder: Equatable, Sendable {
    static let endedMemory: TimeInterval = 10 * 60
    static let endedLimit = 1000

    private struct Entry: Equatable, Sendable {
        var at: Date
        var rank: Int
        var endedAt: Date?
    }

    private var entries: [String: [String: Entry]] = [:]

    /// Whether to apply this event; records it if so.
    mutating func accept(source: String, id: String, at: Date, rank: Int, now: Date) -> Bool {
        prune(source: source, now: now)
        if let last = entries[source]?[id], (at, rank) <= (last.at, last.rank) { return false }
        entries[source, default: [:]][id] = Entry(at: at, rank: rank, endedAt: rank == 2 ? now : nil)
        return true
    }

    /// An activity that timed out counts as ended now: late events for it are ignored too.
    mutating func markEnded(source: String, id: String, now: Date) {
        entries[source, default: [:]][id] = Entry(at: now, rank: 2, endedAt: now)
    }

    private mutating func prune(source: String, now: Date) {
        guard var ids = entries[source] else { return }
        ids = ids.filter { $0.value.endedAt.map { now.timeIntervalSince($0) < Self.endedMemory } ?? true }
        let ended = ids.filter { $0.value.endedAt != nil }
        if ended.count > Self.endedLimit {
            for (id, _) in ended.sorted(by: { $0.value.endedAt! < $1.value.endedAt! }).prefix(ended.count - Self.endedLimit) {
                ids[id] = nil
            }
        }
        entries[source] = ids
    }
}

/// Sliding-window rate limits and deduplication, per key (a source, or one key for links).
nonisolated struct NoticeLimiter: Equatable, Sendable {
    struct Limit: Equatable, Sendable {
        var count: Int
        var window: TimeInterval
    }

    static let link = [Limit(count: 3, window: 10), Limit(count: 20, window: 3600)]
    static let trusted = [Limit(count: 10, window: 60), Limit(count: 100, window: 3600)]
    static let duplicateWindow: TimeInterval = 60

    private var shown: [String: [Date]] = [:]
    private var recent: [String: Date] = [:]

    /// Whether a banner may show for `key` now; records it if so. Repeats of the same text and
    /// state within a minute count as one.
    mutating func allow(key: String, limits: [Limit], fingerprint: String, now: Date) -> Bool {
        let longest = limits.map(\.window).max() ?? 0
        recent = recent.filter { now.timeIntervalSince($0.value) < Self.duplicateWindow }
        let duplicateKey = key + "\u{1F}" + fingerprint
        guard recent[duplicateKey] == nil else { return false }
        var times = (shown[key] ?? []).filter { now.timeIntervalSince($0) < longest }
        for limit in limits where times.filter({ now.timeIntervalSince($0) < limit.window }).count >= limit.count {
            shown[key] = times
            return false
        }
        times.append(now)
        shown[key] = times
        recent[duplicateKey] = now
        return true
    }
}

nonisolated enum EndRule {
    /// Whether ending an activity shows a banner: a short task stays silent unless something needs
    /// attention; after a visible indicator, every end says so.
    static func showsBanner(state: NoticeState, indicatorWasVisible: Bool, quiet: Bool) -> Bool {
        guard !quiet else { return false }
        return state == .attention || indicatorWasVisible
    }

    /// End banners of one source that show one after another before the rest collapse into one.
    static let bannersInARow = 3
}
