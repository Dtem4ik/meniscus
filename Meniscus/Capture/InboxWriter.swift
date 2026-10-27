import Foundation

/// Appends entries to the inbox note. Runs off the main actor and coordinates the write, so
/// iCloud Drive and Obsidian see a clean change.
nonisolated enum InboxWriter {
    /// How much of the end of the note is read to find the last line break and date heading.
    static let tailLength = 64 * 1024

    nonisolated enum WriteError: Error, Equatable, Sendable {
        case emptyEntry
        case failed(String)
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
