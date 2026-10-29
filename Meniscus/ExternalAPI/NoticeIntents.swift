import AppIntents
import Foundation

// Shortcuts actions for the external API. They run inside Meniscus, so only Shortcuts, Siri and
// Spotlight on this Mac can call them; the source shown is Shortcuts.

nonisolated enum NoticeStateOption: String, AppEnum, CaseIterable, Sendable {
    case info, success, attention

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "State" }

    static var caseDisplayRepresentations: [NoticeStateOption: DisplayRepresentation] {
        [
            .info: DisplayRepresentation(title: "Info", image: .init(systemName: "info.circle")),
            .success: DisplayRepresentation(title: "Success", image: .init(systemName: "checkmark.circle")),
            .attention: DisplayRepresentation(title: "Attention", image: .init(systemName: "exclamationmark.circle")),
        ]
    }

    var state: NoticeState { NoticeState(rawValue: rawValue) ?? .info }
}

/// Applies a request from Shortcuts. Text goes through the same cleaning as every channel.
nonisolated private func shortcutsRequest(_ object: [String: Any]) async throws -> some IntentResult {
    let request: APIRequest
    do {
        request = try APIRequest.decode(object.merging(["v": 1]) { current, _ in current }, trusted: true)
    } catch {
        throw NoticeIntentError.invalid(error.message)
    }
    await MainActor.run {
        ActivityServices.shared.external.handle(request, from: .shortcuts)
    }
    return .result()
}

nonisolated enum NoticeIntentError: Error, CustomLocalizedStringResourceConvertible {
    case invalid(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalid(let reason): "\(reason)"
        }
    }
}

struct ShowNoticeIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Notice in Notch"
    static let description: IntentDescription? = "Shows a short notice in the notch for a few seconds."

    @Parameter(title: "Title") var noticeTitle: String
    @Parameter(title: "Subtitle") var subtitle: String?
    @Parameter(title: "State", default: .info) var state: NoticeStateOption
    @Parameter(title: "Open on Click") var link: URL?

    func perform() async throws -> some IntentResult {
        var object: [String: Any] = ["op": "notify", "title": noticeTitle, "state": state.rawValue]
        if let subtitle { object["subtitle"] = subtitle }
        if let link { object["open"] = link.absoluteString }
        return try await shortcutsRequest(object)
    }
}

struct StartNotchActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Notch Activity"
    static let description: IntentDescription? = "Shows that a task is running, once it has run for a while. End it with End Notch Activity and the same ID."

    @Parameter(title: "ID") var activityID: String
    @Parameter(title: "Title") var activityTitle: String
    @Parameter(title: "Subtitle") var subtitle: String?

    func perform() async throws -> some IntentResult {
        var object: [String: Any] = ["op": "start", "id": activityID, "title": activityTitle]
        if let subtitle { object["subtitle"] = subtitle }
        return try await shortcutsRequest(object)
    }
}

struct UpdateNotchActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "Update Notch Activity"

    @Parameter(title: "ID") var activityID: String
    @Parameter(title: "Title") var activityTitle: String?
    @Parameter(title: "Subtitle") var subtitle: String?
    @Parameter(title: "State") var state: NoticeStateOption?

    func perform() async throws -> some IntentResult {
        var object: [String: Any] = ["op": "update", "id": activityID]
        if let activityTitle { object["title"] = activityTitle }
        if let subtitle { object["subtitle"] = subtitle }
        if let state { object["state"] = state.rawValue }
        return try await shortcutsRequest(object)
    }
}

struct EndNotchActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "End Notch Activity"

    @Parameter(title: "ID") var activityID: String
    @Parameter(title: "State", default: .success) var state: NoticeStateOption
    @Parameter(title: "Title") var activityTitle: String?
    @Parameter(title: "Subtitle") var subtitle: String?
    @Parameter(title: "Quietly", default: false) var quiet: Bool

    func perform() async throws -> some IntentResult {
        var object: [String: Any] = ["op": "end", "id": activityID, "state": state.rawValue, "quiet": quiet]
        if let activityTitle { object["title"] = activityTitle }
        if let subtitle { object["subtitle"] = subtitle }
        return try await shortcutsRequest(object)
    }
}

struct GetNotchAPIVersionIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Notch API Version"

    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        .result(value: APILimits.versions.max() ?? 1)
    }
}
