import AppKit
import Observation
import UniformTypeIdentifiers

/// Where a capture is saved.
nonisolated enum CaptureDestination: String, CaseIterable, Identifiable, Sendable {
    /// A new note for each capture, in a chosen folder. The default.
    case noteInFolder
    /// A line at the end of one chosen note.
    case lineInNote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .noteInFolder: String(localized: "A new note for each capture")
        case .lineInNote: String(localized: "A line in one note")
        }
    }
}

/// Where captured thoughts go, persisted in `UserDefaults`. Nothing about the folder or note is
/// stored in the repository.
@Observable
final class CaptureSettings {
    static let shared = CaptureSettings()

    private enum Key {
        static let destination = "capture.destination"
        static let folderBookmark = "capture.folderBookmark"
        static let noteBookmark = "capture.noteBookmark"
        static let dateHeadings = "capture.dateHeadings"
        static let hotKey = "capture.hotKey"
    }

    var destination: CaptureDestination {
        didSet { defaults.set(destination.rawValue, forKey: Key.destination) }
    }
    /// The chosen folder and note, for display; `resolvedFolder()` and `resolvedNote()` follow
    /// moves and renames when saving.
    private(set) var folderURL: URL?
    private(set) var noteURL: URL?
    var addsDateHeadings: Bool {
        didSet { defaults.set(addsDateHeadings, forKey: Key.dateHeadings) }
    }
    var hotKey: HotKey? {
        didSet { defaults.set(hotKey.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.hotKey) }
    }

    var isConfigured: Bool {
        switch destination {
        case .noteInFolder: folderURL != nil
        case .lineInNote: noteURL != nil
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        destination = defaults.string(forKey: Key.destination).flatMap(CaptureDestination.init(rawValue:)) ?? .noteInFolder
        addsDateHeadings = defaults.object(forKey: Key.dateHeadings) as? Bool ?? true
        if let data = defaults.data(forKey: Key.hotKey) {
            hotKey = try? JSONDecoder().decode(HotKey.self, from: data)
        } else {
            hotKey = .defaultCapture
        }
        folderURL = resolve(Key.folderBookmark)
        noteURL = resolve(Key.noteBookmark)
    }

    func resolvedFolder() -> URL? {
        folderURL = resolve(Key.folderBookmark)
        return folderURL
    }

    func resolvedNote() -> URL? {
        noteURL = resolve(Key.noteBookmark)
        return noteURL
    }

    /// Resolves a bookmark, refreshing it when stale.
    private func resolve(_ key: String) -> URL? {
        guard let data = defaults.data(forKey: key),
              let resolved = try? CaptureBookmark.resolve(data)
        else { return nil }
        if resolved.isStale, let fresh = try? CaptureBookmark.make(for: resolved.url) {
            defaults.set(fresh, forKey: key)
        }
        return resolved.url
    }

    // MARK: Choosing

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose a Folder for Captures")
        panel.message = String(localized: "Each capture becomes a new note in this folder, for example your Obsidian inbox.")
        panel.directoryURL = folderURL
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url, let bookmark = try? CaptureBookmark.make(for: url) else { return }
        defaults.set(bookmark, forKey: Key.folderBookmark)
        folderURL = url
    }

    func chooseNote() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose a Note for Captures")
        panel.directoryURL = noteURL?.deletingLastPathComponent() ?? folderURL
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url, let bookmark = try? CaptureBookmark.make(for: url) else { return }
        defaults.set(bookmark, forKey: Key.noteBookmark)
        noteURL = url
    }
}
