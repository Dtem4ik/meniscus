import Foundation

/// Writes captures: a note of its own in a folder, or a line appended to one note. Runs off the
/// main actor and coordinates the write, so iCloud Drive and Obsidian see a clean change.
nonisolated enum InboxWriter {
    /// How much of the end of the note is read to find the last line break and date heading.
    static let tailLength = 64 * 1024

    nonisolated enum WriteError: Error, Equatable, Sendable {
        case emptyEntry
        case failed(String)
    }

    /// Creates `2026-10-27 21-45 First words.md` in `folder` with the text inside, never
    /// replacing an existing note. Returns the new note.
    @concurrent
    static func createNote(_ text: String, in folder: URL, at date: Date) async throws(WriteError) -> URL {
        guard let body = InboxFormatter.noteBody(for: text) else { throw .emptyEntry }
        let fileManager = FileManager.default
        let url = CaptureNoteName.uniqueURL(in: folder, fileName: CaptureNoteName.fileName(for: text, at: date)) {
            fileManager.fileExists(atPath: $0.path(percentEncoded: false))
        }

        var coordinationError: NSError?
        var writeError: (any Error)?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { url in
            do {
                try Data(body.utf8).write(to: url, options: .withoutOverwriting)
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw .failed(coordinationError.localizedDescription) }
        if let writeError { throw .failed(writeError.localizedDescription) }
        return url
    }

    @concurrent
    static func append(_ text: String, to url: URL, at date: Date, addDateHeading: Bool) async throws(WriteError) {
        guard let entry = InboxFormatter.entry(for: text, at: date) else { throw .emptyEntry }

        var coordinationError: NSError?
        var writeError: (any Error)?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { url in
            do {
                try appendSynchronously(entry: entry, to: url, at: date, addDateHeading: addDateHeading)
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw .failed(coordinationError.localizedDescription) }
        if let writeError { throw .failed(writeError.localizedDescription) }
    }

    static func appendSynchronously(entry: String, to url: URL, at date: Date, addDateHeading: Bool) throws {
        let fileManager = FileManager.default
        let path = url.path(percentEncoded: false)
        if !fileManager.fileExists(atPath: path) {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fileManager.createFile(atPath: path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: path])
            }
        }

        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let start = size > UInt64(tailLength) ? size - UInt64(tailLength) : 0
        try handle.seek(toOffset: start)
        let tail = String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self)

        let appendix = InboxFormatter.appendix(entry: entry, existingTail: tail, at: date, addDateHeading: addDateHeading)
        _ = try handle.seekToEnd()
        try handle.write(contentsOf: Data(appendix.utf8))
    }
}
