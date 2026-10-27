import AppKit
import Observation
import Quartz

/// The shelf and what you can do with its files.
@Observable
final class ShelfController {
    static let shared = ShelfController()

    private(set) var store = ShelfStore()
    /// A file drag is over the notch or the island.
    var isDropTargeted = false

    var items: [ShelfItem] { store.items }
    /// The island shows the shelf while something is on it or being dragged to it.
    var isPresented: Bool { isDropTargeted || !store.isEmpty }

    @ObservationIgnored private let quickLook = QuickLookPresenter()

    func add(_ urls: [URL]) {
        guard !store.add(urls, at: Date()).isEmpty else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    func remove(_ item: ShelfItem) {
        store.remove(id: item.id)
    }

    func removeAll() {
        store.removeAll()
    }

    /// Cheap check, run when the island opens, so deleted files don't linger.
    func pruneMissingFiles() {
        store.removeMissing { FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: Actions

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func revealInFinder(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func copyPath(_ item: ShelfItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.path, forType: .string)
    }

    func airDrop(_ items: [ShelfItem]) {
        guard let service = NSSharingService(named: .sendViaAirDrop) else { return }
        let urls = items.map(\.url)
        guard service.canPerform(withItems: urls) else { return }
        NSApp.activate()
        service.perform(withItems: urls)
    }

    func quickLook(_ item: ShelfItem) {
        quickLook.show(items.map(\.url), selecting: item.url)
    }

    func icon(for item: ShelfItem) -> NSImage {
        NSWorkspace.shared.icon(forFile: item.path)
    }
}

/// Drives the system Quick Look panel directly, since the island panel is never in the
/// responder chain of an active app.
final class QuickLookPresenter: NSObject, QLPreviewPanelDataSource {
    private var urls: [URL] = []

    func show(_ urls: [URL], selecting selected: URL) {
        self.urls = urls
        guard let panel = QLPreviewPanel.shared() else { return }
        NSApp.activate()
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = urls.firstIndex(of: selected) ?? 0
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        let url = MainActor.assumeIsolated { urls[index] }
        return url as NSURL
    }
}
