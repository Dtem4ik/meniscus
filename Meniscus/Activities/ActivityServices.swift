import AppKit
import Observation
import OSLog

/// The long-lived sources of live data. Created once by the app delegate.
@Observable
final class ActivityServices {
    static let shared = ActivityServices()

    let center = ActivityCenter()
    let power = PowerSourceMonitor()
    let calendar = CalendarService()
    let nowPlaying = NowPlayingService()
    let inputSource = InputSourceMonitor()
    let presentation = PresentationGuard()
    let headphones = HeadphonesMonitor()

    /// Battery level shown by the charging activity.
    private(set) var chargingLevel: Int?
    /// Battery level shown by the low battery warning.
    private(set) var lowBatteryLevel: Int?
    /// Short name of the keyboard input source just switched to, like EN or РУ.
    private(set) var inputSourceLabel: String?
    /// The event the meeting reminder is about, and whether it is about to start or starting.
    private(set) var meetingEvent: CalendarEventSnapshot?
    private(set) var meetingMoment: MeetingReminder.Moment = .soon
    /// The headphones that just connected or disconnected.
    private(set) var headphonesEvent: HeadphonesEvent?

    /// How long the charging activity stays in the notch after the charger is connected.
    static let chargingActivityDuration: TimeInterval = 4
    static let lowBatteryActivityDuration: TimeInterval = 4
    static let inputSourceActivityDuration: TimeInterval = 1.2
    static let captureSavedActivityDuration: TimeInterval = 1.6
    static let meetingActivityDuration: TimeInterval = 5
    static let headphonesActivityDuration: TimeInterval = 4
    /// A battery reading later than this after the connection is old news and is dropped.
    static let headphonesBatteryWindow: TimeInterval = 8

    @ObservationIgnored private let logger = Logger.power
    @ObservationIgnored private var lowBatteryWarnings = LowBatteryWarnings()
    @ObservationIgnored private var settings: AppSettings = .shared
    @ObservationIgnored private var headphonesConnectedAt: Date?

    init() {
        // Wired here rather than in start(), so the Developer simulations (and tests) work too.
        calendar.onMeetingMoment = { [weak self] event, moment in self?.showMeeting(event, moment) }
        headphones.onEvent = { [weak self] event in self?.showHeadphones(event) }
    }

    func start(settings: AppSettings) {
        self.settings = settings
        power.onEvent = { [weak self] event in self?.handle(event) }
        power.onStateChange = { [weak self] state in self?.checkLowBattery(state) }
        power.start()
        calendar.hiddenCalendarIDs = { settings.hiddenCalendarIDs }
        updateCalendar(settings: settings)
        inputSource.onChange = { [weak self] label in self?.showInputSource(label) }
        updateInputSource(settings: settings)
        updateHeadphones(settings: settings)
        presentation.start()

        nowPlaying.onChange = { [weak self] info in
            guard let self else { return }
            if let info, info.isPlaying {
                center.post(LiveActivity(id: "now-playing", kind: .nowPlaying, priority: .ongoing, updatedAt: Date(), expiresAt: nil))
            } else {
                center.remove(id: "now-playing")
            }
        }
        if settings.showNowPlaying { nowPlaying.start() }

        // A reminder that files wait on the shelf; anything else in the notch comes first.
        ShelfController.shared.onItemsChange = { [weak self] count in
            guard let self else { return }
            if count > 0 {
                center.post(LiveActivity(id: "shelf", kind: .shelf, priority: .background, updatedAt: Date(), expiresAt: nil))
            } else {
                center.remove(id: "shelf")
            }
        }
    }

    /// The calendar runs for the next event on the home view and for meeting reminders.
    func updateCalendar(settings: AppSettings) {
        if settings.showCalendar || settings.showMeetingReminders {
            calendar.start()
        } else {
            calendar.stop()
        }
        if !settings.showMeetingReminders { center.remove(id: ActivityID.meeting) }
    }

    func updateInputSource(settings: AppSettings) {
        if settings.showInputSource { inputSource.start() } else { inputSource.stop() }
    }

    /// Bluetooth is asked for only while the headphones activity is on.
    func updateHeadphones(settings: AppSettings) {
        if settings.showHeadphones {
            headphones.start()
        } else {
            headphones.stop()
            center.remove(id: ActivityID.headphones)
        }
    }

