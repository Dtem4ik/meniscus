import CoreGraphics

/// A page of the expanded island. Swiping or clicking the page dots moves between them.
nonisolated enum IslandPage: Equatable, Hashable, Sendable {
    case nowPlaying
    case home
    case shelf

    var title: String {
        switch self {
        case .nowPlaying: String(localized: "Player")
        case .home: String(localized: "Home")
        case .shelf: String(localized: "Shelf")
        }
    }
}

nonisolated enum IslandPages {
    /// The pages there is something to show on, left to right: the player while something
    /// plays, then the shelf while it holds files, then the home view, always there.
    static func available(isPlaying: Bool, hasShelfItems: Bool) -> [IslandPage] {
        (isPlaying ? [.nowPlaying] : []) + (hasShelfItems ? [.shelf] : []) + [.home]
    }

    /// The page the island opens on: the player while something plays, otherwise the home view.
    static func defaultPage(in pages: [IslandPage]) -> IslandPage {
        pages.contains(.nowPlaying) ? .nowPlaying : .home
    }

    /// `page` if it is still there, otherwise the default.
    static func resolve(_ page: IslandPage, in pages: [IslandPage]) -> IslandPage {
        pages.contains(page) ? page : defaultPage(in: pages)
    }

    /// The page `offset` places away, or `nil` past either end.
    static func page(from page: IslandPage, by offset: Int, in pages: [IslandPage]) -> IslandPage? {
        guard let index = pages.firstIndex(of: page), pages.indices.contains(index + offset) else { return nil }
        return pages[index + offset]
    }
}

/// Turns a two-finger trackpad swipe into one page turn: fingers left for the next page, right
/// for the previous one, like swiping between pages elsewhere on the Mac. Pure, so it is unit
/// tested; the controller feeds it scroll events.
nonisolated struct PageSwipeTracker {
    nonisolated enum Phase: Sendable {
        case began, changed, ended, momentum, other
    }

    nonisolated enum Turn: Equatable, Sendable {
        case next, previous
    }

    /// How far the fingers travel before the page turns.
    static let threshold: CGFloat = 36

    private var horizontal: CGFloat = 0
    private var vertical: CGFloat = 0
    private var didTurn = false

    /// `fingerDeltaX` is positive when the fingers move right, whatever the scroll direction
    /// setting.
    mutating func handle(_ phase: Phase, fingerDeltaX: CGFloat, deltaY: CGFloat) -> Turn? {
        switch phase {
        case .began:
            horizontal = 0
            vertical = 0
            didTurn = false
        case .changed:
            break
        case .ended:
            horizontal = 0
            vertical = 0
            didTurn = false
            return nil
        case .momentum, .other:
            return nil
        }
        guard !didTurn else { return nil }
        horizontal += fingerDeltaX
        vertical += deltaY
        // Mostly vertical: a scroll, not a swipe.
        guard abs(horizontal) > abs(vertical) else { return nil }
        if horizontal <= -Self.threshold {
            didTurn = true
            return .next
        }
        if horizontal >= Self.threshold {
            didTurn = true
            return .previous
        }
        return nil
    }
}
