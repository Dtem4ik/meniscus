import Foundation

/// Reads battery levels from `system_profiler SPBluetoothDataType -json`, a public tool that
/// prints what System Information shows. Run once per headphones connection, never polled.
nonisolated enum AudioBatteryReader {
    static let toolURL = URL(filePath: "/usr/sbin/system_profiler")
    /// The tool is stopped if it takes longer; the activity then keeps showing the name.
    static let timeout: TimeInterval = 6

    @concurrent
    static func read(address: String, name: String) async -> DeviceBattery? {
        guard let data = await run() else { return nil }
        return parse(data, address: address, name: name)
    }

    /// Finds the device by address (or by name when the address is missing) and reads its
    /// battery keys. Pure, so it is unit tested with a sample of the tool's output.
    static func parse(_ data: Data, address: String, name: String) -> DeviceBattery? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let wanted = normalized(address)
        var byName: [String: Any]?
        var found: [String: Any]?
        visitDevices(in: root) { deviceName, info in
            if let deviceAddress = info["device_address"] as? String, normalized(deviceAddress) == wanted {
                found = info
            } else if deviceName == name, byName == nil {
                byName = info
            }
        }
        guard let info = found ?? byName else { return nil }
        let battery = DeviceBattery(
            left: level(info["device_batteryLevelLeft"]),
            right: level(info["device_batteryLevelRight"]),
            case: level(info["device_batteryLevelCase"]),
            main: level(info["device_batteryLevelMain"])
        )
        return battery.isEmpty ? nil : battery
    }

    /// Devices appear as one-key dictionaries, `{ "AirPods Pro": { ... } }`, inside lists.
    private static func visitDevices(in value: Any, _ visit: (String, [String: Any]) -> Void) {
        if let list = value as? [Any] {
            list.forEach { visitDevices(in: $0, visit) }
        } else if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                if let info = child as? [String: Any], info["device_address"] != nil || info["device_minorType"] != nil {
                    visit(key, info)
                } else {
                    visitDevices(in: child, visit)
                }
            }
        }
    }

    /// "80%" → 80.
    static func level(_ value: Any?) -> Int? {
        guard let text = value as? String else { return nil }
        let digits = text.filter(\.isNumber)
        guard let number = Int(digits), (0...100).contains(number) else { return nil }
        return number
    }

    static func normalized(_ address: String) -> String {
        address.uppercased().filter { $0.isHexDigit }
    }

    private static func run() async -> Data? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = toolURL
        process.arguments = ["SPBluetoothDataType", "-json"]
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let running = process
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if running.isRunning { running.terminate() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
