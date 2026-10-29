import SwiftUI

/// Settings → Live Activities → External Notices: channels, the indicator delay, the sources seen
/// so far, and the command line tool.
struct ExternalNoticesSettingsSection: View {
    @Bindable var settings: AppSettings
    let notices: ExternalNotices
    @State private var installMessage: String?

    var body: some View {
        Section {
            Toggle("Command line tool and Shortcuts", isOn: $settings.externalCLI)
                .onChange(of: settings.externalCLI) { ActivityServices.shared.updateExternalAPI(settings: settings) }
            Toggle("Links (meniscus://)", isOn: $settings.externalLinks)
            Stepper(value: $settings.externalIndicatorDelay, in: 3...60, step: 1) {
                Text("Show running tasks after \(Int(settings.externalIndicatorDelay)) s")
            }
            HStack {
                Button("Install Command Line Tool") { install() }
                Button("Copy Path") { CLIInstaller.copy(CLIInstaller.bundledTool.path(percentEncoded: false)) }
                Button("Copy Claude Code Hooks") { CLIInstaller.copy(CLIInstaller.claudeCodeHooks) }
            }
            if let installMessage {
                Text(installMessage)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } header: {
            Text("External Notices")
        } footer: {
            Text("Other apps, scripts and Shortcuts can show short notices and running tasks here, in the island's own style. Links can come from any web page, so they only show text and are off until you turn them on. The command line tool installs as ~/.local/bin/meniscus, no administrator rights needed. In Shortcuts, use Run Shell Script with ~/.local/bin/meniscus: Meniscus's own actions need a build signed by a developer team.")
                .foregroundStyle(.secondary)
        }

        if !notices.knownSources.isEmpty {
            Section("Sources") {
                ForEach(notices.knownSources.sorted { $0.lastSeen > $1.lastSeen }) { source in
                    Toggle(isOn: Binding(
                        get: { source.isEnabled },
                        set: { notices.setEnabled($0, source: source.id) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: source.name)
                            Text("Last seen \(source.lastSeen.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button("Forget") { notices.forget(source: source.id) }
                    }
                }
            }
        }
    }

    private func install() {
        switch CLIInstaller.install() {
        case .installed:
            installMessage = String(localized: "Installed as ~/.local/bin/meniscus. If your shell can't find it, add this line to ~/.zshrc: \(CLIInstaller.pathLine)")
        case .occupied:
            installMessage = String(localized: "~/.local/bin/meniscus already exists and isn't a link to Meniscus, so it was left as it is. Use Copy Path instead.")
        case .failed(let reason):
            installMessage = String(localized: "Couldn't install: \(reason)")
        }
    }
}
