import SwiftUI

/// The shelf inside the island: a tile per file, sized to how many there are, and two quiet
/// buttons in the island's control style.
struct ShelfView: View {
    let shelf: ShelfController
    let metrics: IslandMetrics

    var body: some View {
        Group {
            if shelf.items.isEmpty {
                Label("Drop files to keep them here", systemImage: "tray.and.arrow.down")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: metrics.shelfTileSpacing) {
                    ScrollView(.horizontal) {
                        HStack(spacing: metrics.shelfTileSpacing) {
                            ForEach(shelf.items) { item in
                                ShelfItemView(item: item, shelf: shelf)
                                    .frame(width: metrics.shelfTileWidth)
                            }
                        }
                    }
                    .scrollIndicators(.never)

                    VStack(spacing: 2) {
                        Button {
                            shelf.airDrop(shelf.items)
                        } label: {
                            Label("AirDrop All", systemImage: "square.and.arrow.up")
                        }
                        .help("AirDrop All")
                        Button {
                            shelf.removeAll()
                        } label: {
                            Label("Clear Shelf", systemImage: "xmark")
                        }
                        .help("Clear Shelf")
                    }
                    .buttonStyle(IslandControlStyle(size: 13))
                    .frame(width: metrics.shelfControlsWidth)
                }
                .padding(.horizontal, metrics.shelfHorizontalPadding)
                .frame(maxHeight: .infinity)
            }
        }
        .onAppear {
            shelf.refreshLocations()
            shelf.loadThumbnails()
        }
    }
}

private struct ShelfItemView: View {
    let item: ShelfItem
    let shelf: ShelfController

    var body: some View {
        VStack(spacing: 4) {
            preview
                .frame(width: ShelfController.thumbnailSize, height: ShelfController.thumbnailSize)
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 4)
        .background(
            .white.opacity(shelf.hoveredItemID == item.id ? 0.1 : 0),
            in: .rect(cornerRadius: 10, style: .continuous)
        )
        .contentShape(.rect)
        .onHover { isInside in
            if isInside {
                shelf.hoveredItemID = item.id
            } else if shelf.hoveredItemID == item.id {
                shelf.hoveredItemID = nil
            }
        }
        .help(item.path)
        // Drag the file out to Finder, Mail, a chat… The file itself never moves.
        .draggable(item.url)
        // A click previews the file in Quick Look, a double-click opens it.
        .gesture(
            TapGesture(count: 2).onEnded { shelf.open(item) }
                .exclusively(before: TapGesture().onEnded { shelf.quickLook(item) })
        )
        .contextMenu {
            Button("Open") { shelf.open(item) }
            Button("Quick Look") { shelf.quickLook(item) }
            Button("AirDrop") { shelf.airDrop([item]) }
            Button("Copy Path") { shelf.copyPath(item) }
            Button("Show in Finder") { shelf.revealInFinder(item) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(item) }
        }
    }

    /// A real preview gets rounded corners like Finder's; an icon is shown as it is.
    @ViewBuilder
    private var preview: some View {
        let image = Image(nsImage: shelf.image(for: item)).resizable().aspectRatio(contentMode: .fit)
        if shelf.hasThumbnail(item) {
            image.clipShape(.rect(cornerRadius: 5, style: .continuous))
        } else {
            image
        }
    }
}

/// A large target while files are dragged toward the notch, so they can be dropped long before
/// the pointer reaches the top edge.
struct ShelfDropZone: View {
    let isTargeted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(.white.opacity(isTargeted ? 0.8 : 0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .background(.white.opacity(isTargeted ? 0.08 : 0), in: .rect(cornerRadius: 20, style: .continuous))
            .overlay {
                Label("Drop files to keep them here", systemImage: "tray.and.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(isTargeted ? 1 : 0.7))
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 18)
            .animation(Motion.controlHover, value: isTargeted)
    }
}
