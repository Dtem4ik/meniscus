import Foundation

/// Remembers the chosen folder or note across launches, and follows it when it is moved or
/// renamed. Security-scoped bookmarks keep working if the app is ever sandboxed; outside the
/// sandbox a plain bookmark is used as a fallback.
nonisolated enum CaptureBookmark {
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
}
