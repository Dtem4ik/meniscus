import AppKit
import Observation
import OSLog

/// The long-lived sources of live data. Created once by the app delegate.
@Observable
final class ActivityServices {
    static let shared = ActivityServices()

    let center: ActivityCenter
    /// Notices and tasks from other apps, scripts and Shortcuts.
    let external: ExternalNotices
    let apiServer = APIServer()
    let power = PowerSourceMonitor()
    let calendar = CalendarService()
    let nowPlaying = NowPlayingService()
    let inputSource = InputSourceMonitor()
    let presentation = PresentationGuard()
    let audioDevices = AudioDeviceMonitor()
    let hidDevices = HIDDeviceMonitor()
    let bleBattery = BLEBatteryMonitor()

    /// Battery level shown by the charging activity.
    private(set) var chargingLevel: Int?
    /// Battery level shown by the low battery warning.
    private(set) var lowBatteryLevel: Int?
    /// Short name of the keyboard input source just switched to, like EN or РУ.
    private(set) var inputSourceLabel: String?
    /// The event the meeting reminder is about, and whether it is about to start or starting.
    private(set) var meetingEvent: CalendarEventSnapshot?
    private(set) var meetingMoment: MeetingReminder.Moment = .soon
    /// The third-party Bluetooth device that just connected or disconnected.
    private(set) var bluetoothDevice: (device: BluetoothDevice, isConnected: Bool)?
    /// The Bluetooth device whose battery is low, with the level in `battery.main`.
    private(set) var deviceLowBattery: BluetoothDevice?
    /// The track the track change banner shows.
    private(set) var trackBanner: TrackBanner?
    /// Whether the island is open; a track change then shows nothing. Set by the window
    /// controller.
    @ObservationIgnored var isIslandExpanded: () -> Bool = { false }

    /// How long the charging activity stays in the notch after the charger is connected.
    static let chargingActivityDuration: TimeInterval = 4
    static let lowBatteryActivityDuration: TimeInterval = 4
    static let inputSourceActivityDuration: TimeInterval = 1.2
    static let captureSavedActivityDuration: TimeInterval = 1.6
    static let meetingActivityDuration: TimeInterval = 5
    /// How long a mini banner stays before the island folds back.
    static let bannerDuration: TimeInterval = 3
    /// A new track's artwork often comes a moment after it; the banner waits this long for it.
    static let trackArtworkWait: Duration = .milliseconds(600)

    @ObservationIgnored private let logger = Logger.power
    @ObservationIgnored private var lowBatteryWarnings = LowBatteryWarnings()
    @ObservationIgnored private var settings: AppSettings = .shared
    @ObservationIgnored private var deviceBatteryWarnings = DeviceBatteryWarnings()
    @ObservationIgnored private var trackChanges = TrackChangeDetector()
    @ObservationIgnored private var pendingTrack: TrackBanner?
    @ObservationIgnored private var pendingTrackTask: Task<Void, Never>?
    /// Connected devices by name, for battery levels that arrive by name (CoreBluetooth).
    @ObservationIgnored private var connectedDevices: [String: BluetoothDevice] = [:]

