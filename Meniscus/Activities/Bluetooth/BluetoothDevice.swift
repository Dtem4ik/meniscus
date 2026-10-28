import Foundation
import OSLog

/// A third-party Bluetooth device the island tells about. Apple's own devices (AirPods, Beats,
/// Magic Mouse, Keyboard and Trackpad) are left out: macOS shows its own window for them.
nonisolated struct BluetoothDevice: Identifiable, Equatable, Sendable {
    /// The Bluetooth address when known, otherwise the name.
    var id: String
    var name: String
    var kind: Kind
    /// `nil` when the system doesn't report the battery.
    var battery: DeviceBattery?

    nonisolated enum Kind: String, Equatable, Sendable {
        case headphones, speaker, mouse, keyboard, gamepad

        var symbol: String {
            switch self {
            case .headphones: "headphones"
            case .speaker: "hifispeaker.fill"
            case .mouse: "computermouse.fill"
            case .keyboard: "keyboard.fill"
            case .gamepad: "gamecontroller.fill"
            }
        }
    }
}

/// Battery levels, 0...100. Headphones may report each earbud and the case; other devices one
/// level.
nonisolated struct DeviceBattery: Equatable, Sendable {
    var left: Int?
    var right: Int?
    var `case`: Int?
    var main: Int?

    init(left: Int? = nil, right: Int? = nil, case: Int? = nil, main: Int? = nil) {
        self.left = left
        self.right = right
        self.case = `case`
        self.main = main
    }

    var isEmpty: Bool { left == nil && right == nil && self.case == nil && main == nil }

    /// The level the notch shows and warns about: the lower earbud, or the single level.
    var lowest: Int? {
        [left, right].compactMap { $0 }.min() ?? main
    }
}

/// A device connecting, disconnecting or reporting its battery.
nonisolated enum BluetoothDeviceEvent: Equatable, Sendable {
    case connected(BluetoothDevice)
    case disconnected(BluetoothDevice)
    /// A battery reading that came after the connection (headphones, or a device that reported
    /// a change).
    case battery(BluetoothDevice)
}

/// Tells Apple's devices from third-party ones.
nonisolated enum AppleDevice {
    /// Apple's Bluetooth SIG company ID (vendor ID source 1) and USB vendor ID (source 2).
    static let bluetoothVendorID = 0x004C
    static let usbVendorID = 0x05AC

    /// `source` is the Device ID profile's vendor ID source when known: 1 Bluetooth SIG, 2 USB.
    static func isApple(vendorID: Int?, source: Int?) -> Bool {
        guard let vendorID else { return false }
        switch source {
        case 1: return vendorID == bluetoothVendorID
        case 2: return vendorID == usbVendorID
        default: return vendorID == usbVendorID || vendorID == bluetoothVendorID
        }
    }

    /// For devices that don't report a vendor: the names Apple gives its devices.
    static func hasAppleName(_ name: String) -> Bool {
        let name = name.lowercased()
        return ["airpods", "beats", "magic mouse", "magic keyboard", "magic trackpad", "powerbeats"]
            .contains { name.contains($0) }
    }
}

/// Warns once at 20% and once at 10% per device, like the Mac's battery. A device charged back
/// above 25% can warn again.
nonisolated struct DeviceBatteryWarnings: Equatable, Sendable {
    static let thresholds = LowBatteryWarnings.thresholds
    static let rearmLevel = 25

    private(set) var warned: [String: Set<Int>] = [:]

    /// The threshold to warn about for this reading, if any.
    mutating func check(device: String, level: Int) -> Int? {
        if level > Self.rearmLevel {
            warned[device] = nil
            return nil
        }
        let reached = Self.thresholds.filter { level <= $0 }
        var done = warned[device] ?? []
        guard let lowest = reached.min(), !done.contains(lowest) else { return nil }
        done.formUnion(reached)
        warned[device] = done
        return lowest
    }
}

/// When a connected device's battery is read: it is often not ready at the moment of
/// connection, so again after each of these delays (from the connection) until it is.
nonisolated enum BatteryRetry {
    static let delays: [Duration] = [.seconds(2), .seconds(5), .seconds(10)]
}

extension Logger {
    /// Bluetooth devices and what each battery source returned. In Console, filter by subsystem
    /// `io.github.dtem4ik.meniscus` and category `bluetooth`.
    nonisolated static let bluetooth = Logger(subsystem: "io.github.dtem4ik.meniscus", category: "bluetooth")
}

extension MiniBanner {
    /// A device connecting (its battery ring when known) or disconnecting.
    static func bluetooth(_ device: BluetoothDevice, isConnected: Bool) -> MiniBanner {
        MiniBanner(
            leading: .symbol(device.kind.symbol),
            title: device.name.isEmpty ? String(localized: "Bluetooth device") : device.name,
            subtitle: isConnected ? nil : String(localized: "Disconnected"),
            trailing: isConnected ? device.battery?.lowest.map { .battery($0) } : nil
        )
    }

    /// The banner a live activity shows, for the activities shown as one.
    static func `for`(_ activity: LiveActivity) -> MiniBanner? {
        switch activity.kind {
        case .bluetoothDevice:
            guard let shown = ActivityServices.shared.bluetoothDevice else { return nil }
            return .bluetooth(shown.device, isConnected: shown.isConnected)
        default:
            return nil
        }
    }
}
