import Foundation

/// What the system's Now Playing reports, for whichever app is playing: a music app, a browser
/// tab, a podcast player. Built from the adapter's JSON; never names a specific service.
nonisolated struct NowPlayingInfo: Equatable, Sendable {
    var processIdentifier: Int32?
    var bundleIdentifier: String?
    /// Set when the player is a helper process, for example a browser's media process.
    var parentBundleIdentifier: String?
    var title: String
    var artist: String?
    var album: String?
    var isPlaying: Bool
    var duration: TimeInterval?
    /// Elapsed time at `timestamp`.
    var elapsed: TimeInterval?
    var timestamp: Date?
    var playbackRate: Double?

    /// The app to show and open: the parent app for helper processes.
    var sourceBundleIdentifier: String? { parentBundleIdentifier ?? bundleIdentifier }

    /// Extrapolates the position from the last report, so the progress bar moves without new
    /// messages from the system.
    func elapsed(at date: Date) -> TimeInterval? {
        guard var value = elapsed else { return nil }
        if isPlaying, let timestamp {
            value += max(date.timeIntervalSince(timestamp), 0) * (playbackRate ?? 1)
        }
        if let duration, duration > 0 { value = min(value, duration) }
        return max(value, 0)
    }

    func progress(at date: Date) -> Double? {
        guard let duration, duration > 0, let elapsed = elapsed(at: date) else { return nil }
        return min(max(elapsed / duration, 0), 1)
    }
}

/// A JSON value from the adapter, Sendable so messages can be decoded off the main actor.
nonisolated enum AdapterValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)

    var string: String? {
        switch self {
        case .string(let value): value
        default: nil
        }
    }
    var number: Double? {
        switch self {
        case .number(let value): value
        default: nil
        }
    }
    var bool: Bool? {
        switch self {
        case .bool(let value): value
        case .number(let value): value != 0
        case .string: nil
        }
    }
}

/// One line of `mediaremote-adapter stream --micros`:
/// `{"type":"data","diff":false,"payload":{…}}`. A diff only carries changed keys; `null`
/// removes a key; an empty full payload means nothing is playing.
nonisolated struct AdapterMessage: Equatable, Sendable {
    nonisolated enum ArtworkChange: Equatable, Sendable {
        case unchanged
        case removed
        case set(Data)
    }

    var isDiff: Bool
    var values: [String: AdapterValue]
    var removedKeys: Set<String>
    var artwork: ArtworkChange

    /// Decodes one output line; returns `nil` for anything that isn't a data message. Runs off
    /// the main actor because artwork arrives as several hundred kilobytes of base64.
    static func decode(_ line: Data) -> AdapterMessage? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "data",
              let payload = object["payload"] as? [String: Any]
        else { return nil }
        let isDiff = (object["diff"] as? Bool) ?? false

        var values: [String: AdapterValue] = [:]
        var removed = Set<String>()
        var artwork: ArtworkChange = isDiff ? .unchanged : .removed
        for (key, raw) in payload {
            if key == Keys.artworkData {
                if let base64 = raw as? String, let data = Data(base64Encoded: base64) {
                    artwork = .set(data)
                } else {
                    artwork = .removed
                }
                continue
            }
            switch raw {
            case is NSNull:
                removed.insert(key)
            case let number as NSNumber:
                values[key] = CFGetTypeID(number) == CFBooleanGetTypeID()
                    ? .bool(number.boolValue)
                    : .number(number.doubleValue)
            case let string as String:
                values[key] = .string(string)
            default:
                continue
            }
        }
        return AdapterMessage(isDiff: isDiff, values: values, removedKeys: removed, artwork: artwork)
    }

    nonisolated enum Keys {
        static let processIdentifier = "processIdentifier"
        static let bundleIdentifier = "bundleIdentifier"
        static let parentBundleIdentifier = "parentApplicationBundleIdentifier"
        static let playing = "playing"
        static let title = "title"
        static let artist = "artist"
        static let album = "album"
        static let durationMicros = "durationMicros"
        static let elapsedTimeMicros = "elapsedTimeMicros"
        static let timestampEpochMicros = "timestampEpochMicros"
        static let playbackRate = "playbackRate"
        static let artworkData = "artworkData"
    }
}

/// The accumulated stream: applies full messages and diffs, and derives `NowPlayingInfo`.
nonisolated struct NowPlayingStreamState: Equatable, Sendable {
    private(set) var values: [String: AdapterValue] = [:]
    private(set) var artworkData: Data?

    mutating func apply(_ message: AdapterMessage) {
        if !message.isDiff { values.removeAll() }
        for key in message.removedKeys { values[key] = nil }
        values.merge(message.values) { _, new in new }
        switch message.artwork {
        case .unchanged: break
        case .removed: artworkData = nil
        case .set(let data): artworkData = data
        }
    }

    /// `nil` when nothing is playing or the player gave no title.
    var info: NowPlayingInfo? {
        typealias Keys = AdapterMessage.Keys
        guard let title = values[Keys.title]?.string, !title.isEmpty else { return nil }
        func seconds(_ key: String) -> TimeInterval? { values[key]?.number.map { $0 / 1_000_000 } }
        return NowPlayingInfo(
            processIdentifier: values[Keys.processIdentifier]?.number.map { Int32($0) },
            bundleIdentifier: values[Keys.bundleIdentifier]?.string,
            parentBundleIdentifier: values[Keys.parentBundleIdentifier]?.string,
            title: title,
            artist: values[Keys.artist]?.string.flatMap { $0.isEmpty ? nil : $0 },
            album: values[Keys.album]?.string.flatMap { $0.isEmpty ? nil : $0 },
            isPlaying: values[Keys.playing]?.bool ?? false,
            duration: seconds(Keys.durationMicros),
            elapsed: seconds(Keys.elapsedTimeMicros),
            timestamp: seconds(Keys.timestampEpochMicros).map { Date(timeIntervalSince1970: $0) },
            playbackRate: values[Keys.playbackRate]?.number
        )
    }
}
