import AppKit
import Darwin

/// Who a request came from, as verified by Meniscus; never as claimed by the caller.
nonisolated struct APISource: Hashable, Sendable {
    /// Stable key: `app:<bundle id>`, `unknown`, `link`, `shortcuts` or `developer`.
    var key: String
    var name: String
    var bundleID: String?
    /// The verified app, for its icon and for bringing it forward on a click.
    var appURL: URL?
    var channel: APIChannel

    static let link = APISource(key: "link", name: String(localized: "Links"), channel: .link)
    static let unknown = APISource(key: "unknown", name: String(localized: "Unknown"), channel: .cli)
    static let developer = APISource(key: "developer", name: String(localized: "Developer"), channel: .developer)

    static var shortcuts: APISource {
        let id = "com.apple.shortcuts"
        return APISource(key: "shortcuts", name: String(localized: "Shortcuts"), bundleID: id,
                         appURL: NSWorkspace.shared.urlForApplication(withBundleIdentifier: id), channel: .shortcuts)
    }

    static func app(bundleID: String, name: String, url: URL) -> APISource {
        APISource(key: "app:" + bundleID, name: name, bundleID: bundleID, appURL: url, channel: .cli)
    }
}

/// Finds the app a command runs in: walks up from the process that connected (`LOCAL_PEERPID`)
/// through its parents (`sysctl`), to the first process inside a regular app bundle, like
/// Terminal or Visual Studio Code. A chain that reaches `launchd` first (tmux, ssh, launch
/// agents) has no reliable app. Public APIs only.
nonisolated enum SourceResolver {
    static let maximumDepth = 32

    static func source(forPeer pid: pid_t) -> APISource {
        // The peer is the CLI itself, inside Meniscus: start with its parent.
        var current = parent(of: pid)
        var depth = 0
        while let pid = current, pid > 1, depth < maximumDepth {
            if let path = executablePath(of: pid), let app = enclosingApp(ofExecutable: path) {
                return app
            }
            current = parent(of: pid)
            depth += 1
        }
        return .unknown
    }

    /// The innermost regular app bundle around an executable: helper apps (agents, background
    /// only) are skipped, so a shell started by an editor's helper process finds the editor.
    static func enclosingApp(ofExecutable path: String) -> APISource? {
        var url = URL(filePath: path).deletingLastPathComponent()
        while url.path() != "/" {
            if url.pathExtension == "app", let app = regularApp(at: url) { return app }
            url = url.deletingLastPathComponent()
        }
        return nil
    }

    static func regularApp(at url: URL) -> APISource? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
              id != Bundle.main.bundleIdentifier else { return nil }
        let info = bundle.infoDictionary ?? [:]
        guard (info["CFBundlePackageType"] as? String ?? "APPL") == "APPL",
              !(info["LSUIElement"] as? Bool ?? false), !(info["LSBackgroundOnly"] as? Bool ?? false) else { return nil }
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        return .app(bundleID: id, name: name, url: url)
    }

    static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 0 ? parent : nil
    }

    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
