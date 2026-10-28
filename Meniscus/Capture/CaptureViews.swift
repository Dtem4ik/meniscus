import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The capture field in the island: just the text. Return saves, Escape closes; after saving a
/// short "Saved" shows and the island closes.
struct CaptureField: View {
    @Bindable var capture: CaptureController
    var onFinish: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            if capture.status == .saved {
                SavedBadge()
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            } else if capture.settings.isConfigured {
                HStack(spacing: 8) {
                    TextField(
                        "Capture",
                        text: $capture.draft,
                        prompt: Text("Capture a thought…").foregroundStyle(.white.opacity(0.4))
                    )
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .focused($isFocused)
                    .onSubmit(submit)
                    status
                }
                .transition(.opacity)
            } else {
                // Return opens Settings, so even this needs no button.
                Button("Choose where captures go in Settings → Capture") {
                    onFinish()
                    SettingsWindowController.shared.show()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(Motion.trackChange, value: capture.status)
        .onAppear { isFocused = true }
        .onExitCommand(perform: onFinish)
    }

    private func submit() {
        Task {
            guard await capture.submit() else { return }
            if AppSettings.shared.showCaptureConfirmation {
                // Close right away; the closed notch confirms, like the other live activities.
                ActivityServices.shared.showCaptureSaved()
            } else {
                try? await Task.sleep(for: Motion.captureSavedHold)
            }
            onFinish()
        }
    }

    @ViewBuilder
    private var status: some View {
        switch capture.status {
        case .idle, .saved:
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

/// "Saved" with a check that bounces once as it appears.
private struct SavedBadge: View {
    @State private var didAppear = false

    var body: some View {
        Label("Saved", systemImage: "checkmark.circle.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .symbolEffect(.bounce, value: didAppear)
            .onAppear { didAppear = true }
    }
}

/// Settings → Capture.
struct CaptureSettingsView: View {
    @Bindable var settings: CaptureSettings

    var body: some View {
        Form {
            Section {
                Picker("Save as", selection: $settings.destination) {
                    ForEach(CaptureDestination.allCases) { Text($0.title).tag($0) }
                }
                switch settings.destination {
                case .noteInFolder:
                    LabeledContent("Folder") {
                        ChosenLocation(url: settings.folderURL, choose: settings.chooseFolder)
                    }
                case .lineInNote:
                    LabeledContent("Note") {
                        ChosenLocation(url: settings.noteURL, choose: settings.chooseNote)
                    }
                    Toggle("Add a date heading for each new day", isOn: $settings.addsDateHeadings)
                }
            } footer: {
                Text(footer)
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
        .settingsPage()
    }

    private var footer: String {
        switch settings.destination {
        case .noteInFolder:
            String(localized: "Each capture becomes a note like “2026-10-27 21-45 First words.md” with your text inside. Works with any folder, such as an Obsidian inbox in iCloud Drive; no plugin is needed.")
        case .lineInNote:
            String(localized: "Each capture is added to the end of the note as “- 21:45 your text”. No plugin is needed.")
        }
    }
}

/// A chosen folder or note: its icon and name (the full path on hover) and a button to change it.
private struct ChosenLocation: View {
    let url: URL?
    var choose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let url {
                let path = url.path(percentEncoded: false)
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(FileManager.default.displayName(atPath: path))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help((path as NSString).abbreviatingWithTildeInPath)
            } else {
                Text("Not chosen")
                    .foregroundStyle(.secondary)
            }
            Button("Choose…", action: choose)
        }
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
