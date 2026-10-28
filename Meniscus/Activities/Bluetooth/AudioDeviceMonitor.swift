import Foundation
import IOBluetooth

/// Bluetooth headphones and speakers connecting and disconnecting, through IOBluetooth's public
/// notifications. Mice, keyboards and gamepads come from `HIDDeviceMonitor` instead.
///
/// IOBluetooth calls back on its own background queue (on macOS 27 at least), so the callbacks
/// are nonisolated: they read what they need from the device there and hand it to the main actor.
final class AudioDeviceMonitor: NSObject {
    var onEvent: ((BluetoothDeviceEvent) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private let disconnectNotifications = NotificationBag()
    /// IOBluetooth reports every device already connected right after registering; those aren't
    /// news.
    private var announcesAfter = Date.distantFuture
    private var batteryTasks: [String: Task<Void, Never>] = [:]

    /// The Bluetooth major class of audio devices.
    nonisolated static let audioMajorClass: UInt32 = 0x04
    /// The battery shows up in the system's report a moment after the connection.
    static let batteryDelay: Duration = .seconds(1)

    func start() {
        guard connectNotification == nil else { return }
        announcesAfter = Date().addingTimeInterval(1)
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.removeAll()
        batteryTasks.values.forEach { $0.cancel() }
        batteryTasks.removeAll()
    }

    @objc nonisolated private func deviceConnected(_ notification: IOBluetoothUserNotification?, device: IOBluetoothDevice?) {
        guard let device, let found = Self.audioDevice(device) else { return }
        disconnectNotifications.set(
            device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:))),
            for: found.id
        )
        MainThread.run { [weak self] in self?.connected(found) }
    }

    @objc nonisolated private func deviceDisconnected(_ notification: IOBluetoothUserNotification?, device: IOBluetoothDevice?) {
        notification?.unregister()
        guard let device, let found = Self.audioDevice(device) else { return }
        disconnectNotifications.remove(found.id)
        MainThread.run { [weak self] in self?.disconnected(found) }
    }

    private func connected(_ device: BluetoothDevice) {
        guard Date() >= announcesAfter else { return }
        onEvent?(.connected(device))

        batteryTasks[device.id]?.cancel()
        batteryTasks[device.id] = Task { [weak self] in
            try? await Task.sleep(for: Self.batteryDelay)
            guard !Task.isCancelled else { return }
            let battery = await AudioBatteryReader.read(address: device.id, name: device.name)
            guard !Task.isCancelled, let battery, let self else { return }
            var reported = device
            reported.battery = battery
            self.onEvent?(.battery(reported))
        }
    }

    private func disconnected(_ device: BluetoothDevice) {
        batteryTasks[device.id]?.cancel()
        batteryTasks[device.id] = nil
        guard Date() >= announcesAfter else { return }
        onEvent?(.disconnected(device))
    }

    /// The device as the island shows it, or `nil` for anything that isn't third-party audio.
    nonisolated private static func audioDevice(_ device: IOBluetoothDevice) -> BluetoothDevice? {
        guard device.deviceClassMajor == audioMajorClass else { return nil }
        let name = device.name ?? ""
        let vendor = vendorID(of: device)
        guard !AppleDevice.isApple(vendorID: vendor.id, source: vendor.source), !AppleDevice.hasAppleName(name) else {
            return nil
        }
        let address = device.addressString ?? ""
        return BluetoothDevice(
            id: address.isEmpty ? name : address,
            name: name,
            kind: audioKind(minorClass: device.deviceClassMinor)
        )
    }

    /// Loudspeakers (5) and hi-fi audio (10) are speakers; everything else in the audio class is
    /// worn.
    nonisolated static func audioKind(minorClass: UInt32) -> BluetoothDevice.Kind {
        [0x05, 0x0A].contains(minorClass) ? .speaker : .headphones
    }

    /// The vendor from the device's Device ID record (SDP service 0x1200), when it has one cached.
    nonisolated private static func vendorID(of device: IOBluetoothDevice) -> (id: Int?, source: Int?) {
        guard let uuid = IOBluetoothSDPUUID(uuid16: 0x1200) as IOBluetoothSDPUUID?,
              let record = device.getServiceRecord(for: uuid) as IOBluetoothSDPServiceRecord? else {
            return (nil, nil)
        }
        let id = (record.getAttributeDataElement(0x0201) as IOBluetoothSDPDataElement?)?.getNumberValue()?.intValue
        let source = (record.getAttributeDataElement(0x0205) as IOBluetoothSDPDataElement?)?.getNumberValue()?.intValue
        return (id, source)
    }
}

/// Disconnect notifications by device, touched from IOBluetooth's queue and the main actor.
private nonisolated final class NotificationBag: @unchecked Sendable {
    private let lock = NSLock()
    private var notifications: [String: IOBluetoothUserNotification] = [:]

    func set(_ notification: IOBluetoothUserNotification?, for id: String) {
        let old = lock.withLock {
            let old = notifications[id]
            notifications[id] = notification
            return old
        }
        old?.unregister()
    }

    func remove(_ id: String) {
        _ = lock.withLock { notifications.removeValue(forKey: id) }
    }

    func removeAll() {
        let all = lock.withLock {
            let all = Array(notifications.values)
            notifications.removeAll()
            return all
        }
        all.forEach { $0.unregister() }
    }
}
