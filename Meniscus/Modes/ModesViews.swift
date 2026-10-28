import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Mode buttons inside the island.
struct ModesBar: View {
    let store: ModesStore
    /// How many modes the row shows; the rest stay in Settings.
    static let maximumVisible = 5

    var body: some View {
        if !store.modes.isEmpty {
            HStack(spacing: 4) {
                ForEach(store.modes.prefix(Self.maximumVisible)) { mode in
                    Button {
                        ModeRunner.run(mode)
                    } label: {
                        Label(mode.name, systemImage: mode.symbol)
                    }
                    .buttonStyle(IslandControlStyle(size: 15))
                    // The name shows on hover only.
                    .help(mode.name)
                }
            }
            // Line the symbols up with the time above, not their hover circles.
            .padding(.leading, -9)
        }
    }
}

/// Settings → Modes, in the grouped style of System Settings. Built for the common case, one
/// button that opens one thing: a name, a symbol and what to open. More actions can be chained
/// with "Add Another Action".
struct ModesSettingsView: View {
    let store: ModesStore

    @State private var draft: [EditableMode] = []
    @State private var saveError: String?
    @State private var selectedID: String?
    @State private var draggedID: String?

    var body: some View {
        Form {
            if let loadError = store.loadError {
                Section {
                    Label {
                        Text("config.json has a problem, so the last working modes are in use:\n\(loadError.description)")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    }
                }
            }

            if !draft.isEmpty {
                Section {
                    ForEach(draft) { mode in
                        ModeRow(
                            mode: mode,
                            isSelected: mode.id == selectedID,
                            isInIsland: (draft.firstIndex { $0.id == mode.id } ?? 0) < ModesBar.maximumVisible,
                            onDragStart: { draggedID = mode.id }
                        )
                        .onTapGesture { selectedID = mode.id }
                        .onDrop(of: [.text], delegate: ModeDropDelegate(targetID: mode.id, draft: $draft, draggedID: $draggedID))
                        .contextMenu {
                            Button("Move Up") { withAnimation { draft.move(id: mode.id, by: -1) } }
                                .disabled(draft.first?.id == mode.id)
                            Button("Move Down") { withAnimation { draft.move(id: mode.id, by: 1) } }
                                .disabled(draft.last?.id == mode.id)
                            Divider()
                            Button("Delete Mode", role: .destructive) { delete(mode.id) }
                        }
                    }
                } footer: {
                    Text("The island shows the first five modes, left to right in this order. Drag ≡ to change it, or use Move Up and Move Down in a mode's context menu.")
                        .foregroundStyle(.secondary)
                }
            }

            if let selected = draft.first(where: { $0.id == selectedID }) {
                Section {
                    ModeEditor(mode: binding(for: selected)) { delete(selected.id) }
                } header: {
                    Label {
                        Text(selected.name.isEmpty ? String(localized: "New Mode") : selected.name)
                    } icon: {
                        Image(systemName: SymbolImage.name(selected.symbol))
                    }
                } footer: {
                    if selected.actions.contains(where: { $0.kind == .url }) {
                        Text(ModeAction.Kind.urlHint)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                HStack {
                    Button("Add Mode") {
                        let mode = EditableMode(newModeNamed: String(localized: "New Mode"), existingIDs: Set(draft.map(\.id)))
                        draft.append(mode)
                        selectedID = mode.id
                    }
                    if store.modes.isEmpty && draft.isEmpty {
                        Button("Add Example Modes") {
                            do throws(ModesConfigError) {
                                try store.installExampleIfMissing()
                            } catch {
                                saveError = error.description
                            }
                        }
                    }
                    Spacer()
                    Button("Revert") { loadDraft() }
                        .disabled(!hasChanges)
                    Button("Save") { save() }
                        .keyboardShortcut("s")
                        .disabled(!hasChanges)
                }
                if let saveError {
                    Text(saveError).foregroundStyle(.red)
                }
            } footer: {
                HStack {
                    Text("Stored in config.json. Edits made in a text editor show up here automatically.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .settingsPage()
        .onAppear(perform: loadDraft)
        .onChange(of: store.modes) { loadDraft() }
    }

    /// Compared as modes: editable actions get fresh ids every time they are loaded.
    private var hasChanges: Bool { draft.map(\.mode) != store.modes }

    private func loadDraft() {
        draft = store.modes.map(EditableMode.init)
        if !draft.contains(where: { $0.id == selectedID }) { selectedID = draft.first?.id }
        saveError = nil
    }

    /// Looks the mode up by id on every access, so moving or deleting modes never leaves the
    /// editor pointing at the wrong one.
    private func binding(for mode: EditableMode) -> Binding<EditableMode> {
        Binding {
            draft.first { $0.id == mode.id } ?? mode
        } set: { newValue in
            guard let index = draft.firstIndex(where: { $0.id == mode.id }) else { return }
            draft[index] = newValue
        }
    }

    private func delete(_ id: String) {
        let index = draft.firstIndex { $0.id == id }
        draft.removeAll { $0.id == id }
        if selectedID == id, let index {
            selectedID = draft.isEmpty ? nil : draft[min(index, draft.count - 1)].id
        }
    }

    private func save() {
        do throws(ModesConfigError) {
            try store.save(ModesConfig(modes: draft.map(\.mode)))
            saveError = nil
        } catch {
            saveError = error.description
        }
    }
}

/// A mode in the list: symbol, name and the ≡ handle that drags it to a new place.
private struct ModeRow: View {
    let mode: EditableMode
    let isSelected: Bool
    /// Only the first few modes fit in the island.
    let isInIsland: Bool
    var onDragStart: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: SymbolImage.name(mode.symbol))
                .frame(width: 20)
            Text(mode.name.isEmpty ? String(localized: "New Mode") : mode.name)
                .lineLimit(1)
            if !isInIsland {
                Text("Not in the island")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 20)
                .contentShape(.rect)
                .onDrag {
                    onDragStart()
                    return NSItemProvider(object: mode.id as NSString)
                }
                .help("Drag to change the order")
                .accessibilityLabel(Text("Drag to change the order"))
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
    }
}

/// Moves the dragged mode to where the pointer is, live, like system lists.
private struct ModeDropDelegate: DropDelegate {
    let targetID: String
    @Binding var draft: [EditableMode]
    @Binding var draggedID: String?

    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != targetID else { return }
        withAnimation(.smooth(duration: 0.2)) { draft.move(id: draggedID, to: targetID) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }
}

/// One mode: its name, its symbol and its actions, one tidy row each.
private struct ModeEditor: View {
    @Binding var mode: EditableMode
    var onDelete: () -> Void

    var body: some View {
        TextField("Name", text: $mode.name, prompt: Text("Mode name"))
        LabeledContent("Icon") {
            SymbolPicker(symbol: $mode.symbol)
        }

        ForEach($mode.actions) { $action in
            let id = action.id
            let number = (mode.actions.firstIndex { $0.id == id } ?? 0) + 1
            ActionEditor(
                action: $action,
                title: mode.actions.count > 1 ? String(localized: "Action \(number)") : String(localized: "Action"),
                onRemove: mode.actions.count > 1 ? { mode.actions.removeAll { $0.id == id } } : nil
            )
        }

        HStack {
            Button(mode.actions.isEmpty ? String(localized: "Add Action") : String(localized: "Add Another Action")) {
                mode.actions.append(EditableAction())
            }
            Spacer()
            Button("Delete Mode", role: .destructive, action: onDelete)
        }
        .buttonStyle(.borderless)
    }
}

/// What an action does (a row with the type) and what it opens (a row with the target).
private struct ActionEditor: View {
    @Binding var action: EditableAction
    var title: String
    /// Only chains can drop an action; a single action is the mode itself.
    var onRemove: (() -> Void)?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Picker(title, selection: $action.kind) {
                    ForEach(ModeAction.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                if let onRemove {
                    Button(action: onRemove) {
                        Label("Remove Action", systemImage: "minus.circle")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Remove Action")
                }
            }
        }

        switch action.kind {
        case .url:
            TextField("Link", text: $action.value, prompt: Text(action.kind.placeholder))
        case .app:
            LabeledContent("App") {
                ChosenItem(item: ChosenItem.Item(application: action.value)) {
                    if let url = FileChooser.chooseApplication(),
                       let bundleID = Bundle(url: url)?.bundleIdentifier {
                        action.value = bundleID
                    }
                }
            }
        case .file:
            LabeledContent("File or Folder") {
                ChosenItem(item: ChosenItem.Item(path: action.value)) {
                    if let url = FileChooser.chooseFileOrFolder() {
                        action.value = ModeActionResolver.configPath(for: url)
                    }
                }
            }
        case .capture:
            Text("Opens the capture field, the same as its keyboard shortcut. Where it saves is set in Settings → Capture.")
                .foregroundStyle(.secondary)
        case .shortcut:
            ShortcutPicker(name: $action.value, library: .shared)
            TextField("Input", text: $action.input, prompt: Text("Optional"))
        }
    }
}

/// The chosen app or file, shown by its icon and name, with a button to choose another.
private struct ChosenItem: View {
    struct Item {
        var icon: NSImage?
        var name: String?
        /// The full path or bundle id, for the tooltip.
        var detail: String?
        var isMissing = false

        init(application bundleID: String) {
            guard !bundleID.isEmpty else { return }
            detail = bundleID
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
                name = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
            } else {
                name = bundleID
                isMissing = true
            }
        }

        init(path: String) {
            guard let url = ModeActionResolver.fileURL(from: path, homeDirectory: URL(filePath: NSHomeDirectory())) else { return }
            let fullPath = url.path(percentEncoded: false)
            detail = path
            name = FileManager.default.displayName(atPath: fullPath)
            if FileManager.default.fileExists(atPath: fullPath) {
                icon = NSWorkspace.shared.icon(forFile: fullPath)
            } else {
                isMissing = true
            }
        }
    }

    let item: Item
    var choose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let name = item.name {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(item.isMissing ? .secondary : .primary)
                    .help(item.isMissing ? String(localized: "Not found: \(item.detail ?? name)") : item.detail ?? name)
            }
            Button("Choose…", action: choose)
        }
    }
}

/// The user's shortcuts in a pop-up menu. If they can't be listed, the name is typed instead.
private struct ShortcutPicker: View {
    @Binding var name: String
    let library: ShortcutsLibrary

