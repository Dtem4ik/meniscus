import Foundation
import Observation

/// The quick capture field: what is typed and what happened to the last submit.
@Observable
final class CaptureController {
    static let shared = CaptureController()

    nonisolated enum Status: Equatable, Sendable {
        case idle
        case saving
        case failed(String)
    }

    /// True while the island shows the capture field.
    var isActive = false
    var draft = ""
    private(set) var status: Status = .idle

    let settings: CaptureSettings

    @ObservationIgnored private var hotKeyID: UInt32?
    @ObservationIgnored private var hotKeyAction: (() -> Void)?

    init(settings: CaptureSettings = .shared) {
        self.settings = settings
    }

    /// Appends the draft to the inbox note. Returns `true` when it was saved.
    func submit() async -> Bool {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let vault = try? settings.resolveVault() else {
            status = .failed(String(localized: "Choose your Obsidian vault in Settings → Capture."))
            return false
        }
        let note = vault.appending(path: settings.inboxPath, directoryHint: .notDirectory)
        status = .saving
        let isScoped = vault.startAccessingSecurityScopedResource()
        defer { if isScoped { vault.stopAccessingSecurityScopedResource() } }
        do throws(InboxWriter.WriteError) {
            try await InboxWriter.append(text, to: note, at: Date(), addDateHeading: settings.addsDateHeadings)
        } catch {
            switch error {
            case .emptyEntry: status = .idle
            case .failed(let message): status = .failed(message)
            }
            return false
        }
        draft = ""
        status = .idle
        return true
    }

    // MARK: Hot key

    /// Registers the capture shortcut and re-registers it whenever it changes in Settings.
    func bindHotKey(action: @escaping () -> Void) {
        hotKeyAction = action
        registerHotKey()
    }

    private func registerHotKey() {
        if let hotKeyID { HotKeyCenter.shared.unregister(hotKeyID) }
        hotKeyID = nil
        let hotKey = withObservationTracking {
            settings.hotKey
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.registerHotKey() }
        }
        guard let hotKey, hotKey.isValid, let action = hotKeyAction else { return }
        hotKeyID = HotKeyCenter.shared.register(hotKey, action: action)
    }
}
