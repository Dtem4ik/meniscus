import Carbon.HIToolbox
import Foundation
import Testing
@testable import Meniscus

struct InboxFormatterTests {
    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-10-27 14:32:00 UTC
    private let date = Date(timeIntervalSince1970: 1_793_111_520)

    @Test func formatsASingleLine() {
        #expect(InboxFormatter.entry(for: "  Buy oat milk  ", at: date, timeZone: utc) == "- 14:32 Buy oat milk")
    }

    @Test func indentsFollowingLinesAndTrimsBlankEdges() {
        let entry = InboxFormatter.entry(for: "\n\nIdea\r\nwith details\n\n", at: date, timeZone: utc)
        #expect(entry == "- 14:32 Idea\n  with details")
    }

    @Test func blankInputIsNotAnEntry() {
        #expect(InboxFormatter.entry(for: " \n\t ", at: date, timeZone: utc) == nil)
    }

    @Test func addsLineBreakWhenNoteDoesNotEndWithOne() {
        let appendix = InboxFormatter.appendix(entry: "- 14:32 A", existingTail: "# Inbox", at: date, addDateHeading: false, timeZone: utc)
        #expect(appendix == "\n- 14:32 A\n")
    }

    @Test func addsDateHeadingOnceADay() {
        let first = InboxFormatter.appendix(entry: "- 14:32 A", existingTail: "# Inbox\n", at: date, addDateHeading: true, timeZone: utc)
        #expect(first == "\n## 2026-10-27\n\n- 14:32 A\n")

        let tail = "# Inbox\n\n## 2026-10-27\n\n- 14:32 A\n"
        let second = InboxFormatter.appendix(entry: "- 14:40 B", existingTail: tail, at: date, addDateHeading: true, timeZone: utc)
        #expect(second == "- 14:40 B\n")
    }

    @Test func headingInEmptyNoteHasNoLeadingBlankLine() {
        let appendix = InboxFormatter.appendix(entry: "- 14:32 A", existingTail: "", at: date, addDateHeading: true, timeZone: utc)
        #expect(appendix == "## 2026-10-27\n\n- 14:32 A\n")
    }
}

struct InboxWriterTests {
    private let date = Date(timeIntervalSince1970: 1_793_111_520)

    private func temporaryNote() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "meniscus-capture-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "Folder/Inbox.md")
    }

    @Test func createsTheNoteAndAppends() async throws {
        let note = temporaryNote()
        try await InboxWriter.append("First", to: note, at: date, addDateHeading: false)
        try await InboxWriter.append("Second", to: note, at: date, addDateHeading: false)
        let contents = try String(contentsOf: note, encoding: .utf8)
        let lines = contents.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix(" First"))
        #expect(lines[1].hasSuffix(" Second"))
    }

    @Test func keepsExistingContent() async throws {
        let note = temporaryNote()
        try FileManager.default.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# Inbox".utf8).write(to: note)
        try await InboxWriter.append("Thought", to: note, at: date, addDateHeading: false)
        let contents = try String(contentsOf: note, encoding: .utf8)
        #expect(contents.hasPrefix("# Inbox\n- "))
        #expect(contents.hasSuffix(" Thought\n"))
    }

    @Test func refusesBlankEntries() async {
        await #expect(throws: InboxWriter.WriteError.emptyEntry) {
            try await InboxWriter.append("   ", to: temporaryNote(), at: date, addDateHeading: false)
        }
    }
}

struct HotKeyTests {
    @Test func defaultHotKeyIsControlOptionSpace() {
        let hotKey = HotKey.defaultCapture
        #expect(hotKey.displayString == "⌃⌥Space")
        #expect(hotKey.carbonModifiers == UInt32(controlKey | optionKey))
        #expect(hotKey.isValid)
    }

    @Test func shortcutsNeedAModifierBesidesShift() {
        #expect(!HotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: [.shift]).isValid)
        #expect(!HotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: []).isValid)
        #expect(HotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: [.command, .shift]).displayString == "⇧⌘K")
    }

