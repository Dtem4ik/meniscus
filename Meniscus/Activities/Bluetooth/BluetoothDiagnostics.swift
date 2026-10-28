import Foundation
import IOKit
import IOKit.hid

/// What each battery source reports, per device, as plain text for the Developer button. Read
/// only when asked. Bluetooth addresses are shortened to their last two bytes.
nonisolated enum BluetoothDiagnostics {
    @concurrent
    static func report() async -> String {
        var lines = ["Meniscus Bluetooth diagnostics", ""]
        lines.append("IOKit HID devices on Bluetooth:")
        lines += hidDevices().map { "  " + $0 }
        lines.append("")
        lines.append("IOKit entries with BatteryPercent (like ioreg -r -k BatteryPercent):")
        lines += registryBatteries().map { "  " + $0 }
        lines.append("")
        lines.append("system_profiler SPBluetoothDataType:")
        if let data = await SystemProfilerBattery.report() {
            lines += systemProfilerLines(data).map { "  " + $0 }
        } else {
            lines.append("  (failed or timed out)")
        }
        return lines.joined(separator: "\n")
    }

    /// One line per device in the tool's report, with its battery keys. Pure, so it is tested.
    static func systemProfilerLines(_ data: Data) -> [String] {
        let devices = SystemProfilerBattery.devices(in: data)
        guard !devices.isEmpty else { return ["(no devices)"] }
        return devices.map { device in
            let (name, info) = device
            let battery = info.keys.filter { $0.hasPrefix("device_battery") }.sorted().map { key in
                "\(key)=" + (info[key].map { value in "\(value)" } ?? "")
            }
            let fields = [
                "address \(masked(info["device_address"] as? String))",
                "type \(info["device_minorType"] as? String ?? "?")",
                "vendor \(info["device_vendorID"] as? String ?? "?")",
            ] + (battery.isEmpty ? ["no battery keys"] : battery)
            return "\(name): " + fields.joined(separator: ", ")
        }
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
