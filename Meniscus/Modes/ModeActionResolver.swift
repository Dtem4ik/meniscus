import Foundation

/// What an action turns into once `~` is expanded and Shortcuts names are encoded.
nonisolated enum ResolvedAction: Equatable, Sendable {
    case url(URL)
    case application(bundleID: String)
    case file(URL)
    case quickCapture
}

/// Pure translation from config actions to things `NSWorkspace` can open.
nonisolated enum ModeActionResolver {
    static func resolve(_ action: ModeAction, homeDirectory: URL = URL(filePath: NSHomeDirectory())) -> ResolvedAction? {
        switch action {
        case .openURL(let string):
            return url(from: string).map(ResolvedAction.url)
        case .openApp(let bundleID):
            let trimmed = bundleID.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : .application(bundleID: trimmed)
        case .openFile(let path):
            return fileURL(from: path, homeDirectory: homeDirectory).map(ResolvedAction.file)
        case .runShortcut(let name, let input):
            return shortcutURL(name: name, input: input).map(ResolvedAction.url)
        case .quickCapture:
            return .quickCapture
        }
    }

    /// Why an action can't run, or `nil` if it looks fine. Doesn't touch the file system.
    static func problem(with action: ModeAction) -> String? {
        switch action {
        case .openURL(let string):
            url(from: string) == nil
                ? String(localized: "“\(string)” is not a URL with a scheme (like https:// or obsidian://).")
                : nil
        case .openApp(let bundleID):
            bundleID.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "The app has no bundle id.") : nil
        case .openFile(let path):
            path.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "The file has no path.") : nil
        case .runShortcut(let name, _):
            name.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "The shortcut has no name.") : nil
        case .quickCapture:
            nil
        }
    }

    static func url(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty else { return nil }
        // `file:` URLs belong in a file action, where `~` is expanded.
        return url
    }

    static func fileURL(from path: String, homeDirectory: URL) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "~" { return homeDirectory }
        if trimmed.hasPrefix("~/") {
            return homeDirectory.appending(path: String(trimmed.dropFirst(2)))
        }
        guard trimmed.hasPrefix("/") else { return nil }
        return URL(filePath: trimmed)
    }

    /// The inverse of `fileURL(from:)`: a path inside the home folder is written with `~`, so a
    /// chosen file keeps working for another user and the config doesn't contain the user name.
    static func configPath(for url: URL, homeDirectory: URL = URL(filePath: NSHomeDirectory())) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        var home = homeDirectory.standardizedFileURL.path(percentEncoded: false)
        if home.hasSuffix("/") { home.removeLast() }
        var result = path
        if path == home || path == home + "/" {
            result = "~"
        } else if path.hasPrefix(home + "/") {
            result = "~/" + path.dropFirst(home.count + 1)
        }
        // Folders come back with a trailing slash; the config doesn't need it.
        if result.count > 1, result.hasSuffix("/") { result.removeLast() }
        return result
    }

    /// `shortcuts://run-shortcut?name=…&input=text&text=…`, the URL scheme documented by
    /// the Shortcuts app.
    static func shortcutURL(name: String, input: String?) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var query = "name=\(percentEncode(trimmed))"
        if let input, !input.isEmpty {
            query += "&input=text&text=\(percentEncode(input))"
        }
        return URL(string: "shortcuts://run-shortcut?\(query)")
    }

    /// Encodes everything but RFC 3986 unreserved characters, so "&", "+" and "=" in a
    /// shortcut name can't break the query.
    static func percentEncode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: unreserved) ?? string
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )
}
