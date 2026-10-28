import Foundation
import IOKit
import IOKit.hid

/// What each battery source reports, per device, as plain text for the Developer button. Read
/// only when asked. Bluetooth addresses are shortened to their last two bytes.
nonisolated enum BluetoothDiagnostics {
    @concurrent
    static func report(ble: BLEBatteryMonitor) async -> String {
        var lines = ["Meniscus Bluetooth diagnostics", ""]
        lines.append("IOKit HID devices on Bluetooth:")
        lines += hidDevices().map { "  " + $0 }
        lines.append("")
        lines.append("IOKit entries with BatteryPercent (like ioreg -r -k BatteryPercent):")
        lines += registryBatteries().map { "  " + $0 }
        lines.append("")
        lines.append("CoreBluetooth, GATT Battery Service 180F / Battery Level 2A19:")
        lines += await ble.diagnosticLines().map { "  " + $0 }
        lines.append("")
        lines.append("pmset -g accps (accessory power sources):")
        if let output = await AccessoryPowerSources.report() {
            let entries = AccessoryPowerSources.parse(output)
            lines += entries.isEmpty ? ["  (no accessories)"] : entries.map { "  \($0.name): \($0.level)%" }
        } else {
            lines.append("  (failed or timed out)")
        }
        lines.append("")
        lines.append("system_profiler SPBluetoothDataType:")
        if let data = await SystemProfilerBattery.report() {
            lines += systemProfilerLines(data).map { "  " + $0 }
        } else {
            lines.append("  (failed or timed out)")
        }
        return lines.joined(separator: "\n")
    }

    /// Connected devices with every key the tool reports for them, then paired devices that
    /// aren't connected with just their battery keys. Pure, so it is tested.
    static func systemProfilerLines(_ data: Data) -> [String] {
        let devices = SystemProfilerBattery.devices(in: data)
        guard !devices.isEmpty else { return ["(no devices)"] }
        var lines = ["Connected now:"]
        let connected = devices.filter(\.isConnected)
        lines += connected.isEmpty ? ["  (none)"] : connected.map { "  \($0.name): " + fields($0.info, all: true) }
        lines.append("Paired, not connected:")
        let paired = devices.filter { !$0.isConnected }
        lines += paired.isEmpty ? ["  (none)"] : paired.map { "  \($0.name): " + fields($0.info, all: false) }
        return lines
    }

    /// `key=value` pairs, sorted; the address masked. `all` false keeps the type and battery keys.
    private static func fields(_ info: [String: Any], all: Bool) -> String {
        let keys = info.keys.sorted().filter { all || $0.hasPrefix("device_battery") || $0 == "device_minorType" }
        let pairs = keys.map { key -> String in
            let isIdentifier = key == "device_address" || key.lowercased().contains("serial")
            let value = isIdentifier ? masked(info[key].map { value in "\(value)" }) : info[key].map { value in "\(value)" } ?? ""
            return "\(key)=\(value)"
        }
        let battery = info.keys.contains { $0.hasPrefix("device_battery") } ? "" : " (no battery keys)"
        return pairs.joined(separator: ", ") + battery
    }

    /// `aa-bb-cc-dd-ee-ff` → `…EE:FF`.
    static func masked(_ address: String?) -> String {
        let hex = SystemProfilerBattery.normalized(address ?? "")
        guard hex.count >= 4 else { return "?" }
        let tail = hex.suffix(4)
        return "…" + tail.prefix(2) + ":" + tail.suffix(2)
    }

    private static func hidDevices() -> [String] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOHIDDeviceKey), &iterator) == KERN_SUCCESS else {
            return ["(couldn't list HID devices)"]
        }
        defer { IOObjectRelease(iterator) }
        var lines: [String] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let info = HIDServiceInfo(entry), info.transport.lowercased().contains("bluetooth") else { continue }
            let shown = info.device.map { "shown as \($0.kind.rawValue)" } ?? "not shown"
            lines.append("\(info.name): transport \(info.transport), vendor \(info.vendorID.map { String(format: "0x%04X", $0) } ?? "?") (source \(info.vendorIDSource.map(String.init) ?? "?")), usage \(info.usagePage):\(info.usage), address \(masked(info.address)), BatteryPercent \(info.battery.map(String.init) ?? "none"), \(shown)")
        }
        return lines.isEmpty ? ["(none)"] : lines
    }

    private static func registryBatteries() -> [String] {
        var iterator: io_iterator_t = 0
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return ["(couldn't read the registry)"]
        }
        defer { IOObjectRelease(iterator) }
        var lines: [String] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard let battery = property("BatteryPercent") as? NSNumber else { continue }
            let className = IOObjectCopyClass(entry)?.takeRetainedValue() as String? ?? "?"
            let name = property(kIOHIDProductKey) as? String ?? property("Name") as? String ?? "?"
            let transport = property(kIOHIDTransportKey) as? String ?? "?"
            let address = property("DeviceAddress") as? String ?? property(kIOHIDSerialNumberKey) as? String
            lines.append("\(name): BatteryPercent \(battery.intValue), class \(className), transport \(transport), address \(masked(address))")
        }
        return lines.isEmpty ? ["(none)"] : lines
    }
}
