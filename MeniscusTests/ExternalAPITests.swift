import Foundation
import Testing
@testable import Meniscus

struct APIRequestTests {
    @Test func decodesNotify() throws {
        let request = try APIRequest.decode(["v": 1, "op": "notify", "title": "Build finished", "subtitle": "api", "state": "success", "at": 1_700_000_000_000], trusted: true)
        #expect(request.operation == .notify(NoticeText(title: "Build finished", subtitle: "api"), state: .success, action: nil))
        #expect(request.at == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func unknownStateIsInfoAndUnknownFieldsAreIgnored() throws {
        let request = try APIRequest.decode(["op": "notify", "title": "Hi", "state": "celebrate", "color": "red"], trusted: true)
        #expect(request.operation == .notify(NoticeText(title: "Hi", subtitle: nil), state: .info, action: nil))
    }

    @Test func textIsCleanedAndCut() throws {
        let long = String(repeating: "a", count: 100)
        let request = try APIRequest.decode(["op": "notify", "title": "  Line\u{0007}one\n " + long, "subtitle": long], trusted: true)
        guard case .notify(let text, _, _) = request.operation else { Issue.record("not notify"); return }
        #expect(text.title.count == APILimits.titleLength)
        #expect(text.title.hasPrefix("Lineone"))
        #expect(text.title.hasSuffix("…"))
        #expect(text.subtitle?.count == APILimits.subtitleLength)
    }

    @Test func actionsOnlyFromTrustedChannelsAndOnlySafeOnes() throws {
        let https = try APIRequest.decode(["op": "notify", "title": "CI", "open": "https://example.com/run/1"], trusted: true)
        #expect(https.operation == .notify(NoticeText(title: "CI", subtitle: nil), state: .info, action: .openURL(URL(string: "https://example.com/run/1")!)))
        let untrusted = try APIRequest.decode(["op": "notify", "title": "CI", "open": "https://example.com"], trusted: false)
        #expect(untrusted.operation == .notify(NoticeText(title: "CI", subtitle: nil), state: .info, action: nil))
        #expect(APIRequest.action(from: "javascript:alert(1)") == nil)
        #expect(APIRequest.action(from: "http://example.com") == nil)
        #expect(APIRequest.action(from: "/tmp/report.txt") == .openFile(URL(filePath: "/tmp/report.txt")))
    }

    @Test func activityCalls() throws {
        let start = try APIRequest.decode(["op": "start", "id": "build-42", "title": "Building", "timeout": 999_999], trusted: true)
        #expect(start.operation == .start(id: "build-42", NoticeText(title: "Building", subtitle: nil), state: .info, timeout: APILimits.timeoutRange.upperBound))
        let end = try APIRequest.decode(["op": "end", "id": "build-42"], trusted: true)
        #expect(end.operation == .end(id: "build-42", title: nil, subtitle: nil, state: .success, quiet: false))
        let quiet = try APIRequest.decode(["op": "end", "id": "build-42", "quiet": true], trusted: true)
        #expect(quiet.operation == .end(id: "build-42", title: nil, subtitle: nil, state: .success, quiet: true))
    }

    @Test func rejectsWhatItCantShow() {
        #expect(throws: APIError.invalid("title is required")) { try APIRequest.decode(["op": "notify"], trusted: true) }
        #expect(throws: APIError.invalid("id is required")) { try APIRequest.decode(["op": "end"], trusted: true) }
        #expect(throws: APIError.unsupportedVersion(2)) { try APIRequest.decode(["v": 2, "op": "notify", "title": "x"], trusted: true) }
        #expect(throws: APIError.self) { try APIRequest.decode(["op": "explode"], trusted: true) }
        #expect(throws: APIError.self) { try APIRequest.decode(["op": "end", "id": String(repeating: "x", count: 129)], trusted: true) }
    }

