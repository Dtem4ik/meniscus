import Foundation

/// SF Symbols offered for modes. macOS has no public list of every symbol, so this is a picked
/// set; any other symbol name typed into the search, or into config.json, works too.
nonisolated enum SymbolCatalog {
    static let symbols: [String] = [
        // Work
        "briefcase", "folder", "doc", "doc.text", "note.text", "list.bullet", "checklist",
        "checkmark.circle", "calendar", "clock", "alarm", "timer", "hourglass", "tray", "archivebox",
        "paperclip", "link", "pin", "bookmark", "tag", "flag", "bell", "envelope", "paperplane",
        "bubble.left", "bubble.left.and.bubble.right", "bubble.left.and.text.bubble.right", "phone",
        "video", "person", "person.2", "house", "building.2", "globe", "network", "magnifyingglass",
        "chart.bar", "chart.pie", "chart.line.uptrend.xyaxis", "dollarsign.circle", "creditcard",
        "cart", "bag", "gift",
        // Making things
        "pencil", "highlighter", "paintbrush", "paintpalette", "scribble", "photo", "camera", "film",
        "music.note", "headphones", "guitars", "mic", "waveform", "book", "book.closed",
        "books.vertical", "text.book.closed", "graduationcap", "lightbulb", "brain",
        "brain.head.profile", "sparkles", "wand.and.stars", "star", "heart",
        // Code and devices
        "terminal", "chevron.left.forwardslash.chevron.right", "curlybraces", "hammer",
        "wrench.and.screwdriver", "gearshape", "cpu", "server.rack", "externaldrive", "keyboard",
        "desktopcomputer", "laptopcomputer", "display", "iphone", "ipad", "applewatch", "ladybug",
        "ant", "shippingbox", "square.stack.3d.up", "cube", "puzzlepiece",
        // Life
        "moon", "moon.stars", "sun.max", "sunrise", "cloud", "cloud.rain", "snowflake", "flame",
        "leaf", "drop", "bolt", "cup.and.saucer", "fork.knife", "bed.double", "figure.walk",
        "figure.run", "figure.mind.and.body", "dumbbell", "bicycle", "car", "airplane", "tram",
        "map", "location", "mappin", "gamecontroller", "tv", "theatermasks", "pawprint", "cross.case",
        "pills",
        // Symbols
        "square.grid.2x2", "circle.grid.3x3", "square.and.arrow.down", "arrow.down.circle",
        "arrow.up.circle", "arrow.clockwise", "play.circle", "pause.circle", "power", "lock", "key",
        "shield", "eye", "hand.raised", "hand.thumbsup", "face.smiling", "infinity", "number", "at",
        "command", "questionmark.circle", "exclamationmark.triangle", "info.circle", "plus.circle",
        "xmark.circle", "trash",
    ]

    /// Symbols whose name contains every word of `query` ("arrow down" finds
    /// "arrow.down.circle"). `isValid` decides whether a typed name outside the catalog is a real
    /// symbol; it comes first when it is.
    static func search(_ query: String, isValid: (String) -> Bool) -> [String] {
        let words = query.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "." })
            .map(String.init)
        guard !words.isEmpty else { return symbols }
        let matches = symbols.filter { name in words.allSatisfy { name.contains($0) } }
        let typed = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !matches.contains(typed), isValid(typed) {
            return [typed] + matches
        }
        return matches
    }
}
