import Foundation

/// Reads battery levels from `system_profiler SPBluetoothDataType -json`, a public tool that
/// prints what System Information (and Control Center) shows. Run only after a device connects,
/// a few times until the battery shows up; never polled.
nonisolated enum SystemProfilerBattery {
    static let toolURL = URL(filePath: "/usr/sbin/system_profiler")
    /// The tool is stopped if it takes longer.
    static let timeout: TimeInterval = 6

    @concurrent
    static func read(address: String, name: String) async -> DeviceBattery? {
        guard let data = await report() else { return nil }
        return parse(data, address: address, name: name)
    }

    /// Finds the device by address (or by name when the address doesn't match) and reads its
    /// battery keys. Pure, so it is unit tested with a sample of the tool's output.
    static func parse(_ data: Data, address: String, name: String) -> DeviceBattery? {
        guard let info = device(in: data, address: address, name: name) else { return nil }
        let battery = battery(of: info)
        return battery.isEmpty ? nil : battery
    }

    /// Every `device_batteryLevel…` key: Left, Right and Case for earbuds, Main or no suffix for
    /// a single level.
    static func battery(of info: [String: Any]) -> DeviceBattery {
        var battery = DeviceBattery()
        for (key, value) in info where key.hasPrefix(batteryPrefix) {
            guard let level = level(value) else { continue }
            switch key.dropFirst(batteryPrefix.count).lowercased() {
            case "left": battery.left = level
            case "right": battery.right = level
            case "case": battery.case = level
            default: battery.main = battery.main ?? level
            }
        }
        return battery
    }

    /// A device in the report: under `device_connected` or `device_not_connected` (paired, not
    /// connected now).
    struct Device {
        var name: String
        var info: [String: Any]
        var isConnected: Bool
    }

    /// Each device the report lists.
    static func devices(in data: Data) -> [Device] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var devices: [Device] = []
        visitDevices(in: root, connected: nil) { devices.append(Device(name: $0, info: $1, isConnected: $2 ?? false)) }
        return devices
    }

    private static let batteryPrefix = "device_batteryLevel"

    /// Connected devices only: a paired device that isn't connected has no live level.
    private static func device(in data: Data, address: String, name: String) -> [String: Any]? {
        let wanted = normalized(address)
        let all = devices(in: data).filter(\.isConnected)
        if !wanted.isEmpty, let match = all.first(where: { normalized($0.info["device_address"] as? String ?? "") == wanted }) {
            return match.info
        }
        return name.isEmpty ? nil : all.first { $0.name == name }?.info
    }

    /// Devices appear as one-key dictionaries, `{ "Headphones": { ... } }`, in the lists under
    /// `device_connected` and `device_not_connected`.
    private static func visitDevices(in value: Any, connected: Bool?, _ visit: (String, [String: Any], Bool?) -> Void) {
        if let list = value as? [Any] {
            list.forEach { visitDevices(in: $0, connected: connected, visit) }
        } else if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                if let info = child as? [String: Any], info["device_address"] != nil || info["device_minorType"] != nil {
                    visit(key, info, connected)
                } else {
                    let section: Bool? = switch key {
                    case "device_connected": true
                    case "device_not_connected": false
                    default: connected
                    }
                    visitDevices(in: child, connected: section, visit)
                }
            }
        }
    }

    /// "80%" → 80.
    static func level(_ value: Any?) -> Int? {
        let text: String
        if let string = value as? String {
            text = string
        } else if let number = value as? NSNumber {
            text = number.stringValue
        } else {
            return nil
        }
        let digits = text.filter(\.isNumber)
        guard let number = Int(digits), (0...100).contains(number) else { return nil }
        return number
    }

    static func normalized(_ address: String) -> String {
        address.uppercased().filter { $0.isHexDigit }
    }

    /// The tool's JSON, or `nil` if it failed or timed out.
    @concurrent
    static func report() async -> Data? {
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