    init() {
        let center = ActivityCenter()
        self.center = center
        external = ExternalNotices(center: center)
        // Wired here rather than in start(), so the Developer simulations (and tests) work too.
        calendar.onMeetingMoment = { [weak self] event, moment in self?.showMeeting(event, moment) }
        audioDevices.onEvent = { [weak self] event in self?.handle(event) }
        hidDevices.onEvent = { [weak self] event in self?.handle(event) }
        audioDevices.ble = bleBattery
        hidDevices.ble = bleBattery
        bleBattery.onLevel = { [weak self] name, level in self?.bleLevelArrived(name: name, level: level) }
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
        updateBluetoothDevices(settings: settings)
        presentation.start()
        apiServer.onRequest = { [weak self] incoming, source in self?.receive(incoming, from: source) }
        updateExternalAPI(settings: settings)

        nowPlaying.onChange = { [weak self] info in
            guard let self else { return }
            if let info, info.isPlaying {
                center.post(LiveActivity(id: "now-playing", kind: .nowPlaying, priority: .ongoing, updatedAt: Date(), expiresAt: nil))
            } else {
                center.remove(id: "now-playing")
            }
            // Followed even with the banner off, so turning it on doesn't announce an old track.
            if trackChanges.check(info), let info {
                trackChanged(TrackBanner(title: info.title, artist: info.artist))
            }
        }
        nowPlaying.onArtworkChange = { [weak self] image in self?.artworkChanged(image) }
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

    /// Bluetooth devices are watched only while one of their activities is on.
    func updateBluetoothDevices(settings: AppSettings) {
        if settings.showBluetoothDevices || settings.showDeviceLowBattery {
            bleBattery.start()
            audioDevices.start()
            hidDevices.start()
        } else {
            audioDevices.stop()
            hidDevices.stop()
            bleBattery.stop()
            connectedDevices.removeAll()
        }
        if !settings.showBluetoothDevices { center.remove(id: ActivityID.bluetoothDevice) }
        if !settings.showDeviceLowBattery { center.remove(id: ActivityID.deviceLowBattery) }
    }

    /// Developer menu: a mouse connecting, its battery a moment later, like the real thing.
    func simulateBluetoothDevice() {
        handle(.connected(Self.simulatedMouse))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.simulatedBatteryArrived(level: 64)
        }
    }

    /// The simulated mouse's battery, as if it was read after the connection.
    func simulatedBatteryArrived(level: Int) {
        var device = Self.simulatedMouse
        device.battery = DeviceBattery(main: level)
        handle(.battery(device))
    }

    private static var simulatedMouse: BluetoothDevice {
        BluetoothDevice(id: "simulated-mouse", name: String(localized: "Wireless Mouse"), kind: .mouse)
    }

    /// Developer menu: every battery value each source reports, per device, for the clipboard.
    func copyBluetoothDiagnostics() {
        Task {
            let report = await BluetoothDiagnostics.report(ble: bleBattery)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
            Logger.bluetooth.notice("Bluetooth diagnostics copied")
        }
    }

    /// Developer menu: a keyboard warning about its battery.
    func simulateDeviceLowBattery() {
        showDeviceLowBattery(BluetoothDevice(id: "simulated-keyboard", name: String(localized: "Wireless Keyboard"), kind: .keyboard), level: 10)
    }

    /// Developer menu: a track change, as if a song just started. Pressing it again while the
    /// banner is up shows how quick skips update it in place.
    func simulateTrackChange() {
        let number = (trackBanner?.title.split(separator: " ").last.flatMap { Int($0) } ?? 0) + 1
        showTrackBanner(TrackBanner(title: String(localized: "Simulated Track \(number)"), artist: "Meniscus"))
    }

    private var isShowingTrackBanner: Bool {
        center.current?.id == ActivityID.trackChange
    }

    private func trackChanged(_ track: TrackBanner) {
        guard settings.showTrackChange, !isIslandExpanded() else { return }
        if isShowingTrackBanner {
            // Quick skips: the banner stays and takes the new track; its artwork follows.
            pendingTrackTask?.cancel()
            pendingTrack = nil
            showTrackBanner(track)
            return
        }
        pendingTrack = track
        pendingTrackTask?.cancel()
        pendingTrackTask = Task { [weak self] in
            try? await Task.sleep(for: Self.trackArtworkWait)
            guard !Task.isCancelled, let self else { return }
            // No new artwork came: the new track shares the old one (same album), or has none.
            self.showPendingTrack(artwork: self.nowPlaying.artwork)
        }
    }

    private func artworkChanged(_ image: NSImage?) {
        if pendingTrack != nil {
            showPendingTrack(artwork: image)
        } else if isShowingTrackBanner {
            trackBanner?.artwork = image
        }
    }

    private func showPendingTrack(artwork: NSImage?) {
        pendingTrackTask?.cancel()
        pendingTrackTask = nil
        guard var track = pendingTrack else { return }
        pendingTrack = nil
        guard !isIslandExpanded() else { return }
        track.artwork = artwork
        showTrackBanner(track)
    }

    /// Posting again with the same id updates the banner in place and restarts its time, so
    /// quick skips don't make it close and reopen.
    private func showTrackBanner(_ track: TrackBanner) {
        trackBanner = track
        center.postTransient(id: ActivityID.trackChange, kind: .trackChange, duration: Self.bannerDuration, priority: .confirmation)
    }

