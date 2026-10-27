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
        .onAppear { shelf.pruneMissingFiles() }
    }
}

private struct ShelfItemView: View {
    let item: ShelfItem
    let shelf: ShelfController

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: shelf.icon(for: item))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contentShape(Rectangle())
        .help(item.path)
        // Drag the file out to Finder, Mail, a chat… The file itself never moves.
        .draggable(item.url)
        .onTapGesture(count: 2) { shelf.open(item) }
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
}
