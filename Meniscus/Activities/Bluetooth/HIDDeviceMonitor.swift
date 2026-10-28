import AppKit
import IOKit
import IOKit.hid
import OSLog

/// Bluetooth mice, keyboards and gamepads (classic and Low Energy), from IOKit's matching
/// notifications for HID devices. Only reads the registry: no device is opened, so no Input
/// Monitoring permission is needed.
///
/// The battery is the `BatteryPercent` the HID driver publishes, read when the device connects,
/// when it tells IOKit something changed, and after the Mac wakes. Nothing polls.
final class HIDDeviceMonitor {
    var onEvent: ((BluetoothDeviceEvent) -> Void)?

    private var port: IONotificationPortRef?
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    /// Connected HID services by registry entry ID; one device often has several (keyboard and
    /// media keys, say).
    private var services: [UInt64: Service] = [:]
    private var wakeObserver: (any NSObjectProtocol)?
    private var isBaseline = false

    /// `kIOMessageServicePropertyChange`, a C macro Swift doesn't import.
    nonisolated static let servicePropertyChange: UInt32 = 0xE000_000A

    private struct Service {
        var device: BluetoothDevice
        var entry: io_object_t
        var interest: io_object_t
    }

    func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        let context = Unmanaged.passUnretained(self).toOpaque()

        // The devices connected now are the baseline: tracked for their battery, not announced.
        isBaseline = true
        if IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching(kIOHIDDeviceKey), hidMatched, context, &matchedIterator) == KERN_SUCCESS {
            drain(matchedIterator, matched: true)
        }
        if IOServiceAddMatchingNotification(port, kIOTerminatedNotification, IOServiceMatching(kIOHIDDeviceKey), hidTerminated, context, &terminatedIterator) == KERN_SUCCESS {
            drain(terminatedIterator, matched: false)
        }
        isBaseline = false

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainThread.run { self?.refreshBatteries() }
        }
    }

    func stop() {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        for service in services.values { release(service) }
        services.removeAll()
        for iterator in [matchedIterator, terminatedIterator] where iterator != 0 { IOObjectRelease(iterator) }
        matchedIterator = 0
        terminatedIterator = 0
        if let port { IONotificationPortDestroy(port) }
        port = nil
    }

    /// Reads every service the iterator holds; this also re-arms the notification.
    fileprivate func drain(_ iterator: io_iterator_t, matched: Bool) {
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            if matched {
                add(entry)
            } else {
                remove(entry)
                IOObjectRelease(entry)
            }
        }
    }

    private func add(_ entry: io_object_t) {
        guard let info = HIDServiceInfo(entry), let device = info.device else {
            IOObjectRelease(entry)
            return
        }
        let id = Self.entryID(entry)
        let isNewDevice = !services.values.contains { $0.device.id == device.id }
        var interest: io_object_t = 0
        if let port {
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOServiceAddInterestNotification(port, entry, kIOGeneralInterest, hidChanged, context, &interest)
        }
        services[id] = Service(device: device, entry: entry, interest: interest)
        guard isNewDevice else { return }
        if isBaseline {
            // Not news, but a low battery still is.
            if device.battery != nil { onEvent?(.battery(device)) }
        } else {
            Logger.bluetooth.notice("IOKit BatteryPercent at connection for \(device.kind.rawValue, privacy: .public): \(device.battery?.main.map(String.init) ?? "none", privacy: .public)")
            onEvent?(.connected(device))
            if device.battery == nil { readBatteryUntilFound(device, entryID: id) }
        }
    }

    private func remove(_ entry: io_object_t) {
        let id = Self.entryID(entry)
        guard let service = services.removeValue(forKey: id) else { return }
        release(service)
        // The device is gone when its last service is.
        if !services.values.contains(where: { $0.device.id == service.device.id }) {
            onEvent?(.disconnected(service.device))
        }
    }

    fileprivate func serviceChanged(_ entry: io_object_t) {
        serviceChanged(id: Self.entryID(entry))
    }

    private func serviceChanged(id: UInt64) {
        guard var service = services[id], let level = HIDServiceInfo.batteryPercent(of: service.entry) else { return }
        guard level != service.device.battery?.main else { return }
        service.device.battery = DeviceBattery(main: level)
        services[id] = service
        onEvent?(.battery(service.device))
    }

    /// Low Energy devices often publish their battery a few seconds after they connect, and some
    /// only through Bluetooth's own report: tries the registry, then `system_profiler`, on the
    /// retry schedule until one has it.
    private func readBatteryUntilFound(_ device: BluetoothDevice, entryID: UInt64) {
        Task { [weak self] in
            let start = ContinuousClock.now
            for delay in BatteryRetry.delays {
                try? await Task.sleep(until: start + delay)
                guard let self, let service = self.services[entryID] else { return }
                if let level = HIDServiceInfo.batteryPercent(of: service.entry) {
                    Logger.bluetooth.notice("IOKit BatteryPercent after \(delay, privacy: .public) for \(device.kind.rawValue, privacy: .public): \(level, privacy: .public)")
                    self.report(level, entryID: entryID)
                    return
                }
                Logger.bluetooth.notice("IOKit BatteryPercent after \(delay, privacy: .public) for \(device.kind.rawValue, privacy: .public): none")
                let battery = await SystemProfilerBattery.read(address: device.id, name: device.name)
                Logger.bluetooth.notice("system_profiler after \(delay, privacy: .public) for \(device.kind.rawValue, privacy: .public): \(battery.map { String(describing: $0) } ?? "no battery", privacy: .public)")
                if let level = battery?.lowest {
                    self.report(level, entryID: entryID)
                    return
                }
            }
        }
    }

    private func report(_ level: Int, entryID: UInt64) {
        guard var service = services[entryID] else { return }
        service.device.battery = DeviceBattery(main: level)
        services[entryID] = service
        onEvent?(.battery(service.device))
    }

    private func refreshBatteries() {
        var reported = Set<String>()
        for (id, var service) in services {
            guard let level = HIDServiceInfo.batteryPercent(of: service.entry) else { continue }
            service.device.battery = DeviceBattery(main: level)
            services[id] = service
            if reported.insert(service.device.id).inserted { onEvent?(.battery(service.device)) }
        }
    }

    private func release(_ service: Service) {
        if service.interest != 0 { IOObjectRelease(service.interest) }
        IOObjectRelease(service.entry)
    }

    private static func entryID(_ entry: io_object_t) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(entry, &id)
        return id
    }
}

