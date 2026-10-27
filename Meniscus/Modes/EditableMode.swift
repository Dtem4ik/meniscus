import Foundation

/// A form-friendly copy of a mode for the Settings editor: every field is a plain string, so
/// switching an action's type keeps what was typed.
nonisolated struct EditableMode: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var symbol: String
    var actions: [EditableAction]

    init(_ mode: Mode) {
        id = mode.id
        name = mode.name
        symbol = mode.symbol
        actions = mode.actions.map(EditableAction.init)
    }

    init(newModeNamed name: String, existingIDs: Set<String>) {
        var id = Mode.slug(from: name)
        var suffix = 2
        while existingIDs.contains(id) {
            id = "\(Mode.slug(from: name))-\(suffix)"
            suffix += 1
        }
        self.id = id
        self.name = name
        symbol = Mode.defaultSymbol
        // One button, one action is the common case, so a new mode starts with one to fill in.
        actions = [EditableAction()]
    }

    var mode: Mode {
        Mode(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            symbol: symbol.trimmingCharacters(in: .whitespaces).isEmpty ? Mode.defaultSymbol : symbol,
            actions: actions.map(\.action)
        )
    }
}

nonisolated struct EditableAction: Identifiable, Equatable, Sendable {
    var id = UUID()
    var kind: ModeAction.Kind
    /// The URL, bundle id, path or shortcut name, depending on `kind`.
    var value: String
    /// Text passed to a shortcut; ignored for other kinds.
    var input: String

    init(kind: ModeAction.Kind = .url, value: String = "", input: String = "") {
        self.kind = kind
        self.value = value
        self.input = input
    }

    init(_ action: ModeAction) {
        switch action {
        case .openURL(let url): self.init(kind: .url, value: url)
        case .openApp(let bundleID): self.init(kind: .app, value: bundleID)
        case .openFile(let path): self.init(kind: .file, value: path)
        case .runShortcut(let name, let input): self.init(kind: .shortcut, value: name, input: input ?? "")
        }
    }

    var action: ModeAction {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .url: return .openURL(value)
        case .app: return .openApp(bundleID: value)
        case .file: return .openFile(path: value)
        case .shortcut: return .runShortcut(name: value, input: input.isEmpty ? nil : input)
        }
    }
}

extension ModeAction.Kind {
    var title: String {
        switch self {
        case .url: String(localized: "Open URL")
        case .app: String(localized: "Open App")
        case .file: String(localized: "Open File or Folder")
        case .shortcut: String(localized: "Run Shortcut")
        }
    }

    /// How to open things in other apps with a link, shown under URL actions.
    static var urlHint: String {
        String(localized: "Links can open apps directly. Claude app: claude://claude.ai/new starts a chat (add ?q= with URL-encoded text to prefill it), claude://claude.ai/project/ID opens a project and claude://claude.ai/chat/ID a chat. The ID is the end of the project's or chat's claude.ai address.")
    }

    var placeholder: String {
        switch self {
        case .url: String(localized: "https://…, claude://… or obsidian://…")
        case .app: String(localized: "Bundle id, e.g. com.apple.Notes")
        case .file: "~/Documents/Plan.md"
        case .shortcut: String(localized: "Shortcut name")
        }
    }
}
