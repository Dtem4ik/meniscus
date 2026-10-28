import AppIntents
import OSLog

/// The Focus the filter is added to. macOS doesn't tell apps which Focus turned on, so the user
/// picks it once when adding the filter in System Settings → Focus.
nonisolated enum FocusKind: String, AppEnum, CaseIterable, Sendable {
    case doNotDisturb, personal, work, sleep, driving, fitness, mindfulness, reading, gaming, other

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Focus" }

    static var caseDisplayRepresentations: [FocusKind: DisplayRepresentation] {
        [
            .doNotDisturb: DisplayRepresentation(title: "Do Not Disturb", image: .init(systemName: "moon.fill")),
            .personal: DisplayRepresentation(title: "Personal", image: .init(systemName: "person.fill")),
            .work: DisplayRepresentation(title: "Work", image: .init(systemName: "briefcase.fill")),
            .sleep: DisplayRepresentation(title: "Sleep", image: .init(systemName: "bed.double.fill")),
            .driving: DisplayRepresentation(title: "Driving", image: .init(systemName: "car.fill")),
            .fitness: DisplayRepresentation(title: "Fitness", image: .init(systemName: "figure.run")),
            .mindfulness: DisplayRepresentation(title: "Mindfulness", image: .init(systemName: "apple.meditate")),
            .reading: DisplayRepresentation(title: "Reading", image: .init(systemName: "book.fill")),
            .gaming: DisplayRepresentation(title: "Gaming", image: .init(systemName: "gamecontroller.fill")),
            .other: DisplayRepresentation(title: "Other Focus", image: .init(systemName: "circle.fill")),
        ]
    }

    var symbol: String {
        switch self {
        case .doNotDisturb: "moon.fill"
        case .personal: "person.fill"
        case .work: "briefcase.fill"
        case .sleep: "bed.double.fill"
        case .driving: "car.fill"
        case .fitness: "figure.run"
        case .mindfulness: "apple.meditate"
        case .reading: "book.fill"
        case .gaming: "gamecontroller.fill"
        case .other: "circle.fill"
        }
    }

    var title: String {
        switch self {
        case .doNotDisturb: String(localized: "Do Not Disturb")
        case .personal: String(localized: "Personal")
        case .work: String(localized: "Work")
        case .sleep: String(localized: "Sleep")
        case .driving: String(localized: "Driving")
        case .fitness: String(localized: "Fitness")
        case .mindfulness: String(localized: "Mindfulness")
        case .reading: String(localized: "Reading")
        case .gaming: String(localized: "Gaming")
        case .other: String(localized: "Focus")
        }
    }
}

/// A Focus filter (public App Intents, no entitlement). macOS calls `perform()` when a Focus that
/// has this filter turns on, with the values chosen for it, and again when it turns off, with the
/// values unset.
struct MeniscusFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Show in the notch"
    static let description: IntentDescription? = "Meniscus briefly shows this Focus in the notch when it turns on and off."

    @Parameter(title: "Focus")
    var kind: FocusKind?

    @Parameter(title: "Name", description: "Shown instead of the Focus name, if set.")
    var name: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name ?? kind?.title ?? String(localized: "Focus"))")
    }

    func perform() async throws -> some IntentResult {
        Logger.focus.notice("Focus filter performed: \(kind?.rawValue ?? "off", privacy: .public)")
        await ActivityServices.shared.focusFilterPerformed(kind: kind, name: name)
        return .result()
    }
}

extension Logger {
    /// Focus filter calls. In Console, filter by subsystem `io.github.dtem4ik.meniscus` and
    /// category `focus`.
    nonisolated static let focus = Logger(subsystem: "io.github.dtem4ik.meniscus", category: "focus")
}
