import Foundation

/// The user's modes, stored as JSON in `~/Library/Application Support/Meniscus/config.json`.
/// See `config.example.json` in the repository for the format.
nonisolated struct ModesConfig: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int = ModesConfig.currentVersion
    var modes: [Mode] = []

    init(version: Int = ModesConfig.currentVersion, modes: [Mode] = []) {
        self.version = version
        self.modes = modes
    }

    private enum CodingKeys: String, CodingKey { case version, modes }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? ModesConfig.currentVersion
        modes = try container.decodeIfPresent([Mode].self, forKey: .modes) ?? []
    }
}

/// A named set of actions started with one button in the notch.
nonisolated struct Mode: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    /// SF Symbol name shown on the button.
    var symbol: String
    var actions: [ModeAction]

    static let defaultSymbol = "square.grid.2x2"

    init(id: String = UUID().uuidString, name: String, symbol: String = Mode.defaultSymbol, actions: [ModeAction] = []) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.actions = actions
    }

    private enum CodingKeys: String, CodingKey { case id, name, symbol, actions }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        // A missing id is generated from the name so hand-written configs stay short.
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? Mode.slug(from: name)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? Mode.defaultSymbol
        actions = try container.decodeIfPresent([ModeAction].self, forKey: .actions) ?? []
    }

    static func slug(from name: String) -> String {
        let slug = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return slug.isEmpty ? "mode" : slug
    }
}

/// One step of a mode. Encoded with a `type` field:
///
/// ```json
/// { "type": "url", "url": "https://example.com" }
/// { "type": "app", "bundleId": "com.apple.Notes" }
/// { "type": "file", "path": "~/Documents/Plan.md" }
/// { "type": "shortcut", "name": "Start Focus", "input": "optional text" }
/// ```
nonisolated enum ModeAction: Codable, Equatable, Sendable {
    /// Any URL, including deep links such as `obsidian://…` or `shortcuts://…`.
    case openURL(String)
    case openApp(bundleID: String)
    /// A file or folder; `~` is expanded.
    case openFile(path: String)
    case runShortcut(name: String, input: String?)

    nonisolated enum Kind: String, Codable, CaseIterable, Sendable {
        case url, app, file, shortcut
    }

    var kind: Kind {
        switch self {
        case .openURL: .url
        case .openApp: .app
        case .openFile: .file
        case .runShortcut: .shortcut
        }
    }

    private enum CodingKeys: String, CodingKey { case type, url, bundleId, path, name, input }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch Kind(rawValue: type) {
        case .url: self = .openURL(try container.decode(String.self, forKey: .url))
        case .app: self = .openApp(bundleID: try container.decode(String.self, forKey: .bundleId))
        case .file: self = .openFile(path: try container.decode(String.self, forKey: .path))
        case .shortcut:
            self = .runShortcut(
                name: try container.decode(String.self, forKey: .name),
                input: try container.decodeIfPresent(String.self, forKey: .input)
            )
        case nil:
            let allowed = Kind.allCases.map(\.rawValue).joined(separator: ", ")
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown action type \"\(type)\". Use one of: \(allowed)."
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind.rawValue, forKey: .type)
        switch self {
        case .openURL(let url): try container.encode(url, forKey: .url)
        case .openApp(let bundleID): try container.encode(bundleID, forKey: .bundleId)
        case .openFile(let path): try container.encode(path, forKey: .path)
        case .runShortcut(let name, let input):
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(input, forKey: .input)
        }
    }
}

// MARK: - Reading and writing

nonisolated enum ModesConfigCoder {
    static func decode(_ data: Data) throws(ModesConfigError) -> ModesConfig {
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return ModesConfig() }
        let config: ModesConfig
        do {
            config = try JSONDecoder().decode(ModesConfig.self, from: data)
        } catch let error as DecodingError {
            throw .invalidJSON(Self.describe(error))
        } catch {
            throw .invalidJSON(error.localizedDescription)
        }
        guard config.version <= ModesConfig.currentVersion else {
            throw .unsupportedVersion(config.version)
        }
        let issues = ModesConfigValidator.issues(in: config)
        guard issues.isEmpty else { throw .invalidContent(issues) }
        return config
    }

    static func encode(_ config: ModesConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(config)
        data.append(0x0A)
        return data
    }

    /// Turns a decoding error into something a person editing JSON by hand can act on.
    static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let components = context.codingPath.map { key in
                key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)"
            }
            let joined = components.joined()
            return joined.isEmpty ? "the root" : String(joined.drop(while: { $0 == "." }))
        }
        switch error {
        case .keyNotFound(let key, let context):
            let location = context.codingPath.isEmpty ? "" : " in \(path(context))"
            return "Missing \"\(key.stringValue)\"\(location)."
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "Wrong value at \(path(context)): \(context.debugDescription)"
        case .dataCorrupted(let context):
            if let underlying = context.underlyingError as NSError?,
               let detail = underlying.userInfo[NSDebugDescriptionErrorKey] as? String {
                return "Not valid JSON: \(detail)"
            }
            return context.codingPath.isEmpty
                ? "Not valid JSON: \(context.debugDescription)"
                : "\(path(context)): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}

nonisolated enum ModesConfigError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidJSON(String)
    case unsupportedVersion(Int)
    case invalidContent([String])
    case io(String)

    var description: String {
        switch self {
        case .invalidJSON(let message): message
        case .unsupportedVersion(let version):
            "This config is version \(version); this Meniscus understands up to \(ModesConfig.currentVersion). Update Meniscus."
        case .invalidContent(let issues): issues.joined(separator: "\n")
        case .io(let message): message
        }
    }
}

nonisolated enum ModesConfigValidator {
    static func issues(in config: ModesConfig) -> [String] {
        var issues: [String] = []
        var seen = Set<String>()
        for (index, mode) in config.modes.enumerated() {
            let label = mode.name.isEmpty ? "Mode \(index + 1)" : "Mode \"\(mode.name)\""
            if mode.name.trimmingCharacters(in: .whitespaces).isEmpty { issues.append("\(label) has no name.") }
            if !seen.insert(mode.id).inserted { issues.append("\(label) reuses the id \"\(mode.id)\".") }
            for (actionIndex, action) in mode.actions.enumerated() {
                if let problem = ModeActionResolver.problem(with: action) {
                    issues.append("\(label), action \(actionIndex + 1): \(problem)")
                }
            }
        }
        return issues
    }
}
