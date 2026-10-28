import Carbon.HIToolbox
import Foundation

/// Reports keyboard input source changes, with the short label the island shows. Listens to the
/// system's distributed notification for the change, so nothing runs in between.
final class InputSourceMonitor {
    var onChange: ((String) -> Void)?

    private var observer: (any NSObjectProtocol)?

    func start() {
        guard observer == nil else { return }
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
    }

    private func inputSourceChanged() {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
        let languages = Self.property(kTISPropertyInputSourceLanguages, of: source) as? [String] ?? []
        let name = Self.property(kTISPropertyLocalizedName, of: source) as? String ?? ""
        onChange?(InputSourceLabel.shortName(languages: languages, localizedName: name))
    }

    private static func property(_ key: CFString, of source: TISInputSource) -> AnyObject? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
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
