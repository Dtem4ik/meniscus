import Foundation

/// File names for notes of their own: `2026-10-27 21-45 Call the bank.md`. Pure, so the exact
/// output is unit tested.
nonisolated enum CaptureNoteName {
    /// How much of the text goes into the name.
    static let maximumWords = 6
    static let maximumTitleLength = 60

    static func fileName(for text: String, at date: Date, timeZone: TimeZone = .current) -> String {
        let stamp = InboxFormatter.formatted(date, pattern: "yyyy-MM-dd HH-mm", timeZone: timeZone)
        let title = title(from: text)
        return (title.isEmpty ? stamp : "\(stamp) \(title)") + ".md"
    }

    /// The first words of the first non-blank line, without characters that file systems or
    /// Obsidian links don't allow.
    static func title(from text: String) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let cleaned = String(firstLine.unicodeScalars.map { scalar in
            forbidden.contains(scalar) || CharacterSet.controlCharacters.contains(scalar) ? " " : Character(scalar)
        })
        var title = cleaned
            .split(whereSeparator: \.isWhitespace)
            .prefix(maximumWords)
            .joined(separator: " ")
        if title.count > maximumTitleLength {
            let cut = title.prefix(maximumTitleLength)
            title = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)
        }
        // A leading dot hides the file; trailing dots and commas look broken before ".md".
        let edges = CharacterSet(charactersIn: ".,;")
        title = title.trimmingCharacters(in: edges.union(.whitespaces))
        return title.precomposedStringWithCanonicalMapping
    }

    /// `name.md`, or `name 2.md`, `name 3.md`… if it is taken.
    static func uniqueURL(in folder: URL, fileName: String, exists: (URL) -> Bool) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let pathExtension = (fileName as NSString).pathExtension
        var candidate = folder.appending(path: fileName, directoryHint: .notDirectory)
        var number = 2
        while exists(candidate) {
            candidate = folder.appending(path: "\(base) \(number).\(pathExtension)", directoryHint: .notDirectory)
            number += 1
        }
        return candidate
    }

    private static let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]")
}
