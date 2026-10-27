import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The text field shown in the island during quick capture.
struct CaptureField: View {
    @Bindable var capture: CaptureController
    var onFinish: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.title2)
                .foregroundStyle(.secondary)

            if capture.settings.isConfigured {
                TextField("Capture a thought…", text: $capture.draft)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFocused)
                    .onSubmit {
                        Task {
                            if await capture.submit() { onFinish() }
                        }
                    }
                status
            } else {
                Text("Choose your Obsidian vault first.")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Open Settings…") {
                    onFinish()
                    SettingsWindowController.shared.show()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 28)
        .frame(maxHeight: .infinity)
        .onAppear { isFocused = true }
        .onExitCommand(perform: onFinish)
    }

    @ViewBuilder
    private var status: some View {
        switch capture.status {
        case .idle:
            EmptyView()
        case .saving:
            ProgressView().controlSize(.small)
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .help(message)
        }
    }
}

/// Settings → Capture.
struct CaptureSettingsView: View {
    @Bindable var settings: CaptureSettings
    @State private var inboxError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Vault") {
                    HStack {
                        Text(settings.vaultPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? String(localized: "Not chosen"))
                            .foregroundStyle(settings.vaultPath == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { settings.chooseVault() }
                    }
                }
                LabeledContent("Inbox note") {
                    HStack {
                        TextField("Inbox note", text: $settings.inboxPath)
                            .labelsHidden()
                        Button("Choose…") { inboxError = settings.chooseInbox() }
                            .disabled(settings.vaultPath == nil)
                    }
                }
                if let inboxError {
                    Text(inboxError).foregroundStyle(.red)
                }
                Toggle("Add a date heading for each new day", isOn: $settings.addsDateHeadings)
            } footer: {
                Text("Each thought is added to the end of the note as “- 14:32 your text”. The note is created if it doesn't exist. No Obsidian plugin is needed.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Shortcut") {
                    HotKeyRecorder(hotKey: $settings.hotKey)
                }
            } footer: {
                Text("Opens the capture field from any app. Works without Accessibility access.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Click, then press the new shortcut. Escape cancels.
struct HotKeyRecorder: View {
    @Binding var hotKey: HotKey?
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Button(isRecording ? String(localized: "Type a shortcut…") : (hotKey?.displayString ?? String(localized: "None"))) {
                isRecording ? stopRecording() : startRecording()
            }
            if hotKey != nil && !isRecording {
                Button("Clear") { hotKey = nil }
                    .buttonStyle(.borderless)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stopRecording()
                return nil
            }
            let candidate = HotKey(keyCode: UInt32(event.keyCode), modifiers: HotKey.Modifiers(event.modifierFlags))
            if candidate.isValid {
                hotKey = candidate
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

extension HotKey.Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.shift) { insert(.shift) }
    }
}
