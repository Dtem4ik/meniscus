import Foundation
import Testing
@testable import Meniscus

struct LocalizationTests {
    private func bundle(for language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test func russianIsBundled() throws {
        let russian = try bundle(for: "ru")
        #expect(russian.localizedString(forKey: "General", value: nil, table: nil) == "Основные")
        #expect(russian.localizedString(forKey: "Simulate Charging", value: nil, table: nil) == "Имитировать зарядку")
    }

    @Test func formatsKeepTheirPlaceholders() throws {
        let russian = try bundle(for: "ru")
        let format = russian.localizedString(forKey: "Now · until %@", value: nil, table: nil)
        #expect(String(format: format, "15:30") == "Сейчас · до 15:30")
    }
}
