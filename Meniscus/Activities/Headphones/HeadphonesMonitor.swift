import Foundation
import IOBluetooth

/// Headphones that connected or disconnected, for the live activity.
nonisolated struct HeadphonesEvent: Equatable, Sendable {
    var name: String
    var address: String
    var isConnected: Bool
    /// Read once after connecting; `nil` when the system doesn't report it.
    var battery: HeadphonesBattery?

    var symbol: String { HeadphonesSymbol.name(for: name) }
}

/// Reports Bluetooth audio devices connecting and disconnecting, through IOBluetooth's public
/// connect and disconnect notifications. Event driven: nothing runs in between.
final class HeadphonesMonitor: NSObject {
    var onEvent: ((HeadphonesEvent) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    /// IOBluetooth reports every device already connected right after registering; those aren't
    /// news.
    private var acceptsConnectsAfter = Date.distantFuture
    private var batteryTasks: [String: Task<Void, Never>] = [:]

    /// The Bluetooth class of audio devices (headphones, speakers, headsets).
    private static let audioMajorClass: UInt32 = 0x04
    /// The battery shows up in the system's report a moment after the connection.
    static let batteryDelay: Duration = .seconds(1)

    func start() {
        guard connectNotification == nil else { return }
        acceptsConnectsAfter = Date().addingTimeInterval(1)
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
        batteryTasks.values.forEach { $0.cancel() }
        batteryTasks.removeAll()
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard device.deviceClassMajor == Self.audioMajorClass, let address = device.addressString else { return }
        let name = device.name ?? ""
        disconnectNotifications[address]?.unregister()
        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )
        guard Date() >= acceptsConnectsAfter else { return }
        onEvent?(HeadphonesEvent(name: name, address: address, isConnected: true))

        batteryTasks[address]?.cancel()
        batteryTasks[address] = Task { [weak self] in
            try? await Task.sleep(for: Self.batteryDelay)
            guard !Task.isCancelled else { return }
            let battery = await HeadphonesBatteryReader.read(address: address, name: name)
            guard !Task.isCancelled, let battery, let self else { return }
            self.onEvent?(HeadphonesEvent(name: name, address: address, isConnected: true, battery: battery))
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        guard let address = device.addressString else { return }
        disconnectNotifications[address] = nil
        batteryTasks[address]?.cancel()
        batteryTasks[address] = nil
        onEvent?(HeadphonesEvent(name: device.name ?? "", address: address, isConnected: false))
    }
}

/// The SF Symbol for a device, from its name.
nonisolated enum HeadphonesSymbol {
    static func name(for deviceName: String) -> String {
        let name = deviceName.lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    /// The short family name to fall back on when the full name doesn't fit.
    static func family(for deviceName: String) -> String? {
        let name = deviceName.lowercased()
        if name.contains("airpods") { return "AirPods" }
        if name.contains("beats") { return "Beats" }
        return nil
    }
}
