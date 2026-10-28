import CoreBluetooth
import Foundation
import OSLog

/// Battery of Bluetooth Low Energy devices from their standard GATT Battery Service (0x180F,
/// Battery Level 0x2A19), through public CoreBluetooth. The devices are already connected to the
/// Mac; Meniscus only joins that connection, reads the level once and subscribes to changes, so
/// the level arrives when the device reports it. Nothing polls.
///
/// CoreBluetooth calls back on this monitor's own queue; all its state lives there. Levels are
/// handed to the main actor by device name.
nonisolated final class BLEBatteryMonitor: NSObject, @unchecked Sendable {
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")

    /// Called on the main actor with the device's name and level.
    var onLevel: (@MainActor @Sendable (String, Int) -> Void)? {
        get { queue.sync { _onLevel } }
        set { queue.sync { _onLevel = newValue } }
    }

    private let queue = DispatchQueue(label: "io.github.dtem4ik.meniscus.ble-battery")
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var levels: [UUID: (name: String, level: Int)] = [:]
    private var notes: [UUID: String] = [:]
    private var _onLevel: (@MainActor @Sendable (String, Int) -> Void)?

    func start() {
        queue.async { [self] in
            guard central == nil else { return }
            central = CBCentralManager(delegate: self, queue: queue)
        }
    }

    func stop() {
        queue.async { [self] in
            for peripheral in peripherals.values { central?.cancelPeripheralConnection(peripheral) }
            peripherals.removeAll()
            levels.removeAll()
            notes.removeAll()
            central = nil
        }
    }

    /// Looks for connected devices with a Battery Service; call when a device connects.
    func refresh() {
        queue.async { [self] in attachConnectedPeripherals() }
    }

    /// The last level a device with this name reported, if any.
    func level(named name: String) -> Int? {
        queue.sync { levels.values.first { $0.name == name }?.level }
    }

    /// For the diagnostics: CoreBluetooth's state and every device it found, after giving them
    /// `wait` to answer.
    func diagnosticLines(wait: Duration = .seconds(3)) async -> [String] {
        refresh()
        try? await Task.sleep(for: wait)
        return queue.sync {
            var lines = ["state \(stateName(central?.state)), authorization \(authorizationName(CBManager.authorization))"]
            if peripherals.isEmpty { lines.append("(no connected device offers the Battery Service)") }
            for (id, peripheral) in peripherals {
                let level = levels[id].map { "\($0.level)%" } ?? "no level yet"
                let note = notes[id].map { ", \($0)" } ?? ""
                lines.append("\(peripheral.name ?? "?"): \(level)\(note), id …\(id.uuidString.suffix(4))")
            }
            return lines
        }
    }

    private func attachConnectedPeripherals() {
        guard let central, central.state == .poweredOn else { return }
        for peripheral in central.retrieveConnectedPeripherals(withServices: [Self.batteryService]) {
            guard peripherals[peripheral.identifier] == nil else { continue }
            peripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            central.connect(peripheral)
        }
    }

    private func report(_ peripheral: CBPeripheral, level: Int) {
        let name = peripheral.name ?? ""
        levels[peripheral.identifier] = (name, level)
        Logger.bluetooth.notice("CoreBluetooth Battery Level: \(level, privacy: .public)%")
        guard !name.isEmpty, let onLevel = _onLevel else { return }
        MainThread.run { onLevel(name, level) }
    }

    private func stateName(_ state: CBManagerState?) -> String {
        switch state {
        case .poweredOn: "on"
        case .poweredOff: "off"
        case .unauthorized: "unauthorized"
        case .unsupported: "unsupported"
        case .resetting: "resetting"
        case .unknown, .none: "unknown"
        @unknown default: "other"
        }
    }

    private func authorizationName(_ authorization: CBManagerAuthorization) -> String {
        switch authorization {
        case .allowedAlways: "allowed"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "not asked yet"
        @unknown default: "other"
        }
    }
}

extension BLEBatteryMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Logger.bluetooth.notice("CoreBluetooth state: \(self.stateName(central.state), privacy: .public)")
        if central.state == .poweredOn {
            attachConnectedPeripherals()
        } else {
            peripherals.removeAll()
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        notes[peripheral.identifier] = "couldn't join the connection: \(error?.localizedDescription ?? "unknown error")"
        peripherals[peripheral.identifier] = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        peripherals[peripheral.identifier] = nil
        levels[peripheral.identifier] = nil
    }
}

extension BLEBatteryMonitor: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) else {
            notes[peripheral.identifier] = "no Battery Service: \(error?.localizedDescription ?? "not offered to apps")"
            return
        }
        peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.batteryLevel }) else {
            notes[peripheral.identifier] = "no Battery Level: \(error?.localizedDescription ?? "not offered")"
            return
        }
        peripheral.readValue(for: characteristic)
        if characteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard characteristic.uuid == Self.batteryLevel else { return }
        guard error == nil, let byte = characteristic.value?.first, byte <= 100 else {
            notes[peripheral.identifier] = "reading failed: \(error?.localizedDescription ?? "no value")"
            return
        }
        report(peripheral, level: Int(byte))
    }
}
