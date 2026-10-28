import Foundation

/// Accessory batteries from `pmset -g accps`, the public power management tool, which lists the
/// accessories that report a battery to the system (AirPods and some headphones and mice).
/// Run only after a device connects, until the battery shows up; never polled.
nonisolated enum AccessoryPowerSources {
    static let toolURL = URL(filePath: "/usr/bin/pmset")
    static let timeout: TimeInterval = 4

    /// The level of the accessory with this name, if listed.
    @concurrent
    static func level(named name: String) async -> Int? {
        guard !name.isEmpty, let output = await report() else { return nil }
        return parse(output).first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.level
    }

    /// Lines like ` -MX Master 3S (id=1234567)	75%; discharging; (no estimate) present: true`.
    /// The Mac's own battery (`InternalBattery-0`) is left out. Pure, so it is tested.
    static func parse(_ output: String) -> [(name: String, level: Int)] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            guard let match = line.firstMatch(of: /^\s*-(.+?)\s+\(id=\d+\)\s+(\d{1,3})%/),
                  let level = Int(match.2), (0...100).contains(level) else { return nil }
            let name = String(match.1).trimmingCharacters(in: .whitespaces)
            guard !name.hasPrefix("InternalBattery") else { return nil }
            return (name, level)
        }
    }

    @concurrent
    static func report() async -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = toolURL
        process.arguments = ["-g", "accps"]
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"]
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
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
