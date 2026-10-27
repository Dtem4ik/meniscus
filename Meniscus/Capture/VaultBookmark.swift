import Foundation

/// Remembers the vault folder across launches. Security-scoped bookmarks keep working if the app
/// is ever sandboxed; outside the sandbox a plain bookmark is used as a fallback.
nonisolated enum VaultBookmark {
    static func make(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }

    /// Resolves the bookmark. `isStale` means it should be recreated from the returned URL.
    static func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            return (url, isStale)
        } catch {
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            return (url, isStale)
        }
    }

    /// The inbox note's path inside the vault, or `nil` if it is outside.
    static func relativePath(of file: URL, in vault: URL) -> String? {
        let vaultComponents = vault.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let fileComponents = file.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard fileComponents.count > vaultComponents.count,
              Array(fileComponents.prefix(vaultComponents.count)) == vaultComponents
        else { return nil }
        return fileComponents.dropFirst(vaultComponents.count).joined(separator: "/")
    }
}
