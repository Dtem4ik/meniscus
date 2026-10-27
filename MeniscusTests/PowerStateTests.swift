import Testing
@testable import Meniscus

struct PowerStateTests {
    private func description(
        type: String = "InternalBattery",
        current: Int = 50,
        max: Int = 100,
        source: String = "Battery Power",
        charging: Bool = false,
        charged: Bool = false
    ) -> [String: Any] {
        [
            "Type": type,
            "Current Capacity": current,
            "Max Capacity": max,
            "Power Source State": source,
            "Is Charging": charging,
            "Is Charged": charged,
        ]
    }

    @Test func parsesInternalBattery() throws {
        let state = try #require(PowerState(powerSourceDescription: description(current: 73, source: "AC Power", charging: true)))
        #expect(state == PowerState(level: 73, isOnACPower: true, isCharging: true))
    }

    @Test func levelIsAPercentageOfMaxCapacity() throws {
        let state = try #require(PowerState(powerSourceDescription: description(current: 2_000, max: 4_000)))
        #expect(state.level == 50)
    }

    @Test func ignoresOtherPowerSources() {
        #expect(PowerState(powerSourceDescription: description(type: "UPS")) == nil)
        #expect(PowerState(powerSourceDescription: description(max: 0)) == nil)
        #expect(PowerState(powerSourceDescription: [:]) == nil)
    }

    @Test func firstSnapshotIsNotAnEvent() {
        #expect(PowerEventDetector.event(from: nil, to: PowerState(level: 40, isOnACPower: true, isCharging: true)) == nil)
    }

    @Test func detectsConnectAndDisconnect() {
        let battery = PowerState(level: 40, isOnACPower: false, isCharging: false)
        let charger = PowerState(level: 40, isOnACPower: true, isCharging: true)
        #expect(PowerEventDetector.event(from: battery, to: charger) == .connected(level: 40))
        #expect(PowerEventDetector.event(from: charger, to: battery) == .disconnected(level: 40))
    }

    @Test func detectsFullCharge() {
        let charging = PowerState(level: 99, isOnACPower: true, isCharging: true)
        let full = PowerState(level: 100, isOnACPower: true, isCharging: false, isCharged: true)
        #expect(PowerEventDetector.event(from: charging, to: full) == .fullyCharged)
    }

    @Test func levelChangesAloneAreNotEvents() {
        let a = PowerState(level: 40, isOnACPower: false, isCharging: false)
        let b = PowerState(level: 39, isOnACPower: false, isCharging: false)
        #expect(PowerEventDetector.event(from: a, to: b) == nil)
    }
}