    /// Developer menu: AirPods Pro connecting, then their battery a moment later, like the real
    /// thing.
    func simulateHeadphones() {
        let event = HeadphonesEvent(name: "AirPods Pro", address: "", isConnected: true)
        showHeadphones(event)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            var withBattery = event
            withBattery.battery = HeadphonesBattery(left: 80, right: 75, case: 60)
            self?.showHeadphones(withBattery)
        }
    }

    /// Shown after a quick capture is saved.
    func showCaptureSaved() {
        guard settings.showCaptureConfirmation else { return }
        center.postTransient(id: ActivityID.captureSaved, kind: .captureSaved, duration: Self.captureSavedActivityDuration, priority: .confirmation)
    }

    /// Developer menu: plays the low battery warning without draining the battery.
    func simulateLowBattery() {
        showLowBattery(level: 10)
    }

    private func showMeeting(_ event: CalendarEventSnapshot, _ moment: MeetingReminder.Moment) {
        guard settings.showMeetingReminders else { return }
        meetingEvent = event
        meetingMoment = moment
        center.postTransient(id: ActivityID.meeting, kind: .meeting, duration: Self.meetingActivityDuration, priority: .meeting)
        playHaptic()
    }

    private func checkLowBattery(_ state: PowerState) {
        guard let threshold = lowBatteryWarnings.check(state), settings.showLowBattery else { return }
        logger.notice("Low battery warning at \(threshold, privacy: .public)%")
        showLowBattery(level: state.level)
    }

    private func showLowBattery(level: Int) {
        lowBatteryLevel = level
        center.postTransient(id: ActivityID.lowBattery, kind: .lowBattery, duration: Self.lowBatteryActivityDuration, priority: .lowBattery)
        playHaptic()
    }

    private func showHeadphones(_ event: HeadphonesEvent) {
        guard settings.showHeadphones else { return }
        let date = Date()
        if event.isConnected, event.battery != nil {
            // The battery comes in after the connection; late readings would just repeat it.
            guard let connectedAt = headphonesConnectedAt,
                  date.timeIntervalSince(connectedAt) < Self.headphonesBatteryWindow,
                  headphonesEvent?.address == event.address else { return }
        } else {
            headphonesConnectedAt = event.isConnected ? date : nil
        }
        headphonesEvent = event
        center.postTransient(id: ActivityID.headphones, kind: .headphones, duration: Self.headphonesActivityDuration, priority: .confirmation)
    }

    private func showInputSource(_ label: String) {
        inputSourceLabel = label
        center.postTransient(id: ActivityID.inputSource, kind: .inputSource, duration: Self.inputSourceActivityDuration, priority: .inputSource)
    }

    private func playHaptic() {
        guard settings.hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    /// Developer menu: plays the charging activity without a cable.
    func simulateCharging() {
        let level = power.state?.level ?? 80
        logger.notice("Simulated charger connected at \(level, privacy: .public)%")
        showCharging(level: level)
    }

    private func handle(_ event: PowerEvent) {
        logger.notice("Power event: \(String(describing: event), privacy: .public)")
        switch event {
        case .connected(let level):
            showCharging(level: level)
        case .fullyCharged:
            showCharging(level: 100)
        case .disconnected:
            center.remove(id: ActivityID.charging)
        }
    }

    private func showCharging(level: Int) {
        guard settings.showCharging else { return }
        chargingLevel = level
        center.postTransient(id: ActivityID.charging, kind: .charging, duration: Self.chargingActivityDuration, priority: .charging)
        playHaptic()
    }
}

/// One live activity per id; posting again updates it in place.
nonisolated enum ActivityID {
    static let charging = "charging"
    static let lowBattery = "low-battery"
    static let meeting = "meeting"
    static let inputSource = "input-source"
    static let captureSaved = "capture-saved"
    static let headphones = "headphones"
}

extension Logger {
    /// Power source snapshots and charger events. In Console, filter by subsystem
    /// `io.github.dtem4ik.meniscus` and category `power`.
    nonisolated static let power = Logger(subsystem: "io.github.dtem4ik.meniscus", category: "power")
}
