import Foundation

/// Turns a captured thought into Markdown for the inbox note. Pure, so the exact output is
/// unit tested.
nonisolated enum InboxFormatter {
    /// `- 14:32 The thought`. Further lines are indented so they stay in the same list item.
    /// Returns `nil` for blank input.
    static func entry(for text: String, at date: Date, timeZone: TimeZone = .current) -> String? {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let trimmed = Array(lines.drop(while: \.isEmpty).reversed().drop(while: \.isEmpty).reversed())
        guard let first = trimmed.first else { return nil }
        let rest = trimmed.dropFirst().map { $0.isEmpty ? "" : "  \($0)" }
        return (["- \(time(of: date, timeZone: timeZone)) \(first)"] + rest).joined(separator: "\n")
    }

    /// What to append to a note that currently ends with `tail`: a line break if the note
    /// doesn't end with one, a `## yyyy-MM-dd` heading when the day changed (if enabled), then
    /// the entry.
    static func appendix(entry: String, existingTail tail: String, at date: Date, addDateHeading: Bool, timeZone: TimeZone = .current) -> String {
        var output = ""
        if !tail.isEmpty && !tail.hasSuffix("\n") { output += "\n" }
        if addDateHeading {
            let heading = "## \(day(of: date, timeZone: timeZone))"
            let lastHeading = tail
                .split(separator: "\n", omittingEmptySubsequences: true)
                .last { $0.hasPrefix("## ") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if lastHeading != heading {
                if !tail.isEmpty { output += "\n" }
                output += "\(heading)\n\n"
            }
        }
        return output + entry + "\n"
    }

    static func time(of date: Date, timeZone: TimeZone) -> String {
        formatted(date, pattern: "HH:mm", timeZone: timeZone)
    }

    static func day(of date: Date, timeZone: TimeZone) -> String {
        formatted(date, pattern: "yyyy-MM-dd", timeZone: timeZone)
    }

    private static func formatted(_ date: Date, pattern: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
