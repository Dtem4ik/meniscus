import Foundation

nonisolated struct ShelfItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var url: URL
    var addedAt: Date
    /// Finds the file again after it was moved or renamed.
    var bookmark: Data?

    var name: String { url.lastPathComponent }
    var path: String { url.path(percentEncoded: false) }
}

/// The files lying on the shelf. Files are only referenced, never copied or moved, so the shelf
/// can't lose anything. Pure value type for unit tests.
nonisolated struct ShelfStore: Equatable, Sendable {
    /// Oldest items fall off beyond this.
    static let capacity = 12

    private(set) var items: [ShelfItem] = []

    var isEmpty: Bool { items.isEmpty }

    /// Adds file URLs, newest last. A file already on the shelf moves to the end instead of
    /// appearing twice. Returns the items that were added or moved.
    @discardableResult
    mutating func add(
        _ urls: [URL],
        at date: Date,
        makeID: () -> UUID = UUID.init,
        makeBookmark: (URL) -> Data? = { _ in nil }
    ) -> [ShelfItem] {
        var touched: [ShelfItem] = []
        for url in urls where url.isFileURL {
            let key = Self.key(for: url)
            items.removeAll { Self.key(for: $0.url) == key }
            let item = ShelfItem(id: makeID(), url: url.standardizedFileURL, addedAt: date, bookmark: makeBookmark(url))
            items.append(item)
            touched.append(item)
        }
        if items.count > Self.capacity {
            items.removeFirst(items.count - Self.capacity)
        }
        return touched
    }

    mutating func remove(id: ShelfItem.ID) {
        items.removeAll { $0.id == id }
    }

    /// Follows files that moved and drops files that are gone. `locate` returns where an item's
    /// file is now, or `nil` once it was deleted or put in the Trash. Returns whether anything
    /// changed.
    @discardableResult
    mutating func refresh(locate: (ShelfItem) -> URL?) -> Bool {
        var changed = false
        items = items.compactMap { item in
            guard let url = locate(item)?.standardizedFileURL else {
                changed = true
                return nil
            }
            guard url != item.url else { return item }
            changed = true
            var moved = item
            moved.url = url
            return moved
        }
        return changed
    }

    /// Whether `path` is inside a Trash: the home folder's, or one on another volume.
    static func isInTrash(_ path: String, homeTrash: String?) -> Bool {
        if let homeTrash, path.hasPrefix(homeTrash.hasSuffix("/") ? homeTrash : homeTrash + "/") { return true }
        return path.contains("/.Trashes/")
    }

    mutating func removeAll() {
        items.removeAll()
    }

    private static func key(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
    }
}
