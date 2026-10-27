import AppKit
import Observation
import UniformTypeIdentifiers

/// Where captured thoughts go, persisted in `UserDefaults`. Nothing about the vault is stored in
/// the repository.
@Observable
final class CaptureSettings {
    static let shared = CaptureSettings()

    private enum Key {
        static let vaultBookmark = "capture.vaultBookmark"
        static let inboxPath = "capture.inboxPath"
        static let dateHeadings = "capture.dateHeadings"
        static let hotKey = "capture.hotKey"
    }

    /// Display path of the vault folder, if one is chosen.
    private(set) var vaultPath: String?
    /// The inbox note, relative to the vault.
    var inboxPath: String {
        didSet { defaults.set(inboxPath, forKey: Key.inboxPath) }
    }
    var addsDateHeadings: Bool {
        didSet { defaults.set(addsDateHeadings, forKey: Key.dateHeadings) }
    }
    var hotKey: HotKey? {
        didSet { defaults.set(hotKey.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.hotKey) }
    }

    var isConfigured: Bool { vaultPath != nil && !inboxPath.isEmpty }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        inboxPath = defaults.string(forKey: Key.inboxPath) ?? "Inbox.md"
        addsDateHeadings = defaults.object(forKey: Key.dateHeadings) as? Bool ?? true
        if let data = defaults.data(forKey: Key.hotKey) {
            hotKey = try? JSONDecoder().decode(HotKey.self, from: data)
        } else {
            hotKey = .defaultCapture
        }
        vaultPath = (try? resolveVault())?.path(percentEncoded: false)
    }

    /// The vault folder, refreshing a stale bookmark.
    func resolveVault() throws -> URL? {
        guard let data = defaults.data(forKey: Key.vaultBookmark) else { return nil }
        let (url, isStale) = try VaultBookmark.resolve(data)
        if isStale, let fresh = try? VaultBookmark.make(for: url) {
            defaults.set(fresh, forKey: Key.vaultBookmark)
        }
        return url
    }

    // MARK: Choosing

    func chooseVault() {
        let panel = NSOpenPanel()
        panel.title = "Choose Your Obsidian Vault"
        panel.message = "Pick the vault folder. Meniscus only writes to the inbox note inside it."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose Vault"
        guard panel.runModal() == .OK, let url = panel.url, let bookmark = try? VaultBookmark.make(for: url) else { return }
        defaults.set(bookmark, forKey: Key.vaultBookmark)
        vaultPath = url.path(percentEncoded: false)
    }

    /// Returns a message if the chosen note isn't inside the vault.
    func chooseInbox() -> String? {
        guard let vault = try? resolveVault() else { return "Choose the vault first." }
        let panel = NSOpenPanel()
        panel.title = "Choose the Inbox Note"
        panel.directoryURL = vault
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        panel.prompt = "Choose Note"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let relative = VaultBookmark.relativePath(of: url, in: vault) else {
            return "The inbox note must be inside the vault."
        }
        inboxPath = relative
        return nil
    }
}
