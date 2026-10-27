import AppKit

/// Finds the app to show and open for whatever is playing: a music app, a browser tab, any player.
///
/// The system reports the playing process. Browsers and Electron apps often play from a helper
/// process (for example "Google Chrome Helper.app" inside "Google Chrome.app"), so the result is
/// always the outermost app bundle.
nonisolated enum SourceApplication {
    /// Lookups injected for tests; the defaults ask the system.
    struct Lookup {
        var urlForBundleIdentifier: (String) -> URL?
        var bundleURLForProcess: (Int32) -> URL?

        static var system: Lookup {
            Lookup(
                urlForBundleIdentifier: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
                bundleURLForProcess: { NSRunningApplication(processIdentifier: $0)?.bundleURL }
            )
        }
    }

    /// Tries the parent app, then the player's own bundle identifier, then its process.
    static func url(for info: NowPlayingInfo, lookup: Lookup) -> URL? {
        let candidates: [URL?] = [
            info.parentBundleIdentifier.flatMap(lookup.urlForBundleIdentifier),
            info.bundleIdentifier.flatMap(lookup.urlForBundleIdentifier),
            info.processIdentifier.flatMap(lookup.bundleURLForProcess),
        ]
        return candidates.lazy.compactMap { $0 }.first.map(outermostApplication)
    }

    /// `/Applications/Chrome.app/Contents/Frameworks/…/Helper.app` → `/Applications/Chrome.app`.
    static func outermostApplication(_ url: URL) -> URL {
        let components = url.standardizedFileURL.pathComponents
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return url }
        let path = NSString.path(withComponents: Array(components[...index]))
        return URL(filePath: path, directoryHint: .isDirectory)
    }
}
