import Foundation
import Testing
@testable import Meniscus

@MainActor
struct FocusActivityTests {
    @Test func onThenOffShowsTheSameFocus() {
        let services = ActivityServices()
        services.focusFilterPerformed(kind: .reading, name: nil)
        #expect(services.center.current?.kind == .focus)
        #expect(services.focusEvent == FocusEvent(kind: .reading, name: nil, isOn: true))
        services.focusFilterPerformed(kind: nil, name: nil)
        #expect(services.focusEvent == FocusEvent(kind: .reading, name: nil, isOn: false))
        #expect(services.center.current?.expiresAt != nil)
        #expect(services.lastFocusFilterCall != nil)
    }

    @Test func offWithoutOnShowsNothing() {
        let services = ActivityServices()
        services.focusFilterPerformed(kind: nil, name: nil)
        #expect(services.center.current == nil)
        #expect(services.lastFocusFilterCall != nil)
    }

    @Test func aChosenNameWins() {
        let services = ActivityServices()
        services.focusFilterPerformed(kind: nil, name: "Deep")
        #expect(services.focusEvent?.title == "Deep")
        #expect(services.focusEvent?.kind == .other)
    }

    @Test func everyFocusHasASymbol() {
        for kind in FocusKind.allCases {
            #expect(!kind.symbol.isEmpty)
            #expect(!kind.title.isEmpty)
        }
    }
}