    @Test func hotKeyRoundTripsThroughJSON() throws {
        let hotKey = HotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: [.command, .option])
        let decoded = try JSONDecoder().decode(HotKey.self, from: JSONEncoder().encode(hotKey))
        #expect(decoded == hotKey)
    }
}

struct CaptureNoteTests {
    /// 2026-10-27 21:45 UTC.
    private let date = Date(timeIntervalSince1970: 1_793_137_500)
    private let utc = TimeZone(identifier: "UTC")!

    @Test func nameIsDateTimeAndFirstWords() {
        #expect(CaptureNoteName.fileName(for: "Позвонить в банк", at: date, timeZone: utc) == "2026-10-27 21-45 Позвонить в банк.md")
    }

    @Test func nameKeepsAtMostSixWordsOfTheFirstLine() {
        let name = CaptureNoteName.fileName(for: "\n  one two three four five six seven\nsecond line", at: date, timeZone: utc)
        #expect(name == "2026-10-27 21-45 one two three four five six.md")
    }

    @Test func nameDropsCharactersFilesAndLinksCannotHold() {
        #expect(CaptureNoteName.title(from: "Fix: a/b [[link]] #tag?") == "Fix a b link tag")
        #expect(CaptureNoteName.title(from: "...hidden.") == "hidden")
    }

    @Test func longWordsAreCutAtTheLimit() {
        let title = CaptureNoteName.title(from: String(repeating: "a", count: 100))
        #expect(title.count == CaptureNoteName.maximumTitleLength)
    }

    @Test func blankTitleLeavesTheTimestamp() {
        #expect(CaptureNoteName.fileName(for: "???", at: date, timeZone: utc) == "2026-10-27 21-45.md")
    }

    @Test func takenNamesGetANumber() {
        let folder = URL(filePath: "/tmp/Inbox", directoryHint: .isDirectory)
        let taken: Set<String> = ["/tmp/Inbox/Note.md", "/tmp/Inbox/Note 2.md"]
        let url = CaptureNoteName.uniqueURL(in: folder, fileName: "Note.md") { taken.contains($0.path(percentEncoded: false)) }
        #expect(url.lastPathComponent == "Note 3.md")
    }

    @Test func bodyDropsBlankEdgesOnly() {
        #expect(InboxFormatter.noteBody(for: "\n  first\n\n  second  \n\n") == "  first\n\n  second  \n")
        #expect(InboxFormatter.noteBody(for: " \n ") == nil)
    }

    /// Like an Obsidian vault in iCloud Drive: spaces, Cyrillic and a tilde in the path.
    @Test func writesIntoFoldersWithSpacesAndCyrillic() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "meniscus-capture-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "iCloud~md~obsidian/Мои заметки/Входящие", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let first = try await InboxWriter.createNote("Позвонить в банк\nпро карту", in: folder, at: date)
        let second = try await InboxWriter.createNote("Позвонить в банк", in: folder, at: date)

        #expect(first.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(first.lastPathComponent.hasSuffix(" Позвонить в банк.md"))
        #expect(second.lastPathComponent.hasSuffix(" Позвонить в банк 2.md"))
        #expect(try String(contentsOf: first, encoding: .utf8) == "Позвонить в банк\nпро карту\n")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(names.count == 2)
    }

    @Test func refusesBlankNotes() async {
        await #expect(throws: InboxWriter.WriteError.emptyEntry) {
            try await InboxWriter.createNote("  \n ", in: FileManager.default.temporaryDirectory, at: date)
        }
    }

    @MainActor
    @Test func newNotesAreTheDefault() {
        let defaults = UserDefaults(suiteName: "meniscus-capture-\(UUID().uuidString)")!
        #expect(CaptureSettings(defaults: defaults).destination == .noteInFolder)
    }
}
