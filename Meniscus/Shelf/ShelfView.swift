import SwiftUI

/// The shelf inside the island. Functional layout only; polish comes with the island style.
struct ShelfView: View {
    let shelf: ShelfController

    var body: some View {
        HStack(spacing: 12) {
            if shelf.items.isEmpty {
                Label("Drop files to keep them here", systemImage: "tray.and.arrow.down")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items) { item in
                            ShelfItemView(item: item, shelf: shelf)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.never)

                VStack(spacing: 8) {
                    Button {
                        shelf.airDrop(shelf.items)
                    } label: {
                        Label("AirDrop All", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        shelf.removeAll()
                    } label: {
                        Label("Clear Shelf", systemImage: "xmark.circle")
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxHeight: .infinity)
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
                .frame(width: 44, height: 44)
            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 68)
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