    @Test func linksOnlyNotify() throws {
        let link = try APIRequest.link(URL(string: "meniscus://v1/notify?title=Build%20finished&subtitle=api&state=success&open=https://evil.example")!)
        #expect(link.operation == .notify(NoticeText(title: "Build finished", subtitle: "api"), state: .success, action: nil))
        #expect(throws: APIError.self) { try APIRequest.link(URL(string: "meniscus://v1/start?id=x&title=y")!) }
        #expect(throws: APIError.unsupportedVersion(9)) { try APIRequest.link(URL(string: "meniscus://v9/notify?title=x")!) }
    }
}

/// `#expect` can't call a mutating method on a local value, so the tests use a reference.
private final class Order {
    var value = EventOrder()
    func accept(source: String, id: String, at: Date, rank: Int, now: Date) -> Bool {
        value.accept(source: source, id: id, at: at, rank: rank, now: now)
    }
    func markEnded(source: String, id: String, now: Date) {
        value.markEnded(source: source, id: id, now: now)
    }
}

struct EventOrderTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func aLateStartAfterItsEndIsIgnored() {
        let order = Order()
        // The hooks ran start (t=1) then end (t=2), but end arrived first.
        #expect(order.accept(source: "s", id: "a", at: now.addingTimeInterval(2), rank: 2, now: now))
        #expect(!order.accept(source: "s", id: "a", at: now.addingTimeInterval(1), rank: 0, now: now))
        // The next turn starts later and is accepted.
        #expect(order.accept(source: "s", id: "a", at: now.addingTimeInterval(5), rank: 0, now: now))
    }

    @Test func atEqualTimesEndWins() {
        let order = Order()
        #expect(order.accept(source: "s", id: "a", at: now, rank: 2, now: now))
        #expect(!order.accept(source: "s", id: "a", at: now, rank: 0, now: now))
        #expect(!order.accept(source: "s", id: "a", at: now, rank: 1, now: now))
    }

    @Test func sourcesAndIdsAreSeparate() {
        let order = Order()
        #expect(order.accept(source: "s", id: "a", at: now, rank: 2, now: now))
        #expect(order.accept(source: "s", id: "b", at: now.addingTimeInterval(-1), rank: 0, now: now))
        #expect(order.accept(source: "t", id: "a", at: now.addingTimeInterval(-1), rank: 0, now: now))
    }

    @Test func endedIdsAreForgottenAfterTenMinutes() {
        let order = Order()
        #expect(order.accept(source: "s", id: "a", at: now, rank: 2, now: now))
        let later = now.addingTimeInterval(EventOrder.endedMemory + 1)
        #expect(order.accept(source: "s", id: "a", at: now.addingTimeInterval(-5), rank: 0, now: later))
    }

    @Test func aTimedOutActivityIgnoresLateEvents() {
        let order = Order()
        #expect(order.accept(source: "s", id: "a", at: now, rank: 0, now: now))
        order.markEnded(source: "s", id: "a", now: now.addingTimeInterval(60))
        #expect(!order.accept(source: "s", id: "a", at: now.addingTimeInterval(30), rank: 1, now: now.addingTimeInterval(61)))
    }
}

/// `#expect` can't call a mutating method on a local value, so the tests use a reference.
private final class Limiter {
    var value = NoticeLimiter()
    func allow(_ key: String, _ fingerprint: String, at seconds: TimeInterval, limits: [NoticeLimiter.Limit] = NoticeLimiter.link) -> Bool {
        value.allow(key: key, limits: limits, fingerprint: fingerprint, now: Date(timeIntervalSince1970: seconds))
    }
}

struct NoticeLimiterTests {
    @Test func linksAreLimitedGlobally() {
        let limiter = Limiter()
        #expect(limiter.allow("link", "a", at: 0))
        #expect(limiter.allow("link", "b", at: 1))
        #expect(limiter.allow("link", "c", at: 2))
        #expect(!limiter.allow("link", "d", at: 3))
        #expect(limiter.allow("link", "e", at: 11))
    }

