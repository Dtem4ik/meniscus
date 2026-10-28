import Foundation

/// Turns Claude Code hook events into API calls. The `meniscus hook claude-code` command forwards
/// the hook's fields here; the mapping lives in the app so its texts follow the user's language.
/// docs/external-api.md, section 8.
nonisolated enum ClaudeCodeAdapter {
    /// What the CLI forwards from a hook's JSON input: no prompt, no answer text, no full paths.
    struct HookEvent: Equatable, Sendable {
        var event: String
        var sessionID: String
        /// The last part of the hook's `cwd`, to tell parallel sessions apart.
        var project: String?
        var notificationType: String?

        init(event: String, sessionID: String, project: String? = nil, notificationType: String? = nil) {
            self.event = event
            self.sessionID = sessionID
            self.project = project
            self.notificationType = notificationType
        }

        init?(_ object: [String: Any]) {
            guard let event = object["hook_event_name"] as? String else { return nil }
            self.init(
                event: event,
                sessionID: object["session_id"] as? String ?? "",
                project: object["project"] as? String,
                notificationType: object["notification_type"] as? String
            )
        }
    }

    struct Call: Equatable, Sendable {
        var operation: APIOperation
        /// Dropped when a Claude activity of the same source ended in the last few seconds:
        /// `agent_completed` repeats what the background session's own `Stop` said.
        var skipAfterRecentEnd = false
    }

    /// The adapter starts activities with a long timeout, so a long task doesn't vanish quietly.
    static let activityTimeout: TimeInterval = 2 * 60 * 60
    static let recentEndWindow: TimeInterval = 10

    enum Text {
        static var working: String { String(localized: "Claude is working") }
        static var finished: String { String(localized: "Claude finished") }
        static var waiting: String { String(localized: "Claude is waiting for you") }
        static var stopped: String { String(localized: "Claude stopped") }
    }

    /// The calls for one hook event; none for events it doesn't use.
    static func calls(for hook: HookEvent) -> [Call] {
        let id = hook.sessionID
        let project = hook.project.flatMap { $0.isEmpty ? nil : $0 }
        let needsSession = ["UserPromptSubmit", "Stop", "StopFailure", "SessionEnd"].contains(hook.event)
            || ["permission_prompt", "elicitation_dialog"].contains(hook.notificationType ?? "")
        guard !needsSession || !id.isEmpty else { return [] }

        switch hook.event {
        case "UserPromptSubmit":
            return [Call(operation: .start(id: id, NoticeText(title: Text.working, subtitle: project), state: .info, timeout: activityTimeout))]
        case "Stop":
            return [Call(operation: .end(id: id, title: Text.finished, subtitle: project, state: .success, quiet: false))]
        case "StopFailure":
            return [Call(operation: .end(id: id, title: Text.stopped, subtitle: project, state: .attention, quiet: false))]
        case "SessionEnd":
            return [Call(operation: .end(id: id, title: nil, subtitle: nil, state: .info, quiet: true))]
        case "Notification":
            switch hook.notificationType {
            case "permission_prompt", "elicitation_dialog":
                return [Call(operation: .update(id: id, title: Text.waiting, subtitle: project, state: .attention))]
            case "agent_needs_input":
                // Sent by the agent view process: its session_id isn't the background session's.
                return [Call(operation: .notify(NoticeText(title: Text.waiting, subtitle: project), state: .attention, action: nil))]
            case "agent_completed":
                return [Call(operation: .notify(NoticeText(title: Text.finished, subtitle: project), state: .success, action: nil), skipAfterRecentEnd: true)]
            default:
                return []
            }
        default:
            return []
        }
    }
}
