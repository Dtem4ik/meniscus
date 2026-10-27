import AppKit
import SwiftUI

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

/// Settings → Modes. Functional editor; visual polish comes later.
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

private struct ModeEditor: View {
    @Binding var mode: EditableMode
    var onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: NSImage(systemSymbolName: mode.symbol, accessibilityDescription: nil) == nil
                ? "questionmark.square.dashed" : mode.symbol)
                .frame(width: 24)
            TextField("Name", text: $mode.name)
            SymbolMenu(symbol: $mode.symbol)
            Button(role: .destructive, action: onDelete) {
                Label("Delete Mode", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }

        ForEach($mode.actions) { $action in
            HStack {
                Picker("Action", selection: $action.kind) {
                    ForEach(ModeAction.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                TextField(action.kind.placeholder, text: $action.value)
                if action.kind == .shortcut {
                    TextField("Input (optional)", text: $action.input)
                }
                Button {
                    mode.actions.removeAll { $0.id == action.id }
                } label: {
                    Label("Remove Action", systemImage: "minus.circle")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }

        Button("Add Action") { mode.actions.append(EditableAction()) }
            .buttonStyle(.borderless)
    }
}

private struct SymbolMenu: View {
    @Binding var symbol: String

    private static let suggestions = [
        "briefcase", "house", "moon", "sun.max", "book", "pencil", "terminal", "chevron.left.forwardslash.chevron.right",
        "paintbrush", "music.note", "gamecontroller", "cart", "airplane", "figure.run", "brain", "sparkles",
    ]

    var body: some View {
        Menu {
            ForEach(Self.suggestions, id: \.self) { name in
                Button {
                    symbol = name
                } label: {
                    Label(name, systemImage: name)
                }
            }
        } label: {
            Text(symbol)
        }
        .fixedSize()
        .help("SF Symbol name. Pick one or type any name in config.json.")
    }
}
