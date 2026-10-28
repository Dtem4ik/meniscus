import SwiftUI

/// What a live activity shows left and right of the notch in the compact island. Every activity
/// follows one pattern: a symbol on the left, a short value on the right. Both sides are as wide
/// as the wider of the two (measured, see `CompactSlotMeasure`), so the notch stays centered.
struct CompactActivityView: View {
    let activity: LiveActivity
    let layout: IslandLayout
    let wing: CGFloat

    var body: some View {
        let slot = max(wing - 2 * layout.metrics.compactSlotPadding, 0)
        HStack(spacing: 0) {
            CompactSlot(activity: activity, side: .leading)
                .frame(width: slot)
                .frame(width: wing)
            // The camera housing: nothing can be seen here.
            Color.clear
                .frame(width: layout.geometry.notchRect.width)
            CompactSlot(activity: activity, side: .trailing)
                .frame(width: slot)
                .frame(width: wing)
        }
        .frame(height: layout.notchHeight)
        .offset(x: layout.centerOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Both sides of an activity at their natural width, never shown: the island takes the wider one.
struct CompactSlotMeasure: View {
    let activity: LiveActivity

    var body: some View {
        ZStack {
            CompactSlot(activity: activity, side: .leading).fixedSize()
            CompactSlot(activity: activity, side: .trailing).fixedSize()
        }
    }
}

/// One side of a compact activity.
struct CompactSlot: View {
    enum Side { case leading, trailing }

    let activity: LiveActivity
    let side: Side

    var body: some View {
        switch side {
        case .leading: leading
        case .trailing: trailing
        }
    }

    @ViewBuilder
    private var leading: some View {
        switch activity.kind {
        case .charging:
            ChargingBolt()
        case .nowPlaying:
            CompactArtwork(service: ActivityServices.shared.nowPlaying)
        case .shelf, .dropHint:
            CompactSymbol(name: "paperclip")
        case .meeting:
            CompactSymbol(name: "calendar", color: ActivityServices.shared.meetingEvent?.calendarColor.map {
                Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue)
            } ?? .white)
        case .lowBattery:
            let level = ActivityServices.shared.lowBatteryLevel ?? 0
            CompactSymbol(name: BatteryWarningStyle.symbol(level: level), color: BatteryWarningStyle.color(level: level))
        case .inputSource:
            CompactSymbol(name: "keyboard")
        case .captureSaved:
            CompactSymbol(name: "checkmark.circle.fill", color: .green)
        case .bluetoothDevice:
            // Shown as a mini banner, not on the sides.
            EmptyView()
        case .deviceLowBattery:
            let device = ActivityServices.shared.deviceLowBattery
            CompactSymbol(name: device?.kind.symbol ?? "battery.25percent", color: BatteryWarningStyle.color(level: device?.battery?.main ?? 0))
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch activity.kind {
        case .charging:
            CompactValue(text: CompactText.percent(ActivityServices.shared.chargingLevel ?? 0), color: .green)
        case .nowPlaying:
            let nowPlaying = ActivityServices.shared.nowPlaying
            let shelfCount = ShelfController.shared.visibleCount
            HStack(spacing: 5) {
                Equalizer(
                    isPlaying: nowPlaying.current?.isPlaying ?? false,
                    tint: nowPlaying.artworkTint.map(Color.init(nsColor:)) ?? .primary
                )
                // Music comes first; a small count reminds of files on the shelf.
                if shelfCount > 0 {
                    ShelfCountBadge(count: shelfCount)
                }
            }
        case .shelf:
            let count = ShelfController.shared.items.count
            CompactValue(text: count.formatted())
                .contentTransition(.numericText())
                .accessibilityLabel(Text("Files on the shelf: \(count)"))
        case .dropHint:
            DropHint()
        case .meeting:
            let services = ActivityServices.shared
            CompactValue(text: CompactText.meeting(start: services.meetingEvent?.start ?? Date(), moment: services.meetingMoment, at: Date()))
                .accessibilityLabel(Text(services.meetingEvent?.title ?? ""))
        case .lowBattery:
            let level = ActivityServices.shared.lowBatteryLevel ?? 0
            CompactValue(text: CompactText.percent(level), color: BatteryWarningStyle.color(level: level))
        case .inputSource:
            CompactValue(text: ActivityServices.shared.inputSourceLabel ?? "")
                .contentTransition(.opacity)
        case .captureSaved:
            // Shortened, never cut: the check mark on the left already says it.
            ViewThatFits(in: .horizontal) {
                CompactValue(text: String(localized: "Saved"))
                CompactValue(text: "✓")
            }
        case .bluetoothDevice:
            EmptyView()
        case .deviceLowBattery:
            let device = ActivityServices.shared.deviceLowBattery
            let level = device?.battery?.main ?? 0
            CompactValue(text: CompactText.percent(level), color: BatteryWarningStyle.color(level: level))
                .accessibilityLabel(Text(device?.name ?? ""))
        }
    }
}

/// The short value on the right: one line, digits that don't jump.
private struct CompactValue: View {
    let text: String
    var color: Color = .white

    var body: some View {
        Text(verbatim: text)
            .font(CompactText.font)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }
}

/// The short values, kept apart so tests can check that they fit.
enum CompactText {
    static let font = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let fontSize: CGFloat = 13

    static func percent(_ level: Int) -> String {
        (Double(level) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    private static func minutesText(_ minutes: Int) -> String {
        String(localized: "\(minutes) min")
    }

    /// "6 min" before the meeting, "now" when it starts.
    static func meeting(start: Date, moment: MeetingReminder.Moment, at date: Date) -> String {
        switch moment {
        case .starting:
            String(localized: "now")
        case .soon:
            minutesText(max(MeetingReminder.minutesUntil(start, from: date), 1))
        }
    }
}

/// A symbol on one side of the compact island.
private struct CompactSymbol: View {
    let name: String
    var color: Color = .white

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// Yellow at 20%, red at 10%, like the battery in the menu bar.
nonisolated enum BatteryWarningStyle {
    static func symbol(level: Int) -> String {
        level <= 10 ? "battery.0percent" : "battery.25percent"
    }

    static func color(level: Int) -> Color {
        level <= 10 ? .red : .yellow
    }
}

/// An arrow toward the notch, gently bouncing while a file is dragged anywhere: drop it here.
private struct DropHint: View {
    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .symbolEffect(.bounce.up, options: .repeating)
            .accessibilityLabel(Text("Drop here"))
    }
}

/// The shelf's symbol and how many files are on it, next to the equalizer while music plays.
private struct ShelfCountBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "paperclip")
                .font(.system(size: 9, weight: .bold))
            Text(count.formatted())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white.opacity(0.85))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Files on the shelf: \(count)"))
    }
}

/// The bolt bounces once when the activity appears.
private struct ChargingBolt: View {
    @State private var didAppear = false

    var body: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.green)
            .symbolEffect(.bounce, value: didAppear)
            .onAppear { didAppear = true }
            .accessibilityLabel(Text("Charging"))
    }
}
