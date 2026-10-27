import Foundation
import Testing
@testable import Meniscus

struct ModesConfigTests {
    private func decode(_ json: String) throws(ModesConfigError) -> ModesConfig {
        try ModesConfigCoder.decode(Data(json.utf8))
    }

    @Test func decodesAllActionTypes() throws {
        let config = try decode("""
        { "version": 1, "modes": [ { "id": "w", "name": "Work", "symbol": "briefcase", "actions": [
            { "type": "url", "url": "https://example.com" },
            { "type": "app", "bundleId": "com.apple.Notes" },
            { "type": "file", "path": "~/Documents" },
            { "type": "shortcut", "name": "Focus", "input": "deep" }
        ] } ] }
        """)
        #expect(config.modes.first?.actions == [
            .openURL("https://example.com"),
            .openApp(bundleID: "com.apple.Notes"),
            .openFile(path: "~/Documents"),
            .runShortcut(name: "Focus", input: "deep"),
        ])
    }

    @Test func fillsInMissingIdSymbolAndActions() throws {
        let config = try decode(#"{ "modes": [ { "name": "Deep Work!" } ] }"#)
        let mode = try #require(config.modes.first)
        #expect(mode.id == "deep-work")
        #expect(mode.symbol == Mode.defaultSymbol)
        #expect(mode.actions.isEmpty)
        #expect(config.version == ModesConfig.currentVersion)
    }

    @Test func emptyFileMeansNoModes() throws {
        #expect(try decode("  \n") == ModesConfig())
    }

    private func decodingMessage(_ json: String) -> String? {
        do throws(ModesConfigError) {
            _ = try decode(json)
            return nil
        } catch {
            guard case .invalidJSON(let message) = error else { return nil }
            return message
        }
    }

    @Test func unknownActionTypeExplainsTheChoices() throws {
        let message = try #require(decodingMessage(#"{ "modes": [ { "name": "A", "actions": [ { "type": "launch" } ] } ] }"#))
        #expect(message.contains("launch"))
        #expect(message.contains("url, app, file, shortcut"))
    }

    @Test func missingFieldNamesTheField() throws {
        let message = try #require(decodingMessage(#"{ "modes": [ { "name": "A", "actions": [ { "type": "url" } ] } ] }"#))
        #expect(message.contains("“url”"))
    }

    @Test func brokenJSONIsReported() {
        #expect(throws: ModesConfigError.self) { try decode("{ \"modes\": [ ") }
    }

    @Test func newerVersionIsRejected() {
        #expect(throws: ModesConfigError.unsupportedVersion(99)) { try decode(#"{ "version": 99 }"#) }
    }

    @Test func validationFindsDuplicatesAndBadURLs() {
        let config = ModesConfig(modes: [
            Mode(id: "a", name: "One", actions: [.openURL("not a url")]),
            Mode(id: "a", name: "", actions: [.runShortcut(name: " ", input: nil)]),
        ])
        let issues = ModesConfigValidator.issues(in: config)
        #expect(issues.count == 4)
    }

    @Test func encodingRoundTrips() throws {
        let config = ModesConfig(modes: [
            Mode(id: "w", name: "Work", symbol: "briefcase", actions: [
                .openURL("obsidian://open?vault=Notes"),
                .runShortcut(name: "Focus", input: nil),
            ]),
        ])
        let data = try ModesConfigCoder.encode(config)
        #expect(try ModesConfigCoder.decode(data) == config)
        // Slashes stay readable for people editing the file by hand.
        #expect(String(decoding: data, as: UTF8.self).contains("obsidian://open"))
    }

    @Test func bundledExampleIsValid() throws {
        let url = try #require(Bundle.main.url(forResource: "config.example", withExtension: "json"))
        let config = try ModesConfigCoder.decode(Data(contentsOf: url))
        // A few simple modes, one action each: the common case, nothing that opens a pile of things.
        #expect((2...3).contains(config.modes.count))
        #expect(config.modes.allSatisfy { $0.actions.count == 1 })
    }
}

struct ModeActionResolverTests {
    private let home = URL(filePath: "/tmp/home", directoryHint: .isDirectory)

    private func resolvedPath(_ path: String) -> String? {
        guard case .file(let url) = ModeActionResolver.resolve(.openFile(path: path), homeDirectory: home) else { return nil }
        return url.path(percentEncoded: false)
    }

    @Test func expandsTilde() {
        #expect(resolvedPath("~/Documents/Plan.md") == "/tmp/home/Documents/Plan.md")
        #expect(resolvedPath("~")?.hasPrefix("/tmp/home") == true)
        #expect(resolvedPath("/tmp/a b") == "/tmp/a b")
    }

    @Test func rejectsRelativePaths() {
        #expect(ModeActionResolver.resolve(.openFile(path: "Documents"), homeDirectory: home) == nil)
    }

    @Test func urlsNeedAScheme() {
        #expect(ModeActionResolver.url(from: "example.com") == nil)
        #expect(ModeActionResolver.url(from: " https://claude.ai/new ")?.absoluteString == "https://claude.ai/new")
        #expect(ModeActionResolver.url(from: "obsidian://open?vault=Notes")?.scheme == "obsidian")
    }

