import SwiftUI

/// Small dots under the expanded island, one per page; a click on a dot opens its page, for
/// mice without gestures.
struct PageDots: View {
    let pages: [IslandPage]
    let selected: IslandPage
    var select: (IslandPage) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(pages, id: \.self) { page in
                Button {
                    select(page)
                } label: {
                    Circle()
                        .fill(page == selected ? .white : .white.opacity(0.3))
                        .frame(width: 5, height: 5)
                        .frame(width: 14, height: 14)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(page.title)
                .accessibilityLabel(Text(page.title))
                .accessibilityAddTraits(page == selected ? .isSelected : [])
            }
        }
        .animation(Motion.pageDots, value: selected)
    }
}
