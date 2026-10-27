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

    @Test func removesByIDAndMissingFiles() {
        var store = ShelfStore()
        store.add([file("keep.txt"), file("gone.txt"), file("drop.txt")], at: date)
        let drop = store.items.last!
        store.remove(id: drop.id)
        store.removeMissing { !$0.hasSuffix("gone.txt") }
        #expect(store.items.map(\.name) == ["keep.txt"])
        store.removeAll()
        #expect(store.isEmpty)
    }
}
