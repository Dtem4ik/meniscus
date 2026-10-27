import Foundation
import Testing
@testable import Meniscus

struct ShelfStoreTests {
    private let date = Date(timeIntervalSinceReferenceDate: 0)

    private func file(_ name: String) -> URL {
        URL(filePath: "/tmp/shelf-tests/\(name)")
    }

    @Test func addsFilesInOrder() {
        var store = ShelfStore()
        store.add([file("a.pdf"), file("b.png")], at: date)
        #expect(store.items.map(\.name) == ["a.pdf", "b.png"])
    }

    @Test func addingTheSameFileMovesItToTheEnd() {
        var store = ShelfStore()
        store.add([file("a.pdf"), file("b.png")], at: date)
        store.add([URL(filePath: "/tmp/shelf-tests/./a.pdf")], at: date)
        #expect(store.items.map(\.name) == ["b.png", "a.pdf"])
    }

    @Test func ignoresNonFileURLs() {
        var store = ShelfStore()
        let added = store.add([URL(string: "https://example.com/a.pdf")!], at: date)
        #expect(added.isEmpty)
        #expect(store.isEmpty)
    }

    @Test func oldestFallOffBeyondCapacity() {
        var store = ShelfStore()
        store.add((0..<(ShelfStore.capacity + 3)).map { file("\($0).txt") }, at: date)
        #expect(store.items.count == ShelfStore.capacity)
        #expect(store.items.first?.name == "3.txt")
    }

    @Test func removesByIDAndDeletedFiles() {
        var store = ShelfStore()
        store.add([file("keep.txt"), file("gone.txt"), file("drop.txt")], at: date)
        let drop = store.items.last!
        store.remove(id: drop.id)
        let changed = store.refresh { $0.name == "gone.txt" ? nil : $0.url }
        #expect(changed)
        #expect(store.items.map(\.name) == ["keep.txt"])
        store.removeAll()
        #expect(store.isEmpty)
    }

    @Test func followsMovedFiles() {
        var store = ShelfStore()
        store.add([file("a.pdf"), file("b.png")], at: date)
        let id = store.items[0].id
        let changed = store.refresh { $0.name == "a.pdf" ? URL(filePath: "/tmp/elsewhere/renamed.pdf") : $0.url }
        #expect(changed)
        #expect(store.items[0].id == id)
        #expect(store.items[0].name == "renamed.pdf")
        #expect(!store.refresh { $0.url })
    }

    @Test func recognizesTheTrash() {
        #expect(ShelfStore.isInTrash("/tmp/home/.Trash/a.pdf", homeTrash: "/tmp/home/.Trash"))
        #expect(ShelfStore.isInTrash("/Volumes/Disk/.Trashes/501/a.pdf", homeTrash: "/tmp/home/.Trash"))
        #expect(!ShelfStore.isInTrash("/tmp/home/.Trash-notes/a.pdf", homeTrash: "/tmp/home/.Trash"))
        #expect(!ShelfStore.isInTrash("/tmp/home/Documents/a.pdf", homeTrash: "/tmp/home/.Trash"))
    }

    /// A real file: moving it keeps it on the shelf at its new place, deleting it drops it.
    @MainActor
    @Test func bookmarksFollowRealFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "shelf-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = folder.appending(path: "Отчёт за год.pdf")
        try Data("x".utf8).write(to: original)
        var store = ShelfStore()
        store.add([original], at: date, makeBookmark: { try? $0.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) })

        let moved = folder.appending(path: "Moved report.pdf")
        try FileManager.default.moveItem(at: original, to: moved)
        store.refresh { ShelfController.locate($0, homeTrash: nil) }
        #expect(store.items.first?.name == "Moved report.pdf")

        try FileManager.default.removeItem(at: moved)
        store.refresh { ShelfController.locate($0, homeTrash: nil) }
        #expect(store.isEmpty)
    }
}

@MainActor
struct ShelfSettingTests {
    @Test func shelfIsOnByDefault() {
        let defaults = UserDefaults(suiteName: "meniscus-shelf-\(UUID().uuidString)")!
        #expect(AppSettings(defaults: defaults).showShelf)
    }

    @Test func turnedOffShelfShowsNothingButKeepsItsFiles() {
        let shelf = ShelfController()
        var reported: [Int] = []
        shelf.onItemsChange = { reported.append($0) }
        shelf.add([URL(filePath: "/tmp/shelf-setting/a.txt")])
        #expect(shelf.visibleCount == 1)
        shelf.isEnabled = false
        #expect(shelf.visibleCount == 0)
        #expect(shelf.items.count == 1)
        shelf.isEnabled = true
        #expect(reported == [1, 0, 1])
    }
}