    @Test func shortcutURLEncodesNameAndInput() throws {
        let url = try #require(ModeActionResolver.shortcutURL(name: "Log & Plan +1", input: "a b"))
        #expect(url.absoluteString == "shortcuts://run-shortcut?name=Log%20%26%20Plan%20%2B1&input=text&text=a%20b")
    }

    @Test func shortcutWithoutInput() throws {
        let url = try #require(ModeActionResolver.shortcutURL(name: "Focus", input: nil))
        #expect(url.absoluteString == "shortcuts://run-shortcut?name=Focus")
    }

    @Test func editableActionRoundTrips() {
        let actions: [ModeAction] = [
            .openURL("https://example.com"), .openApp(bundleID: "com.apple.Notes"),
            .openFile(path: "~/x"), .runShortcut(name: "S", input: "i"), .runShortcut(name: "S", input: nil),
        ]
        #expect(actions.map { EditableAction($0).action } == actions)
    }

    @Test func newModeIdsAreUnique() {
        let mode = EditableMode(newModeNamed: "New Mode", existingIDs: ["new-mode", "new-mode-2"])
        #expect(mode.id == "new-mode-3")
    }

    @Test func newModeStartsWithOneActionToFillIn() {
        let mode = EditableMode(newModeNamed: "New Mode", existingIDs: [])
        #expect(mode.actions.count == 1)
    }
}

@MainActor
struct ModesStoreTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "meniscus-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "config.json")
    }

    @Test func missingFileMeansNoModesAndNoError() {
        let store = ModesStore(fileURL: temporaryFile())
        store.reload()
        #expect(store.modes.isEmpty)
        #expect(store.loadError == nil)
    }

    @Test func savesAndReloads() throws {
        let url = temporaryFile()
        let store = ModesStore(fileURL: url)
        let config = ModesConfig(modes: [Mode(id: "w", name: "Work", actions: [.openURL("https://example.com")])])
        try store.save(config)

        let other = ModesStore(fileURL: url)
        other.reload()
        #expect(other.config == config)
    }

    @Test func brokenFileKeepsLastGoodModes() throws {
        let url = temporaryFile()
        let store = ModesStore(fileURL: url)
        try store.save(ModesConfig(modes: [Mode(id: "w", name: "Work")]))

        try Data("{ broken".utf8).write(to: url)
        store.reload()
        #expect(store.modes.map(\.id) == ["w"])
        #expect(store.loadError != nil)
    }

    @Test func refusesToSaveInvalidConfig() {
        let store = ModesStore(fileURL: temporaryFile())
        #expect(throws: ModesConfigError.self) {
            try store.save(ModesConfig(modes: [Mode(id: "a", name: "")]))
        }
    }
}

struct QuickCaptureActionTests {
    @Test func captureActionRoundTrips() throws {
        let config = try ModesConfigCoder.decode(Data(#"{ "modes": [ { "name": "Note", "actions": [ { "type": "capture" } ] } ] }"#.utf8))
        #expect(config.modes.first?.actions == [.quickCapture])
        let encoded = String(decoding: try ModesConfigCoder.encode(config), as: UTF8.self)
        #expect(encoded.contains(#""type" : "capture""#))
        #expect(ModeActionResolver.resolve(.quickCapture) == .quickCapture)
        #expect(ModeActionResolver.problem(with: .quickCapture) == nil)
        #expect(EditableAction(.quickCapture).action == .quickCapture)
    }
}

struct ModesSettingsHelperTests {
    @Test func shortcutsListIsParsedSortedAndDeduplicated() {
        let output = "Start Focus\n\nbeta\nAlpha  \nStart Focus\r\n"
        #expect(ShortcutsLibrary.parse(output) == ["Alpha", "beta", "Start Focus"])
    }

    @Test func chosenPathsInHomeUseTilde() {
        let home = URL(filePath: "/tmp/home", directoryHint: .isDirectory)
        #expect(ModeActionResolver.configPath(for: URL(filePath: "/tmp/home/Documents/Plan.md"), homeDirectory: home) == "~/Documents/Plan.md")
        #expect(ModeActionResolver.configPath(for: URL(filePath: "/tmp/home/Downloads/", directoryHint: .isDirectory), homeDirectory: home) == "~/Downloads")
        #expect(ModeActionResolver.configPath(for: home, homeDirectory: home) == "~")
        #expect(ModeActionResolver.configPath(for: URL(filePath: "/Applications"), homeDirectory: home) == "/Applications")
        #expect(ModeActionResolver.configPath(for: URL(filePath: "/tmp/homework"), homeDirectory: home) == "/tmp/homework")
    }

    @Test func symbolSearchMatchesEveryWord() {
        let results = SymbolCatalog.search("arrow down", isValid: { _ in false })
        #expect(results.contains("arrow.down.circle"))
        #expect(!results.contains("arrow.up.circle"))
        #expect(SymbolCatalog.search("", isValid: { _ in false }) == SymbolCatalog.symbols)
    }

    @Test func typedSymbolNameOutsideCatalogComesFirst() {
        let results = SymbolCatalog.search("swift", isValid: { $0 == "swift" })
        #expect(results.first == "swift")
    }

    @MainActor
    @Test func catalogHasOnlyRealSymbols() {
        #expect(Set(SymbolCatalog.symbols).count == SymbolCatalog.symbols.count)
        for name in SymbolCatalog.symbols {
            #expect(SymbolImage.exists(name), "\(name) is not an SF Symbol")
        }
    }
}
