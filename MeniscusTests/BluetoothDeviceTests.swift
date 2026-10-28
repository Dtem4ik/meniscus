import Foundation
import Testing
@testable import Meniscus

struct SystemProfilerBatteryTests {
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
        let battery = SystemProfilerBattery.parse(report, address: "aa-bb-cc-dd-ee-01", name: "")
        #expect(battery == DeviceBattery(left: 80, right: 75, case: 60))
        #expect(battery?.lowest == 75)
    }

    @Test func readsASingleLevel() {
        let battery = SystemProfilerBattery.parse(report, address: "AA:BB:CC:DD:EE:02", name: "Studio Headphones")
        #expect(battery?.lowest == 45)
    }

    @Test func fallsBackToTheName() {
        #expect(SystemProfilerBattery.parse(report, address: "", name: "Studio Buds")?.left == 80)
    }

    @Test func noBatteryMeansNothing() {
        #expect(SystemProfilerBattery.parse(report, address: "AA:BB:CC:DD:EE:03", name: "Desk Speaker") == nil)
        #expect(SystemProfilerBattery.parse(report, address: "11:22:33:44:55:66", name: "Unknown") == nil)
        #expect(SystemProfilerBattery.parse(Data("not json".utf8), address: "", name: "") == nil)
    }

    @Test func readsLevels() {
        #expect(SystemProfilerBattery.level("80%") == 80)
        #expect(SystemProfilerBattery.level("150%") == nil)
        #expect(SystemProfilerBattery.level(nil) == nil)
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
struct MiniBannerTests {
    private let mouse = BluetoothDevice(id: "a", name: "MX Master 3S", kind: .mouse, battery: DeviceBattery(main: 75))

    @Test func connectionShowsTheFullNameAndTheBatteryRing() {
        let banner = MiniBanner.bluetooth(mouse, isConnected: true)
        #expect(banner.leading == .symbol("computermouse.fill"))
        #expect(banner.title == "MX Master 3S")
        #expect(banner.subtitle == String(localized: "Connected"))
        #expect(banner.trailing == .battery(75))
    }

    @Test func noBatteryNoRing() {
        var device = mouse
        device.battery = nil
        #expect(MiniBanner.bluetooth(device, isConnected: true).trailing == nil)
    }

    @Test func headphonesShowTheLowerEarbud() {
        let buds = BluetoothDevice(id: "b", name: "MAJOR V", kind: .headphones, battery: DeviceBattery(left: 81, right: 79, case: 40))
        #expect(MiniBanner.bluetooth(buds, isConnected: true).trailing == .battery(79))
    }

    @Test func disconnectionSaysSoWithoutARing() {
        let banner = MiniBanner.bluetooth(mouse, isConnected: false)
        #expect(banner.title == "MX Master 3S")
        #expect(banner.subtitle == String(localized: "Disconnected"))
        #expect(banner.trailing == nil)
    }

    @Test func ringColors() {
        #expect(BatteryRingStyle.tone(level: 81) == .normal)
        #expect(BatteryRingStyle.tone(level: 20) == .normal)
        #expect(BatteryRingStyle.tone(level: 19) == .low)
        #expect(BatteryRingStyle.tone(level: 10) == .low)
        #expect(BatteryRingStyle.tone(level: 9) == .critical)
    }

    @Test func aLateBatteryNeverReopensTheBanner() {
        let services = ActivityServices()
        services.simulateBluetoothDevice()
        services.center.remove(id: ActivityID.bluetoothDevice)
        services.simulatedBatteryArrived(level: 64)
        #expect(services.center.current == nil)
    }
}

struct BannerLayoutTests {
    private func layout() -> IslandLayout {
        IslandLayout(geometry: NotchGeometry(
            kind: .hardware,
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            notchRect: CGRect(x: 661, y: 950, width: 190, height: 32),
            backingScale: 2
        ))
    }

    @Test func smallerThanTheOpenIslandAndClearOfTheNotch() {
        let layout = layout()
        let banner = layout.shape(for: .banner)
        let player = layout.shape(for: .expanded, content: .nowPlaying)
        #expect(banner.height < player.height)
        #expect(banner.height > layout.shape(for: .compact).height)
        #expect(banner.width >= layout.geometry.notchRect.width + 2 * layout.metrics.bannerMinimumWingWidth)
        let rect = layout.interactiveScreenRect(for: .banner)
        #expect(abs(rect.midX - layout.geometry.notchRect.midX) < 0.01)
    }

    @Test func widthFollowsTheContent() {
        let layout = layout()
        let narrow = layout.bannerWidth(contentWidth: 120)
        let wide = layout.bannerWidth(contentWidth: 300)
        #expect(narrow == layout.minimumBannerWidth)
        #expect(wide > narrow)
        #expect(layout.bannerWidth(contentWidth: 2000) == layout.metrics.bannerMaximumWidth)
        #expect(layout.shape(for: .banner, bannerWidth: wide).width == wide)
    }

    @Test func bannerActivitiesRestInTheBanner() {
        let state = NotchState(layout: layout())
        state.compactActivity = LiveActivity(id: "x", kind: .bluetoothDevice, priority: .confirmation, updatedAt: .now, expiresAt: nil)
        #expect(state.restingPhase == .banner)
        state.compactActivity = LiveActivity(id: "y", kind: .charging, priority: .charging, updatedAt: .now, expiresAt: nil)
        #expect(state.restingPhase == .compact)
        state.compactActivity = nil
        #expect(state.restingPhase == .collapsed)
    }
}

struct SystemProfilerLeniencyTests {
    @Test func readsAnyBatteryLevelKey() {
        let data = Data("""
        {"SPBluetoothDataType":[{"device_connected":[
          {"MX Master 3S":{"device_address":"AA:BB:CC:DD:EE:05","device_batteryLevel":"75%","device_minorType":"Mouse"}},
          {"MAJOR V":{"device_address":"AA:BB:CC:DD:EE:06","device_batteryLevelMain":81,"device_minorType":"Headphones"}}
        ]}]}
        """.utf8)
        #expect(SystemProfilerBattery.parse(data, address: "aa-bb-cc-dd-ee-05", name: "")?.lowest == 75)
        #expect(SystemProfilerBattery.parse(data, address: "", name: "MAJOR V")?.lowest == 81)
        #expect(SystemProfilerBattery.parse(data, address: "", name: "") == nil)
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

struct AccessoryPowerSourcesTests {
    @Test func readsAccessoriesAndSkipsTheMac() {
        let output = """
        Now drawing from 'AC Power'
         -InternalBattery-0 (id=4653155)	100%; charged; 0:00 remaining present: true
         -MX Master 3S (id=11796480)	75%; discharging; (no estimate) present: true
         -MAJOR V (id=11862016)	81%; discharging; (no estimate) present: true
        """
        let entries = AccessoryPowerSources.parse(output)
        #expect(entries.map(\.name) == ["MX Master 3S", "MAJOR V"])
        #expect(entries.map(\.level) == [75, 81])
        #expect(AccessoryPowerSources.parse("Now drawing from 'AC Power'").isEmpty)
    }
}

struct SystemProfilerSectionsTests {
    private let data = Data("""
    {"SPBluetoothDataType":[{
      "device_connected":[{"MX Master 3S":{"device_address":"AA:BB:CC:DD:EE:05","device_minorType":"Mouse","device_serialNumber":"ABCDEF123456"}}],
      "device_not_connected":[{"Old Mouse":{"device_address":"AA:BB:CC:DD:EE:09","device_batteryLevelMain":"50%","device_minorType":"Mouse"}}]
    }]}
    """.utf8)

    @Test func tellsConnectedFromPaired() {
        let devices = SystemProfilerBattery.devices(in: data)
        #expect(devices.first { $0.name == "MX Master 3S" }?.isConnected == true)
        #expect(devices.first { $0.name == "Old Mouse" }?.isConnected == false)
    }

    @Test func aPairedDevicesOldLevelIsNotUsed() {
        #expect(SystemProfilerBattery.parse(data, address: "AA:BB:CC:DD:EE:09", name: "Old Mouse") == nil)
    }

    @Test func diagnosticsShowRawKeysOfConnectedDevices() {
        let lines = BluetoothDiagnostics.systemProfilerLines(data)
        let connected = lines.firstIndex(of: "Connected now:") ?? -1
        let paired = lines.firstIndex(of: "Paired, not connected:") ?? -1
        #expect(connected >= 0 && paired > connected)
        let mouse = lines.first { $0.contains("MX Master 3S") } ?? ""
        #expect(mouse.contains("device_minorType=Mouse"))
        #expect(mouse.contains("(no battery keys)"))
        #expect(!mouse.contains("ABCDEF123456"))
        #expect(!mouse.contains("AA:BB"))
    }
}
