import SwiftUI

/// The island: solid black like Dynamic Island, continuous with the hardware notch. Liquid Glass
/// is used only for the controls inside it.
struct IslandView: View {
    let context: IslandContext

    var body: some View {
        let shape = context.shape
        let layout = context.layout
        ZStack(alignment: .top) {
            shape
                .fill(.black)
                .shadow(color: .black.opacity(context.isExpanded ? 0.35 : 0), radius: 18, y: 8)

            IslandContentLayer(
                context: context,
                topInset: layout.notchHeight,
                height: layout.contentHeight,
                horizontalOffset: layout.centerOffset
            ) {
                IslandPlaceholderContent(actions: context.actions)
            }
            .mask { shape }
        }
        // Black stays black in Light Mode, so the content must use dark-appearance colors.
        .environment(\.colorScheme, .dark)
    }
}

/// The expanded content: time, date, next event and the island's controls.
struct IslandPlaceholderContent: View {
    var actions: NotchActions

    @State private var sparkleCount = 0

    var body: some View {
        HStack(spacing: 14) {
            HomeContent(
                calendar: ActivityServices.shared.calendar,
                showCalendar: AppSettings.shared.showCalendar
            )
            Spacer(minLength: 0)
            controls
        }
        .padding(.horizontal, 28)
        .frame(maxHeight: .infinity)
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    sparkleCount += 1
                } label: {
                    Label("Sparkle", systemImage: "sparkles")
                        .symbolEffect(.bounce, value: sparkleCount)
                }
                .islandControl()
                Button(action: actions.openSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .islandControl()
            }
        }
    }
}

extension View {
    /// A round Liquid Glass button that stays legible on the black island. Glass refracts what is
    /// behind it, and behind it there is only black, so it gets a system fill to refract and a
    /// full-strength label.
    func islandControl() -> some View {
        self
            .labelStyle(.iconOnly)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .background(.fill.tertiary, in: .circle)
    }
}
