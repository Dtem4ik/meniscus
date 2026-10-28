import AppKit

/// Puts the bundled `meniscus` tool where a shell finds it, without administrator rights: a link
/// in `~/.local/bin`. Never replaces a file that isn't its own link.
enum CLIInstaller {
    enum Outcome: Equatable {
        case installed
        case occupied
        case failed(String)
    }

    static var bundledTool: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Helpers/meniscus")
    }

    static var link: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin/meniscus")
    }

    /// The line to add to `~/.zshrc` when `~/.local/bin` isn't on `PATH` yet.
    static let pathLine = #"export PATH="$HOME/.local/bin:$PATH""#

    static var isInstalled: Bool {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false)) else { return false }
        return URL(filePath: target).standardizedFileURL == bundledTool.standardizedFileURL
    }

    static func install() -> Outcome {
        let manager = FileManager.default
        let path = link.path(percentEncoded: false)
        do {
            try manager.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? manager.destinationOfSymbolicLink(atPath: path)) != nil {
                // Our own link from an earlier copy of Meniscus: point it here.
                try manager.removeItem(atPath: path)
            } else if manager.fileExists(atPath: path) {
                return .occupied
            }
            try manager.createSymbolicLink(at: link, withDestinationURL: bundledTool)
            return .installed
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Claude Code hooks for `~/.claude/settings.json` (docs/external-api.md, section 8). The full
    /// path, because hooks don't always get the shell's `PATH`.
    static var claudeCodeHooks: String {
        let command = #""command": "$HOME/.local/bin/meniscus hook claude-code", "async": true"#
        let hook = #"[{ "hooks": [{ "type": "command", \#(command) }] }]"#
        return """
        {
          "hooks": {
            "UserPromptSubmit": \(hook),
            "Stop": \(hook),
            "StopFailure": \(hook),
            "SessionEnd": \(hook),
            "Notification": [{
              "matcher": "permission_prompt|elicitation_dialog|agent_needs_input|agent_completed",
              "hooks": [{ "type": "command", \(command) }]
            }]
          }
        }
        """
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