    @Test func duplicatesWithinAMinuteShowOnce() {
        let limiter = Limiter()
        #expect(limiter.allow("cli:term", "same", at: 0, limits: NoticeLimiter.trusted))
        #expect(!limiter.allow("cli:term", "same", at: 30, limits: NoticeLimiter.trusted))
        #expect(limiter.allow("cli:other", "same", at: 30, limits: NoticeLimiter.trusted))
        #expect(limiter.allow("cli:term", "same", at: 61, limits: NoticeLimiter.trusted))
    }

    @Test func trustedSourcesHaveTheirOwnLimit() {
        let limiter = Limiter()
        for index in 0..<10 { #expect(limiter.allow("cli:a", "\(index)", at: Double(index), limits: NoticeLimiter.trusted)) }
        #expect(!limiter.allow("cli:a", "x", at: 20, limits: NoticeLimiter.trusted))
        #expect(limiter.allow("cli:b", "x", at: 20, limits: NoticeLimiter.trusted))
    }
}

struct EndRuleTests {
    @Test(arguments: [
        (NoticeState.info, false, false), (.success, false, false), (.attention, false, true),
        (.info, true, true), (.success, true, true), (.attention, true, true),
    ])
    func shortTasksStaySilentUnlessTheyNeedAttention(state: NoticeState, visible: Bool, shows: Bool) {
        #expect(EndRule.showsBanner(state: state, indicatorWasVisible: visible, quiet: false) == shows)
        #expect(!EndRule.showsBanner(state: state, indicatorWasVisible: visible, quiet: true))
    }

    @Test func bannerTimes() {
        #expect(NoticeState.info.bannerDuration == 3)
        #expect(NoticeState.attention.bannerDuration == 5)
        #expect(NoticeState.allCases.allSatisfy { $0.bannerDuration <= 5 })
    }
}

struct ClaudeCodeAdapterTests {
    private func calls(_ event: String, _ type: String? = nil, session: String = "s1") -> [ClaudeCodeAdapter.Call] {
        ClaudeCodeAdapter.calls(for: .init(event: event, sessionID: session, project: "meniscus", notificationType: type))
    }

    @Test func aTurnStartsAndEndsTheSessionsActivity() {
        #expect(calls("UserPromptSubmit") == [.init(operation: .start(id: "s1", NoticeText(title: ClaudeCodeAdapter.Text.working, subtitle: "meniscus"), state: .info, timeout: 7200))])
        #expect(calls("Stop") == [.init(operation: .end(id: "s1", title: ClaudeCodeAdapter.Text.finished, subtitle: "meniscus", state: .success, quiet: false))])
        #expect(calls("StopFailure").first?.operation == .end(id: "s1", title: ClaudeCodeAdapter.Text.stopped, subtitle: "meniscus", state: .attention, quiet: false))
        #expect(calls("SessionEnd").first?.operation == .end(id: "s1", title: nil, subtitle: nil, state: .info, quiet: true))
    }

    @Test func permissionTurnsTheActivityToAttention() {
        #expect(calls("Notification", "permission_prompt").first?.operation == .update(id: "s1", title: ClaudeCodeAdapter.Text.waiting, subtitle: "meniscus", state: .attention))
        #expect(calls("Notification", "elicitation_dialog").count == 1)
    }

    @Test func backgroundSessionNoticesDontTouchActivities() {
        let input = calls("Notification", "agent_needs_input")
        #expect(input.first?.operation.activityID == nil)
        let completed = calls("Notification", "agent_completed")
        #expect(completed.first?.skipAfterRecentEnd == true)
    }

    @Test func ignoredEvents() {
        #expect(calls("Notification", "idle_prompt").isEmpty)
        #expect(calls("PostToolUse").isEmpty)
        #expect(calls("Stop", session: "").isEmpty)
    }

