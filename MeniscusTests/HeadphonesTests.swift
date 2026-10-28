import Foundation
import Testing
@testable import Meniscus

struct HeadphonesBatteryTests {
    /// The shape of `system_profiler SPBluetoothDataType -json`, trimmed.
    private let report = Data("""
    {
      "SPBluetoothDataType": [{
        "controller_properties": { "controller_address": "00:00:00:00:00:01", "controller_state": "attrib_on" },
        "device_connected": [
          { "AirPods Pro": {
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
          { "Magic Mouse": {
              "device_address": "AA:BB:CC:DD:EE:03",
              "device_minorType": "Mouse"
          } }
        ],
        "device_not_connected": [
          { "Old Speaker": { "device_address": "AA:BB:CC:DD:EE:04", "device_minorType": "Speaker" } }
        ]
      }]
    }
    """.utf8)

    @Test func readsBudsAndCaseByAddress() {
        let battery = HeadphonesBatteryReader.parse(report, address: "aa-bb-cc-dd-ee-01", name: "")
        #expect(battery == HeadphonesBattery(left: 80, right: 75, case: 60))
        #expect(battery?.lowest == 75)
    }

    @Test func readsASingleLevel() {
        let battery = HeadphonesBatteryReader.parse(report, address: "AA:BB:CC:DD:EE:02", name: "Studio Headphones")
        #expect(battery?.main == 45)
        #expect(battery?.lowest == 45)
    }

    @Test func fallsBackToTheNameWithoutAnAddressMatch() {
        let battery = HeadphonesBatteryReader.parse(report, address: "", name: "AirPods Pro")
        #expect(battery?.left == 80)
    }

    @Test func noBatteryMeansNothing() {
        #expect(HeadphonesBatteryReader.parse(report, address: "AA:BB:CC:DD:EE:03", name: "Magic Mouse") == nil)
        #expect(HeadphonesBatteryReader.parse(report, address: "11:22:33:44:55:66", name: "Unknown") == nil)
        #expect(HeadphonesBatteryReader.parse(Data("not json".utf8), address: "", name: "AirPods") == nil)
    }

    @Test func oneBudOutOfTheCase() {
        #expect(HeadphonesBattery(left: 40).lowest == 40)
        #expect(HeadphonesBattery(case: 90).lowest == nil)
    }

    @Test(arguments: [("80%", 80), ("100 %", 100), ("0%", 0)])
    func readsLevels(text: String, level: Int) {
        #expect(HeadphonesBatteryReader.level(text) == level)
    }

    @Test func ignoresBadLevels() {
        #expect(HeadphonesBatteryReader.level("150%") == nil)
        #expect(HeadphonesBatteryReader.level(80) == nil)
        #expect(HeadphonesBatteryReader.level(nil) == nil)
    }
}

@MainActor
struct HeadphonesSymbolTests {
    @Test(arguments: [
        ("AirPods Pro", "airpodspro"),
        ("Наушники AirPods Max", "airpodsmax"),
        ("AirPods", "airpods"),
        ("Beats Studio Pro", "beats.headphones"),
        ("WH-1000XM5", "headphones"),
        ("", "headphones"),
    ])
    func symbolFromTheName(name: String, symbol: String) {
        #expect(HeadphonesSymbol.name(for: name) == symbol)
    }

    @Test func namesShortenToTheFamilyThenOn() {
        let names = CompactText.headphonesNames("Office AirPods Pro")
        #expect(names.first == "Office AirPods Pro")
        #expect(names.dropFirst().first == "AirPods")
        #expect(names.count == 3)
        #expect(CompactText.headphonesNames("").count == 1)
        #expect(CompactText.headphonesNames("AirPods").count == 2)
    }
}
