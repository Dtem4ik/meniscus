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

struct VaultAndHotKeyTests {
    @Test func relativePathInsideVault() {
        let vault = URL(filePath: "/tmp/Vault", directoryHint: .isDirectory)
        #expect(VaultBookmark.relativePath(of: URL(filePath: "/tmp/Vault/Notes/Inbox.md"), in: vault) == "Notes/Inbox.md")
        #expect(VaultBookmark.relativePath(of: URL(filePath: "/tmp/Other/Inbox.md"), in: vault) == nil)
        #expect(VaultBookmark.relativePath(of: URL(filePath: "/tmp/VaultX/Inbox.md"), in: vault) == nil)
    }

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