    @Test func forwardedFieldsOnly() {
        let event = ClaudeCodeAdapter.HookEvent(["hook_event_name": "Stop", "session_id": "abc", "project": "api", "prompt": "secret"])
        #expect(event == .init(event: "Stop", sessionID: "abc", project: "api"))
    }
}

@MainActor
struct ExternalNoticesTests {
    private let terminal = APISource(key: "app:com.apple.Terminal", name: "Terminal", bundleID: "com.apple.Terminal",
                                     appURL: URL(filePath: "/System/Applications/Utilities/Terminal.app"), channel: .cli)

    private func make(delay: Double = 0.05) -> (ExternalNotices, ActivityCenter) {
        let defaults = UserDefaults(suiteName: "meniscus-api-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.externalIndicatorDelay = delay
        settings.hapticsEnabled = false
        let center = ActivityCenter()
        return (ExternalNotices(center: center, settings: settings, defaults: defaults), center)
    }

    private func request(_ operation: APIOperation, at: Date? = nil) -> APIRequest {
        APIRequest(version: 1, at: at, operation: operation)
    }

    @Test func aNoticeIsAMiniBanner() {
        let (notices, center) = make()
        notices.handle(request(.notify(NoticeText(title: "Build finished", subtitle: "api"), state: .success, action: nil)), from: terminal)
        #expect(center.current?.kind == .externalBanner)
        #expect(center.current?.priority == .external)
        let banner = notices.banners[center.current?.id ?? ""]
        #expect(banner?.text.title == "Build finished")
        // Its clock started when it showed.
        #expect(center.current?.expiresAt != nil)
        #expect(notices.isClickable(center.current?.id ?? ""))
    }

    @Test func attentionOutranksMusicAndInfoDoesnt() {
        let (notices, center) = make()
        center.post(LiveActivity(id: "music", kind: .nowPlaying, priority: .ongoing, updatedAt: .now, expiresAt: nil))
        notices.handle(request(.notify(NoticeText(title: "Saved", subtitle: nil), state: .info, action: nil)), from: terminal)
        #expect(center.current?.id == "music")
        notices.handle(request(.notify(NoticeText(title: "Tests failed", subtitle: nil), state: .attention, action: nil)), from: terminal)
        #expect(center.current?.priority == .externalAttention)
    }

    @Test func aShortTaskStaysSilent() {
        let (notices, center) = make(delay: 10)
        notices.handle(request(.start(id: "a", NoticeText(title: "Working", subtitle: nil), state: .info, timeout: nil)), from: terminal)
        #expect(center.current == nil)
        notices.handle(request(.end(id: "a", title: "Done", subtitle: nil, state: .success, quiet: false)), from: terminal)
        #expect(center.current == nil)
        #expect(notices.runningCount == 0)
    }

    @Test func aShortTaskThatNeedsAttentionStillSaysSo() {
        let (notices, center) = make(delay: 10)
        notices.handle(request(.start(id: "a", NoticeText(title: "Working", subtitle: nil), state: .info, timeout: nil)), from: terminal)
        notices.handle(request(.end(id: "a", title: "Failed", subtitle: nil, state: .attention, quiet: false)), from: terminal)
        #expect(center.current?.kind == .externalBanner)
    }

    @Test func aLongTaskShowsItsIndicatorThenABanner() async throws {
        let (notices, center) = make(delay: 0.05)
        notices.handle(request(.start(id: "a", NoticeText(title: "Working", subtitle: nil), state: .info, timeout: nil)), from: terminal)
        try await Task.sleep(for: .milliseconds(200))
        #expect(center.current?.kind == .externalActivity)
        #expect(notices.groups[center.current?.id ?? ""]?.count == 1)
        notices.handle(request(.end(id: "a", title: "Done", subtitle: nil, state: .success, quiet: false)), from: terminal)
        #expect(center.current?.kind == .externalBanner)
    }

    @Test func parallelTasksAreOneGroupWithACount() async throws {
        let (notices, center) = make(delay: 0.05)
        for id in ["a", "b"] {
            notices.handle(request(.start(id: id, NoticeText(title: "Working", subtitle: nil), state: .info, timeout: nil)), from: terminal)
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(notices.groups.count == 1)
        #expect(notices.groups.values.first?.count == 2)
        #expect(center.current?.kind == .externalActivity)
    }

    @Test func endBannersCollapseAfterThree() async throws {
        let (notices, center) = make(delay: 0.05)
        let ids = ["a", "b", "c", "d", "e"]
        for id in ids {
            notices.handle(request(.start(id: id, NoticeText(title: "Working", subtitle: id), state: .info, timeout: nil)), from: terminal)
        }
        try await Task.sleep(for: .milliseconds(200))
        for id in ids {
            notices.handle(request(.end(id: id, title: "Claude finished", subtitle: id, state: .success, quiet: false)), from: terminal)
        }
        // Three banners and one summary for the other two; the first shows first.
        #expect(notices.banners.count == 4)
        #expect(notices.banners.values.contains { $0.text.title == String(localized: "\("Claude finished") · \(2) more") })
        #expect(notices.banners[center.current?.id ?? ""]?.text.subtitle == "a")
    }

    @Test func aLateStartAfterItsEndLeavesNothingRunning() {
        let (notices, center) = make()
        let date = Date()
        notices.handle(request(.end(id: "a", title: nil, subtitle: nil, state: .success, quiet: false), at: date), from: terminal)
        notices.handle(request(.start(id: "a", NoticeText(title: "Working", subtitle: nil), state: .info, timeout: nil), at: date.addingTimeInterval(-1)), from: terminal)
        #expect(notices.runningCount == 0)
        #expect(center.current == nil)
    }

    @Test func activitiesOfOtherSourcesAreUntouched() {
        let (notices, _) = make(delay: 10)
        let other = APISource(key: "app:com.example.Editor", name: "Editor", channel: .cli)
        notices.handle(request(.start(id: "s1", NoticeText(title: "Working", subtitle: nil), state: .info, timeout: nil)), from: terminal)
        notices.handle(request(.end(id: "s1", title: nil, subtitle: nil, state: .success, quiet: false)), from: other)
        #expect(notices.runningCount == 1)
    }

    @Test func linksAreOffByDefault() {
        let (notices, center) = make()
        notices.handleLink(URL(string: "meniscus://v1/notify?title=Hello")!)
        #expect(center.current == nil)
        #expect(!notices.isClickable("external.banner.1"))
    }

    @Test func aSwitchedOffSourceShowsNothing() {
        let (notices, center) = make()
        notices.handle(request(.notify(NoticeText(title: "One", subtitle: nil), state: .info, action: nil)), from: terminal)
        center.remove(id: center.current?.id ?? "")
        notices.setEnabled(false, source: terminal.key)
        notices.handle(request(.notify(NoticeText(title: "Two", subtitle: nil), state: .info, action: nil)), from: terminal)
        #expect(center.current == nil)
    }

    @Test func claudeCodeShortTurnIsSilentAndBackgroundRepeatsAreDropped() {
        let (notices, center) = make(delay: 10)
        notices.handleClaudeCode(.init(event: "UserPromptSubmit", sessionID: "s1", project: "meniscus"), at: nil, from: terminal)
        notices.handleClaudeCode(.init(event: "Stop", sessionID: "s1", project: "meniscus"), at: nil, from: terminal)
        #expect(center.current == nil)
        notices.handleClaudeCode(.init(event: "Notification", sessionID: "viewer", notificationType: "agent_completed"), at: nil, from: terminal)
        #expect(center.current == nil)
        notices.handleClaudeCode(.init(event: "Notification", sessionID: "s2", project: "api", notificationType: "permission_prompt"), at: nil, from: terminal)
        #expect(center.current?.priority == .externalAttention)
    }
}