    /// The command line tool's socket is open only while its switch is on.
    func updateExternalAPI(settings: AppSettings) {
        if settings.externalCLI { apiServer.start() } else { apiServer.stop() }
    }

    private func receive(_ incoming: APIServer.Incoming, from source: APISource) {
        switch incoming {
        case .request(let request):
            external.handle(request, from: source)
        case .hook(_, let event, let at):
            external.handleClaudeCode(event, at: at, from: source)
        }
    }

    /// Shown after a quick capture is saved.
    func showCaptureSaved() {
        guard settings.showCaptureConfirmation else { return }
        center.postTransient(id: ActivityID.captureSaved, kind: .captureSaved, duration: Self.captureSavedActivityDuration, priority: .directFeedback)
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

    private func handle(_ event: BluetoothDeviceEvent) {
        switch event {
        case .connected(let device):
            connectedDevices[device.name] = device
            // A device that just connected may offer the Battery Service.
            bleBattery.refresh()
            showBluetoothDevice(device, isConnected: true)
            checkDeviceBattery(device)
        case .disconnected(let device):
            connectedDevices[device.name] = nil
            showBluetoothDevice(device, isConnected: false)
        case .battery(let device):
            connectedDevices[device.name] = device
            // Fills in the ring while the banner is still up; never brings it back.
            if isShowingBanner(for: device) {
                bluetoothDevice = (device, true)
            }
            checkDeviceBattery(device)
        }
    }

    /// CoreBluetooth reports by name, when the device sends its level.
    private func bleLevelArrived(name: String, level: Int) {
        let known = connectedDevices[name] ?? connectedDevices.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        guard var device = known, device.battery?.lowest != level else { return }
        device.battery = DeviceBattery(main: level)
        handle(.battery(device))
    }

    private func isShowingBanner(for device: BluetoothDevice) -> Bool {
        center.current?.id == ActivityID.bluetoothDevice
            && bluetoothDevice?.device.id == device.id
            && bluetoothDevice?.isConnected == true
    }

    private func showBluetoothDevice(_ device: BluetoothDevice, isConnected: Bool) {
        Logger.bluetooth.notice("\(device.kind.rawValue, privacy: .public) \(isConnected ? "connected" : "disconnected", privacy: .public), battery \(device.battery?.lowest.map(String.init) ?? "unknown", privacy: .public)")
        guard settings.showBluetoothDevices else { return }
        bluetoothDevice = (device, isConnected)
        center.postTransient(id: ActivityID.bluetoothDevice, kind: .bluetoothDevice, duration: Self.bannerDuration, priority: .directFeedback)
    }

    private func checkDeviceBattery(_ device: BluetoothDevice) {
        guard let level = device.battery?.lowest,
              deviceBatteryWarnings.check(device: device.id, level: level) != nil,
              settings.showDeviceLowBattery else { return }
        logger.notice("Low battery warning for a Bluetooth device at \(level, privacy: .public)%")
        showDeviceLowBattery(device, level: level)
    }

    private func showDeviceLowBattery(_ device: BluetoothDevice, level: Int) {
        var device = device
        device.battery = DeviceBattery(main: level)
        deviceLowBattery = device
        center.postTransient(id: ActivityID.deviceLowBattery, kind: .deviceLowBattery, duration: Self.lowBatteryActivityDuration, priority: .deviceLowBattery)
        playHaptic()
    }

    private func showInputSource(_ label: String) {
        inputSourceLabel = label
        center.postTransient(id: ActivityID.inputSource, kind: .inputSource, duration: Self.inputSourceActivityDuration, priority: .directFeedback)
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
    static let bluetoothDevice = "bluetooth-device"
    static let deviceLowBattery = "device-low-battery"
    static let trackChange = "track-change"
}

extension Logger {
    /// Power source snapshots and charger events. In Console, filter by subsystem
    /// `io.github.dtem4ik.meniscus` and category `power`.
    nonisolated static let power = Logger(subsystem: "io.github.dtem4ik.meniscus", category: "power")
}