    var body: some View {
        Group {
            switch library.state {
            case .notLoaded, .loading:
                LabeledContent("Shortcut") {
                    ProgressView().controlSize(.small)
                }
            case .loaded(let names):
                Picker("Shortcut", selection: $name) {
                    if name.isEmpty {
                        Text("Choose a Shortcut").tag("")
                    } else if !names.contains(name) {
                        // Renamed or deleted in Shortcuts; keep it visible rather than drop it.
                        Text(verbatim: name).tag(name)
                    }
                    ForEach(names, id: \.self) { Text(verbatim: $0).tag($0) }
                }
            case .unavailable:
                TextField("Shortcut", text: $name, prompt: Text(ModeAction.Kind.shortcut.placeholder))
            }
        }
        .onAppear { library.loadIfNeeded() }
    }
}

/// The mode's symbol; a click opens a searchable grid.
private struct SymbolPicker: View {
    @Binding var symbol: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: SymbolImage.name(symbol))
                .font(.system(size: 15))
                .frame(width: 22, height: 18)
        }
        .help("Choose a symbol")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            SymbolGrid(selection: $symbol) { isPresented = false }
        }
    }
}

private struct SymbolGrid: View {
    @Binding var selection: String
    var dismiss: () -> Void
    @State private var query = ""

