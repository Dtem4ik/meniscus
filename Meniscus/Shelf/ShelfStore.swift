import Foundation

nonisolated struct ShelfItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var url: URL
    var addedAt: Date

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
    mutating func add(_ urls: [URL], at date: Date, makeID: () -> UUID = UUID.init) -> [ShelfItem] {
        var touched: [ShelfItem] = []
        for url in urls where url.isFileURL {
            let key = Self.key(for: url)
            items.removeAll { Self.key(for: $0.url) == key }
            let item = ShelfItem(id: makeID(), url: url.standardizedFileURL, addedAt: date)
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

    /// Drops items whose files were deleted or moved away.
    mutating func removeMissing(fileExists: (String) -> Bool) {
        items.removeAll { !fileExists($0.path) }
    }

    mutating func removeAll() {
        items.removeAll()
    }

    private static func key(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
    }
}
