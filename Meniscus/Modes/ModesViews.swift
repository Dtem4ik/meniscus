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

            ForEach($draft) { $mode in
                Section {
                    ModeEditor(mode: $mode) {
                        draft.removeAll { $0.id == mode.id }
                    }
                } header: {
                    Label {
                        Text(mode.name.isEmpty ? String(localized: "New Mode") : mode.name)
                    } icon: {
                        Image(systemName: SymbolImage.name(mode.symbol))
                    }
                } footer: {
                    if mode.actions.contains(where: { $0.kind == .url }) {
                        Text(ModeAction.Kind.urlHint)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                HStack {
                    Button("Add Mode") {
                        draft.append(EditableMode(newModeNamed: String(localized: "New Mode"), existingIDs: Set(draft.map(\.id))))
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
        .formStyle(.grouped)
        .frame(width: 560, height: 520)
        .onAppear(perform: loadDraft)
        .onChange(of: store.modes) { loadDraft() }
    }

    /// Compared as modes: editable actions get fresh ids every time they are loaded.
    private var hasChanges: Bool { draft.map(\.mode) != store.modes }

    private func loadDraft() {
        draft = store.modes.map(EditableMode.init)
        saveError = nil
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