    private static let columns = Array(repeating: GridItem(.fixed(32), spacing: 6), count: 8)

    var body: some View {
        let results = SymbolCatalog.search(query, isValid: SymbolImage.exists)
        VStack(spacing: 10) {
            TextField("Search", text: $query, prompt: Text("Search symbols"))
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 6) {
                    ForEach(results, id: \.self) { name in
                        Button {
                            selection = name
                            dismiss()
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 15))
                                .frame(width: 32, height: 32)
                                .background(
                                    selection == name ? Color.accentColor.opacity(0.3) : .clear,
                                    in: .rect(cornerRadius: 6)
                                )
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .help(Text(verbatim: name))
                    }
                }
            }
            .frame(height: 230)
            .overlay {
                if results.isEmpty {
                    Text("No symbols match")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(width: 8 * 32 + 7 * 6 + 24)
    }
}

enum SymbolImage {
    static func exists(_ name: String) -> Bool {
        !name.isEmpty && NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    /// The symbol, or a placeholder for a name that isn't one.
    static func name(_ name: String) -> String {
        exists(name) ? name : "questionmark.square.dashed"
    }
}

/// Open panels for choosing what an action opens.
enum FileChooser {
    static func chooseApplication() -> URL? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseFileOrFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        return panel.runModal() == .OK ? panel.url : nil
    }
}
