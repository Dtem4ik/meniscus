import Foundation
import Testing
@testable import Meniscus

struct AudioBatteryReaderTests {
    /// The shape of `system_profiler SPBluetoothDataType -json`, trimmed.
    private let report = Data("""
    {
      "SPBluetoothDataType": [{
        "controller_properties": { "controller_address": "00:00:00:00:00:01", "controller_state": "attrib_on" },
        "device_connected": [
          { "Studio Buds": {
              "device_address": "AA:BB:CC:DD:EE:01",
              "device_batteryLevelCase": "60%",
              "device_batteryLevelLeft": "80%",
              "device_batteryLevelRight": "75%",
              "device_minorType": "Headphones"
          } },
          { "Studio Headphones": {
              "device_address": "AA:BB:CC:DD:EE:02",
              "device_batteryLevelMain": "45%",
              "device_minorType": "Headphones"
          } },
          { "Desk Speaker": {
              "device_address": "AA:BB:CC:DD:EE:03",
              "device_minorType": "Speaker"
          } }
        ],
        "device_not_connected": [
          { "Old Speaker": { "device_address": "AA:BB:CC:DD:EE:04", "device_minorType": "Speaker" } }
        ]
      }]
    }
    """.utf8)

    @Test func readsBudsAndCaseByAddress() {
        let battery = AudioBatteryReader.parse(report, address: "aa-bb-cc-dd-ee-01", name: "")
        #expect(battery == DeviceBattery(left: 80, right: 75, case: 60))
        #expect(battery?.lowest == 75)
    }

    @Test func readsASingleLevel() {
        let battery = AudioBatteryReader.parse(report, address: "AA:BB:CC:DD:EE:02", name: "Studio Headphones")
        #expect(battery?.lowest == 45)
    }

    @Test func fallsBackToTheName() {
        #expect(AudioBatteryReader.parse(report, address: "", name: "Studio Buds")?.left == 80)
    }

    @Test func noBatteryMeansNothing() {
        #expect(AudioBatteryReader.parse(report, address: "AA:BB:CC:DD:EE:03", name: "Desk Speaker") == nil)
        #expect(AudioBatteryReader.parse(report, address: "11:22:33:44:55:66", name: "Unknown") == nil)
        #expect(AudioBatteryReader.parse(Data("not json".utf8), address: "", name: "") == nil)
    }

    @Test func readsLevels() {
        #expect(AudioBatteryReader.level("80%") == 80)
        #expect(AudioBatteryReader.level("150%") == nil)
        #expect(AudioBatteryReader.level(nil) == nil)
    }

    @Test func oneBudOutOfTheCase() {
        #expect(DeviceBattery(left: 40).lowest == 40)
        #expect(DeviceBattery(case: 90).lowest == nil)
    }
}

struct AppleDeviceTests {
    @Test func vendorIDs() {
        #expect(AppleDevice.isApple(vendorID: 0x004C, source: 1))
        #expect(AppleDevice.isApple(vendorID: 0x05AC, source: 2))
        #expect(AppleDevice.isApple(vendorID: 0x05AC, source: nil))
        #expect(!AppleDevice.isApple(vendorID: 0x046D, source: 2))   // Logitech
        #expect(!AppleDevice.isApple(vendorID: 0x004C, source: 2))
        #expect(!AppleDevice.isApple(vendorID: nil, source: nil))
    }

    @Test func names() {
        #expect(AppleDevice.hasAppleName("AirPods Pro"))
        #expect(AppleDevice.hasAppleName("Beats Studio Buds"))
        #expect(AppleDevice.hasAppleName("Magic Keyboard with Touch ID"))
        #expect(!AppleDevice.hasAppleName("MX Master 3S"))
        #expect(!AppleDevice.hasAppleName("WH-1000XM5"))
    }

    @Test func audioKinds() {
        #expect(AudioDeviceMonitor.audioKind(minorClass: 0x06) == .headphones)
        #expect(AudioDeviceMonitor.audioKind(minorClass: 0x01) == .headphones)
        #expect(AudioDeviceMonitor.audioKind(minorClass: 0x05) == .speaker)
    }
}

struct HIDServiceInfoTests {
    private func info(transport: String = "Bluetooth Low Energy", name: String = "MX Master 3S", vendorID: Int? = 0x046D,
                      source: Int? = 2, page: Int = 1, usage: Int = 2, battery: Int? = 70) -> HIDServiceInfo {
        HIDServiceInfo(transport: transport, name: name, vendorID: vendorID, vendorIDSource: source, usagePage: page,
                       usage: usage, address: "aa-bb-cc-dd-ee-ff", battery: battery)
    }

    @Test func thirdPartyBluetoothDevices() {
        #expect(info().device == BluetoothDevice(id: "AABBCCDDEEFF", name: "MX Master 3S", kind: .mouse, battery: DeviceBattery(main: 70)))
        #expect(info(usage: 6).device?.kind == .keyboard)
        #expect(info(transport: "Bluetooth", usage: 5).device?.kind == .gamepad)
        #expect(info(battery: nil).device?.battery == nil)
    }

    @Test func leavesOutEverythingElse() {
        #expect(info(transport: "USB").device == nil)
        #expect(info(transport: "SPI").device == nil)
        #expect(info(vendorID: 0x05AC).device == nil)
        #expect(info(name: "Magic Mouse", vendorID: nil).device == nil)
        #expect(info(page: 0x0C, usage: 1).device == nil)   // media keys of the same keyboard
        #expect(info(page: 0xFF00).device == nil)
    }
}

struct DeviceBatteryWarningsTests {
    @Test func warnsAt20And10OncePerDevice() {
        var warnings = DeviceBatteryWarnings()
        #expect(warnings.check(device: "a", level: 50) == nil)
        #expect(warnings.check(device: "a", level: 20) == 20)
        #expect(warnings.check(device: "a", level: 18) == nil)
        #expect(warnings.check(device: "b", level: 19) == 20)
        #expect(warnings.check(device: "a", level: 10) == 10)
        #expect(warnings.check(device: "a", level: 5) == nil)
    }

    @Test func fallingPastBothWarnsOnceForTheLowest() {
        var warnings = DeviceBatteryWarnings()
        #expect(warnings.check(device: "a", level: 8) == 10)
        #expect(warnings.check(device: "a", level: 15) == nil)
    }

    @Test func chargingRearms() {
        var warnings = DeviceBatteryWarnings()
        #expect(warnings.check(device: "a", level: 20) == 20)
        #expect(warnings.check(device: "a", level: 80) == nil)
        #expect(warnings.check(device: "a", level: 20) == 20)
    }
}

@MainActor
struct BluetoothActivityTests {
    @Test func namesShortenToTheFirstWordThenOn() {
        #expect(CompactText.deviceNames("Logitech MX Keys") == ["Logitech MX Keys", "Logitech", String(localized: "On")])
        #expect(CompactText.deviceNames("Keychron").count == 2)
        #expect(CompactText.deviceNames("").count == 1)
    }
}

struct MainThreadTests {
    /// System callbacks may arrive on any queue; handing over must not stop the app.
    @Test func runsMainActorWorkFromABackgroundThread() async {
        let ran = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                MainThread.run {
                    MainActor.assertIsolated()
                    continuation.resume(returning: true)
                }
            }
        }
        #expect(ran)
    }
}
