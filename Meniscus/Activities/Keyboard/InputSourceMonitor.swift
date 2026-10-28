import Carbon.HIToolbox
import Foundation

/// Reports keyboard input source changes, with the short label the island shows. Listens to the
/// system's distributed notification for the change, so nothing runs in between.
///
/// The notification can arrive before the new source is current, which showed the layout being
/// left. So the source is read a moment later, and shown only when it really differs from the
/// last one.
final class InputSourceMonitor {
    var onChange: ((String) -> Void)?

    /// How long after the notification the current source is read.
    static let settleDelay: Duration = .milliseconds(120)

    private var observer: (any NSObjectProtocol)?
    private var readTask: Task<Void, Never>?
    private var filter = InputSourceChangeFilter()

    func start() {
        guard observer == nil else { return }
        // The source at start is the baseline, not a change.
        if let current = Self.current() { _ = filter.accept(current.id) }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.inputSourceChanged() }
        }
    }

    func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        readTask?.cancel()
    }

    private func inputSourceChanged() {
        readTask?.cancel()
        readTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self, let current = Self.current() else { return }
            if self.filter.accept(current.id) { self.onChange?(current.label) }
        }
    }

    private static func current() -> (id: String, label: String)? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        let id = property(kTISPropertyInputSourceID, of: source) as? String ?? ""
        let languages = property(kTISPropertyInputSourceLanguages, of: source) as? [String] ?? []
        let name = property(kTISPropertyLocalizedName, of: source) as? String ?? ""
        return (id, InputSourceLabel.shortName(languages: languages, localizedName: name))
    }

    private static func property(_ key: CFString, of source: TISInputSource) -> AnyObject? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }
}

/// Lets a source through only when it differs from the last one let through, so repeated or
/// early notifications don't show anything. Pure, so it is unit tested.
nonisolated struct InputSourceChangeFilter: Equatable, Sendable {
    private(set) var last: String?

    mutating func accept(_ id: String) -> Bool {
        guard id != last else { return false }
        last = id
        return true
    }
}

/// Two letters for an input source, like the menu bar: EN, РУ, DE, УК…, written in the
/// language itself. Pure, so it is unit tested.
nonisolated enum InputSourceLabel {
    static func shortName(languages: [String], localizedName: String) -> String {
        if let language = languages.first {
            let locale = Locale(identifier: language)
            let endonym = locale.localizedString(forLanguageCode: language) ?? language
            return String(endonym.prefix(2)).uppercased(with: locale)
        }
        return String(localizedName.prefix(2)).uppercased()
    }
}
