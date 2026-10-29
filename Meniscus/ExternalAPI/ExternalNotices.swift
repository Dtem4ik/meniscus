import AppKit
import Observation
import OSLog

/// Shows what other apps, scripts and Shortcuts ask for, through the island's own machinery:
/// banners are mini banners in the activity queue, running activities are one compact activity
/// per source. docs/external-api.md describes the rules.
@Observable
final class ExternalNotices {
    /// What a banner shows, by its live activity id.
    struct Banner: Equatable {
        var source: APISource
        var text: NoticeText
        var state: NoticeState
        var action: APIAction?
    }

    /// One source's running activities whose indicator is visible, as the compact island shows
    /// them.
    struct Group: Equatable {
        var source: APISource
        var count: Int
        var needsAttention: Bool
    }

    /// A source seen so far, with its switch.
    struct KnownSource: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var bundleID: String?
        var isEnabled: Bool
        var lastSeen: Date
    }

    private(set) var banners: [LiveActivity.ID: Banner] = [:]
    private(set) var groups: [LiveActivity.ID: Group] = [:]
    private(set) var knownSources: [KnownSource] = []

    @ObservationIgnored private let center: ActivityCenter
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var order = EventOrder()
    @ObservationIgnored private var limiter = NoticeLimiter()
    @ObservationIgnored private var running: [String: Running] = [:]
    @ObservationIgnored private var lastEnd: [String: Date] = [:]
    @ObservationIgnored private var bannerSequence = 0
    /// End banners of each source that are waiting or showing, and its collapsed summary.
    @ObservationIgnored private var endBanners: [String: [LiveActivity.ID]] = [:]
    @ObservationIgnored private var summaries: [String: (id: LiveActivity.ID, title: String, count: Int)] = [:]

    private struct Running {
        var source: APISource
        var id: String
        var text: NoticeText
        var state: NoticeState
        var timeout: TimeInterval
        var isVisible = false
        var generation: Int
        var indicatorTask: Task<Void, Never>?
        var timeoutTask: Task<Void, Never>?
    }

    @ObservationIgnored private var generation = 0

    init(center: ActivityCenter, settings: AppSettings = .shared, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.center = center
        self.settings = settings
        self.defaults = defaults
        self.now = now
        loadSources()
    }

    // MARK: Requests

    /// A request from any channel. Returns quietly when it's switched off, limited or out of order.
    func handle(_ request: APIRequest, from source: APISource) {
        guard isAllowed(source) else { return }
        let date = now()
        let operation = request.operation
        if let id = operation.activityID {
            let at = request.at ?? date
            guard order.accept(source: source.key, id: id, at: at, rank: operation.rank, now: date) else {
                Logger.api.notice("Ignored an event older than the last one for its activity")
                return
            }
        }
        switch operation {
        case .notify(let text, let state, let action):
            showBanner(Banner(source: source, text: text, state: state, action: action))
        case .start(let id, let text, let state, let timeout):
            start(id: id, text: text, state: state, timeout: timeout ?? APILimits.defaultTimeout, source: source)
        case .update(let id, let title, let subtitle, let state):
            update(id: id, title: title, subtitle: subtitle, state: state, source: source)
        case .end(let id, let title, let subtitle, let state, let quiet):
            end(id: id, title: title, subtitle: subtitle, state: state, quiet: quiet, source: source)
        case .status:
            break
        }
    }

    /// A Claude Code hook, forwarded by `meniscus hook claude-code`.
    func handleClaudeCode(_ hook: ClaudeCodeAdapter.HookEvent, at: Date?, from source: APISource) {
        for call in ClaudeCodeAdapter.calls(for: hook) {
            if call.skipAfterRecentEnd, let ended = lastEnd[source.key],
               now().timeIntervalSince(ended) < ClaudeCodeAdapter.recentEndWindow {
                continue
            }
            handle(APIRequest(version: 1, at: at, operation: call.operation), from: source)
        }
    }

    /// `meniscus://v1/notify?…`
    func handleLink(_ url: URL) {
        do {
            handle(try APIRequest.link(url), from: .link)
        } catch {
            Logger.api.notice("Ignored a link: \(error.message, privacy: .public)")
        }
    }

    // MARK: Activities

    private func key(_ source: APISource, _ id: String) -> String { source.key + "\u{1F}" + id }

    private func start(id: String, text: NoticeText, state: NoticeState, timeout: TimeInterval, source: APISource) {
        let key = key(source, id)
        // Starting again restarts it.
        cancelTasks(of: key)
        generation += 1
        var activity = Running(source: source, id: id, text: text, state: state, timeout: timeout, generation: generation)
        let current = generation
        activity.indicatorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.settings.externalIndicatorDelay ?? 10))
            guard !Task.isCancelled else { return }
            self?.showIndicator(key: key, generation: current)
        }
        activity.timeoutTask = timeoutTask(key: key, generation: current, after: timeout)
        running[key] = activity
        updateGroup(of: source)
        if state == .attention { showBanner(Banner(source: source, text: text, state: .attention, action: nil)) }
    }

    private func update(id: String, title: String?, subtitle: String?, state: NoticeState?, source: APISource) {
        let key = key(source, id)
        guard var activity = running[key] else {
            // Something needs the user even if its start never arrived.
            if state == .attention, let title {
                showBanner(Banner(source: source, text: NoticeText(title: title, subtitle: subtitle), state: .attention, action: nil))
            }
            return
        }
        let becameAttention = state == .attention && activity.state != .attention
        if let title { activity.text.title = title }
        if let subtitle { activity.text.subtitle = subtitle }
        if let state { activity.state = state }
        activity.timeoutTask?.cancel()
        activity.timeoutTask = timeoutTask(key: key, generation: activity.generation, after: activity.timeout)
        running[key] = activity
        updateGroup(of: source)
        // The user must see it now, even before the indicator would appear.
        if becameAttention { showBanner(Banner(source: source, text: activity.text, state: .attention, action: nil)) }
    }

    private func end(id: String, title: String?, subtitle: String?, state: NoticeState, quiet: Bool, source: APISource) {
        let key = key(source, id)
        let activity = running.removeValue(forKey: key)
        cancelTasks(of: key, activity)
        lastEnd[source.key] = now()
        updateGroup(of: source)
        guard EndRule.showsBanner(state: state, indicatorWasVisible: activity?.isVisible ?? false, quiet: quiet) else { return }
        let text = NoticeText(
            title: title ?? activity?.text.title ?? source.name,
            subtitle: subtitle ?? activity?.text.subtitle
        )
        showEndBanner(Banner(source: source, text: text, state: state, action: nil))
    }

    private func showIndicator(key: String, generation: Int) {
        guard var activity = running[key], activity.generation == generation else { return }
        activity.isVisible = true
        running[key] = activity
        updateGroup(of: activity.source)
    }

    private func timeoutTask(key: String, generation: Int, after timeout: TimeInterval) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, let self, let activity = self.running[key], activity.generation == generation else { return }
            // Nothing heard for too long: it leaves quietly, no banner and no error.
            self.running[key] = nil
            self.order.markEnded(source: activity.source.key, id: activity.id, now: self.now())
            self.updateGroup(of: activity.source)
            Logger.api.notice("An external activity timed out")
        }
    }

    private func cancelTasks(of key: String, _ activity: Running? = nil) {
        let activity = activity ?? running[key]
        activity?.indicatorTask?.cancel()
        activity?.timeoutTask?.cancel()
    }

    /// One compact activity per source: the visible ones, with their number.
    private func updateGroup(of source: APISource) {
        let id = "external.activity." + source.key
        let visible = running.values.filter { $0.source.key == source.key && $0.isVisible }
        guard !visible.isEmpty else {
            groups[id] = nil
            center.remove(id: id)
            return
        }
        let group = Group(source: source, count: visible.count, needsAttention: visible.contains { $0.state == .attention })
        let changed = groups[id] != group
        groups[id] = group
        if changed || !center.contains(id: id) {
            let priority: LiveActivity.Priority = group.needsAttention ? .externalAttention : .externalActivity
            center.post(LiveActivity(id: id, kind: .externalActivity, priority: priority, updatedAt: now(), expiresAt: nil))
        }
    }

    // MARK: Banners

    private func showEndBanner(_ banner: Banner) {
        let sourceKey = banner.source.key
        let waiting = (endBanners[sourceKey] ?? []).filter { center.contains(id: $0) }
        endBanners[sourceKey] = waiting
        // After three in a row, the rest collapse into one: "Claude finished · 2 more".
        guard banner.state != .attention, waiting.count >= EndRule.bannersInARow else {
            if let id = showBanner(banner) { endBanners[sourceKey, default: []].append(id) }
            return
        }
        var summary = summaries[sourceKey].flatMap { center.contains(id: $0.id) ? $0 : nil }
            ?? (id: "external.more." + sourceKey, title: banner.text.title, count: 0)
        summary.count += 1
        summaries[sourceKey] = summary
        let text = NoticeText(title: String(localized: "\(summary.title) · \(summary.count) more"), subtitle: nil)
        showBanner(Banner(source: banner.source, text: text, state: banner.state, action: nil), id: summary.id, limited: false)
    }

    @discardableResult
    private func showBanner(_ banner: Banner, id: LiveActivity.ID? = nil, limited: Bool = true) -> LiveActivity.ID? {
        let date = now()
        if limited {
            let channel = banner.source.channel
            let limitKey = channel == .link ? "link" : banner.source.key
            let fingerprint = [banner.text.title, banner.text.subtitle ?? "", banner.state.rawValue].joined(separator: "\u{1F}")
            guard limiter.allow(key: limitKey, limits: channel == .link ? NoticeLimiter.link : NoticeLimiter.trusted, fingerprint: fingerprint, now: date) else {
                Logger.api.notice("A notice was limited or repeated")
                return nil
            }
        }
        banners = banners.filter { center.contains(id: $0.key) }
        let id = id ?? {
            bannerSequence += 1
            return "external.banner.\(bannerSequence)"
        }()
        banners[id] = banner
        var activity = LiveActivity(
            id: id, kind: .externalBanner,
            priority: banner.state == .attention ? .externalAttention : .external,
            updatedAt: date, expiresAt: nil
        )
        activity.displayDuration = banner.state.bannerDuration
        activity.showBy = date.addingTimeInterval(banner.state.bannerWait)
        activity.waitsInLine = true
        center.post(activity)
        if banner.state == .attention, settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        return id
    }

    /// Trusted banners take a click: their action, or else their app comes forward, as macOS
    /// notifications do. Links never take clicks.
    func isClickable(_ id: LiveActivity.ID) -> Bool {
        guard let banner = banners[id], banner.source.channel.isTrusted else { return false }
        return banner.action != nil || banner.source.appURL != nil
    }

    func click(_ id: LiveActivity.ID) {
        guard isClickable(id), let banner = banners[id] else { return }
        switch banner.action {
        case .openURL(let url), .openFile(let url):
            NSWorkspace.shared.open(url)
        case nil:
            if let bundleID = banner.source.bundleID,
               let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                app.activate()
            } else if let url = banner.source.appURL {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
        center.remove(id: id)
    }

    // MARK: Sources

    private func isAllowed(_ source: APISource) -> Bool {
        let date = now()
        if let index = knownSources.firstIndex(where: { $0.id == source.key }) {
            knownSources[index].lastSeen = date
            knownSources[index].name = source.name
        } else {
            knownSources.append(KnownSource(id: source.key, name: source.name, bundleID: source.bundleID, isEnabled: true, lastSeen: date))
        }
        saveSources()
        switch source.channel {
        case .link: guard settings.externalLinks else { return false }
        case .cli, .shortcuts: guard settings.externalCLI else { return false }
        case .developer: break
        }
        return knownSources.first { $0.id == source.key }?.isEnabled ?? true
    }

    func setEnabled(_ isEnabled: Bool, source id: String) {
        guard let index = knownSources.firstIndex(where: { $0.id == id }) else { return }
        knownSources[index].isEnabled = isEnabled
        saveSources()
    }

    func forget(source id: String) {
        knownSources.removeAll { $0.id == id }
        saveSources()
    }

    private func loadSources() {
        guard let data = defaults.data(forKey: SettingsKey.externalSources),
              let sources = try? JSONDecoder().decode([KnownSource].self, from: data) else { return }
        knownSources = sources
    }

    private func saveSources() {
        guard let data = try? JSONEncoder().encode(knownSources) else { return }
        defaults.set(data, forKey: SettingsKey.externalSources)
    }

    // MARK: Developer

    func simulateNotices() {
        let notices = [
            (NoticeState.info, String(localized: "Backup started")),
            (.success, String(localized: "Build finished")),
            (.attention, String(localized: "Tests failed")),
        ]
        for (state, title) in notices {
            handle(APIRequest(version: 1, at: nil, operation: .notify(NoticeText(title: title, subtitle: APISource.developer.name), state: state, action: nil)), from: .developer)
        }
    }

    /// A short task stays silent; a long one shows its indicator, then a banner.
    func simulateActivity(long: Bool) {
        let id = "simulated-\(long ? "long" : "short")"
        handle(APIRequest(version: 1, at: nil, operation: .start(id: id, NoticeText(title: String(localized: "Exporting"), subtitle: APISource.developer.name), state: .info, timeout: nil)), from: .developer)
        let delay = long ? settings.externalIndicatorDelay + 4 : 2
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.handle(APIRequest(version: 1, at: nil, operation: .end(id: id, title: String(localized: "Export finished"), subtitle: nil, state: .success, quiet: false)), from: .developer)
        }
    }

    /// Four parallel tasks: one grouped indicator, then three banners and one collapsed.
    func simulateParallelActivities() {
        let ids = (1...4).map { "simulated-parallel-\($0)" }
        for (index, id) in ids.enumerated() {
            handle(APIRequest(version: 1, at: nil, operation: .start(id: id, NoticeText(title: String(localized: "Rendering"), subtitle: String(localized: "Project \(index + 1)")), state: .info, timeout: nil)), from: .developer)
        }
        let delay = settings.externalIndicatorDelay + 3
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            for id in ids {
                self?.handle(APIRequest(version: 1, at: nil, operation: .end(id: id, title: String(localized: "Render finished"), subtitle: nil, state: .success, quiet: false)), from: .developer)
            }
        }
    }

    /// An `end` that arrives before its `start`: the late start is ignored and nothing stays.
    func simulateLateStart() {
        let date = now()
        handle(APIRequest(version: 1, at: date, operation: .end(id: "simulated-late", title: nil, subtitle: nil, state: .success, quiet: false)), from: .developer)
        handle(APIRequest(version: 1, at: date.addingTimeInterval(-1), operation: .start(id: "simulated-late", NoticeText(title: String(localized: "Late start"), subtitle: nil), state: .info, timeout: nil)), from: .developer)
    }

    /// For tests: how many activities run, visible or not.
    var runningCount: Int { running.count }
}
