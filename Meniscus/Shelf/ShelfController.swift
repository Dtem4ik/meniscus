import AppKit
import Carbon.HIToolbox
import Observation
import Quartz
import QuickLookThumbnailing

/// The shelf and what you can do with its files.
@Observable
final class ShelfController {
    static let shared = ShelfController()

    private(set) var store = ShelfStore() {
        didSet {
            guard store.items.count != oldValue.items.count else { return }
            onItemsChange?(store.items.count)
        }
    }
    /// A file drag is over the notch or the island.
    var isDropTargeted = false
    /// A file drag is near the top of the screen, heading for the notch.
    var isDragApproaching = false
    /// The tile under the pointer; Space opens it in Quick Look.
    var hoveredItemID: ShelfItem.ID?
    /// Real previews of images, PDFs, videos and documents, made in the background.
    private(set) var thumbnails: [ShelfItem.ID: NSImage] = [:]

    var items: [ShelfItem] { store.items }

    /// Called with the number of files whenever it changes, for the notch's shelf indicator.
    @ObservationIgnored var onItemsChange: ((Int) -> Void)?

    @ObservationIgnored private let quickLook = QuickLookPresenter()
    @ObservationIgnored private var thumbnailRequests: Set<ShelfItem.ID> = []

    /// Size of the thumbnails, in points.
    static let thumbnailSize: CGFloat = 44

    func add(_ urls: [URL]) {
        guard !store.add(urls, at: Date()).isEmpty else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        loadThumbnails()
    }

    func remove(_ item: ShelfItem) {
        store.remove(id: item.id)
        thumbnails[item.id] = nil
    }

    func removeAll() {
        store.removeAll()
        thumbnails.removeAll()
    }

    /// Cheap check, run when the island opens, so deleted files don't linger.
    func pruneMissingFiles() {
        store.removeMissing { FileManager.default.fileExists(atPath: $0) }
        thumbnails = thumbnails.filter { id, _ in items.contains { $0.id == id } }
    }

    // MARK: Previews

    /// The file's preview if there is one, otherwise its icon.
    func image(for item: ShelfItem) -> NSImage {
        thumbnails[item.id] ?? NSWorkspace.shared.icon(forFile: item.path)
    }

    func hasThumbnail(_ item: ShelfItem) -> Bool {
        thumbnails[item.id] != nil
    }

    /// Asks Quick Look for a preview of every file that has none yet. Files without one (a
    /// folder, an app, an unknown type) keep their icon.
    func loadThumbnails() {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        for item in items where thumbnails[item.id] == nil && !thumbnailRequests.contains(item.id) {
            thumbnailRequests.insert(item.id)
            Task {
                let thumbnail = await Self.thumbnail(for: item.url, size: Self.thumbnailSize, scale: scale)
                thumbnailRequests.remove(item.id)
                guard let thumbnail, items.contains(where: { $0.id == item.id }) else { return }
                thumbnails[item.id] = NSImage(cgImage: thumbnail.image, size: .zero)
            }
        }
    }

    @concurrent
    nonisolated private static func thumbnail(for url: URL, size: CGFloat, scale: CGFloat) async -> CGImageBox? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .thumbnail
        )
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation.map { CGImageBox(image: $0.cgImage) })
            }
        }
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

    /// Space on a tile, as in Finder: opens Quick Look on the hovered file, or closes it.
    /// Returns `false` when there was nothing to do.
    func toggleQuickLookForHoveredItem() -> Bool {
        if quickLook.isVisible {
            quickLook.close()
            return true
        }
        guard let item = items.first(where: { $0.id == hoveredItemID }) else { return false }
        quickLook(item)
        return true
    }
}

/// Carries a thumbnail from Quick Look's queue to the main actor.
private nonisolated final class CGImageBox: @unchecked Sendable {
    let image: CGImage
    init(image: CGImage) { self.image = image }
}

/// Drives the system Quick Look panel directly, since the island panel is never in the
/// responder chain of an active app. Space or Escape closes it; the arrow keys move between the
/// shelf's files.
final class QuickLookPresenter: NSObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    private var urls: [URL] = []

    var isVisible: Bool { QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible }

    func show(_ urls: [URL], selecting selected: URL) {
        self.urls = urls
        guard let panel = QLPreviewPanel.shared() else { return }
        NSApp.activate()
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = urls.firstIndex(of: selected) ?? 0
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        QLPreviewPanel.shared()?.orderOut(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls[index] as NSURL
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let panel, let event, event.type == .keyDown else { return false }
        switch Int(event.keyCode) {
        case kVK_Space:
            // Space closes, as in Finder.
            panel.orderOut(nil)
            return true
        case kVK_LeftArrow, kVK_RightArrow:
            guard !urls.isEmpty else { return false }
            let step = Int(event.keyCode) == kVK_LeftArrow ? -1 : 1
            panel.currentPreviewItemIndex = (panel.currentPreviewItemIndex + step + urls.count) % urls.count
            return true
        default:
            return false
        }
    }
}