/// IOKit calls these on the main queue (set on the port), but they are C callbacks: they check
/// and hand over to the main actor rather than assume it.
private nonisolated func hidMatched(_ context: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
    guard let context else { return }
    let address = Int(bitPattern: context)
    MainThread.run {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<HIDDeviceMonitor>.fromOpaque(pointer).takeUnretainedValue().drain(iterator, matched: true)
    }
}

private nonisolated func hidTerminated(_ context: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
    guard let context else { return }
    let address = Int(bitPattern: context)
    MainThread.run {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<HIDDeviceMonitor>.fromOpaque(pointer).takeUnretainedValue().drain(iterator, matched: false)
    }
}

private nonisolated func hidChanged(_ context: UnsafeMutableRawPointer?, _ service: io_service_t, _ messageType: UInt32, _ argument: UnsafeMutableRawPointer?) {
    guard let context, messageType == HIDDeviceMonitor.servicePropertyChange else { return }
    let address = Int(bitPattern: context)
    IOObjectRetain(service)
    MainThread.run {
        defer { IOObjectRelease(service) }
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<HIDDeviceMonitor>.fromOpaque(pointer).takeUnretainedValue().serviceChanged(service)
    }
}

/// The registry properties of one HID service.
nonisolated struct HIDServiceInfo: Equatable, Sendable {
    var transport: String
    var name: String
    var vendorID: Int?
    var vendorIDSource: Int?
    var usagePage: Int
    var usage: Int
    var address: String?
    var battery: Int?

    init(transport: String, name: String, vendorID: Int?, vendorIDSource: Int?, usagePage: Int, usage: Int, address: String?, battery: Int?) {
        self.transport = transport
        self.name = name
        self.vendorID = vendorID
        self.vendorIDSource = vendorIDSource
        self.usagePage = usagePage
        self.usage = usage
        self.address = address
        self.battery = battery
    }

    init?(_ entry: io_object_t) {
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        guard let transport = property(kIOHIDTransportKey) as? String else { return nil }
        self.init(
            transport: transport,
            name: property(kIOHIDProductKey) as? String ?? "",
            vendorID: (property(kIOHIDVendorIDKey) as? NSNumber)?.intValue,
            vendorIDSource: (property(kIOHIDVendorIDSourceKey) as? NSNumber)?.intValue,
            usagePage: (property(kIOHIDPrimaryUsagePageKey) as? NSNumber)?.intValue ?? 0,
            usage: (property(kIOHIDPrimaryUsageKey) as? NSNumber)?.intValue ?? 0,
            address: (property("DeviceAddress") as? String) ?? (property(kIOHIDSerialNumberKey) as? String),
            battery: Self.batteryPercent(of: entry)
        )
    }

    /// The device as the island shows it, or `nil` for anything that isn't a third-party
    /// Bluetooth mouse, keyboard or gamepad.
    var device: BluetoothDevice? {
        guard transport.lowercased().contains("bluetooth"), let kind else { return nil }
        guard !AppleDevice.isApple(vendorID: vendorID, source: vendorIDSource), !AppleDevice.hasAppleName(name) else {
            return nil
        }
        let id = address.map(SystemProfilerBattery.normalized).flatMap { $0.isEmpty ? nil : $0 } ?? name
        return BluetoothDevice(id: id, name: name, kind: kind, battery: battery.map { DeviceBattery(main: $0) })
    }

    /// Generic Desktop (page 1): pointer and mouse, keyboard and keypad, joystick, gamepad and
    /// multi-axis controller. Other services of the same device (media keys, vendor pages) are
    /// skipped.
    var kind: BluetoothDevice.Kind? {
        guard usagePage == 0x01 else { return nil }
        switch usage {
        case 0x01, 0x02: return .mouse
        case 0x06, 0x07: return .keyboard
        case 0x04, 0x05, 0x08: return .gamepad
        default: return nil
        }
    }

    /// `BatteryPercent` on the service, a driver below it or the device above it.
    static func batteryPercent(of entry: io_object_t) -> Int? {
        let key = "BatteryPercent" as CFString
        for options in [IOOptionBits(kIORegistryIterateRecursively), IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)] {
            if let value = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key, kCFAllocatorDefault, options) as? NSNumber,
               (0...100).contains(value.intValue) {
                return value.intValue
            }
        }
        return nil
    }
}
