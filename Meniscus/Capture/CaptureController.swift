import Foundation
import Observation

/// The quick capture field: what is typed and what happened to the last submit.
@Observable
final class CaptureController {
    static let shared = CaptureController()

    nonisolated enum Status: Equatable, Sendable {
        case idle
        case saving
        /// Shown for a moment before the island closes.
        case saved
        case failed(String)
    }

    /// True while the island shows the capture field.
    private(set) var isActive = false
    var draft = ""
    private(set) var status: Status = .idle

    let settings: CaptureSettings

    @ObservationIgnored private var hotKeyID: UInt32?
    @ObservationIgnored private var hotKeyAction: (() -> Void)?

    init(settings: CaptureSettings = .shared) {
        self.settings = settings
    }

    func begin() {
        status = .idle
        isActive = true
    }

    /// Closes the field. An unsaved draft is kept for next time.
    func end() {
        isActive = false
    }

    /// Saves the draft where Settings say. Returns `true` when it was saved.
    func submit() async -> Bool {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, status != .saving else { return false }
        status = .saving
        let result: Result<Void, InboxWriter.WriteError>
        switch settings.destination {
        case .noteInFolder:
            guard let folder = settings.resolvedFolder() else {
                status = .failed(String(localized: "Choose a folder in Settings → Capture."))
                return false
            }
            result = await Self.withAccess(to: folder) { () async throws(InboxWriter.WriteError) in
                _ = try await InboxWriter.createNote(text, in: folder, at: Date())
            }
        case .lineInNote:
            guard let note = settings.resolvedNote() else {
                status = .failed(String(localized: "Choose a note in Settings → Capture."))
                return false
            }
            let addsHeading = settings.addsDateHeadings
            result = await Self.withAccess(to: note) { () async throws(InboxWriter.WriteError) in
                try await InboxWriter.append(text, to: note, at: Date(), addDateHeading: addsHeading)
            }
        }
        switch result {
        case .success:
            draft = ""
            status = .saved
            return true
        case .failure(.emptyEntry):
            status = .idle
        case .failure(.failed(let message)):
            status = .failed(message)
        }
        return false
    }

    private static func withAccess(
        to url: URL,
        _ write: () async throws(InboxWriter.WriteError) -> Void
    ) async -> Result<Void, InboxWriter.WriteError> {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        do throws(InboxWriter.WriteError) {
            try await write()
            return .success(())
        } catch {
            return .failure(error)
        }
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
