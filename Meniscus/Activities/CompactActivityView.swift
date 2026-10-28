import SwiftUI

/// What a live activity shows left and right of the notch in the compact island.
struct CompactActivityView: View {
    let activity: LiveActivity
    let layout: IslandLayout

    var body: some View {
        let wing = layout.metrics.compactWingWidth
        HStack(spacing: 0) {
            leading
                .frame(width: wing)
            // The camera housing: nothing can be seen here.
            Color.clear
                .frame(width: layout.geometry.notchRect.width)
            trailing
                .frame(width: wing)
        }
        .frame(height: layout.notchHeight)
        .offset(x: layout.centerOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            CompactSymbol(name: "calendar", color: ActivityServices.shared.meeting?.calendarColor.map {
                Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue)
            } ?? .white)
        case .lowBattery:
            let level = ActivityServices.shared.lowBatteryLevel ?? 0
            CompactSymbol(name: BatteryWarningStyle.symbol(level: level), color: BatteryWarningStyle.color(level: level))
        case .inputSource:
            CompactSymbol(name: "keyboard")
        case .captureSaved:
            CompactSymbol(name: "checkmark.circle.fill", color: .green)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch activity.kind {
        case .charging:
            if let level = ActivityServices.shared.chargingLevel {
                Text((Double(level) / 100).formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.green)
            }
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
            Text(count.formatted())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .accessibilityLabel(Text("Files on the shelf: \(count)"))
        case .dropHint:
            DropHint()
        case .meeting:
            if let meeting = ActivityServices.shared.meeting {
                MeetingCountdown(start: meeting.start)
                    .accessibilityLabel(Text(meeting.title))
            }
        case .lowBattery:
            let level = ActivityServices.shared.lowBatteryLevel ?? 0
            Text((Double(level) / 100).formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(BatteryWarningStyle.color(level: level))
        case .inputSource:
            Text(verbatim: ActivityServices.shared.inputSourceLabel ?? "")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.opacity)
        case .captureSaved:
            Text("Saved")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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

/// "in 5 min", then "now", counting down once a minute while it shows.
private struct MeetingCountdown: View {
    let start: Date

    var body: some View {
        TimelineView(.everyMinute) { context in
            let minutes = MeetingReminder.minutesUntil(start, from: context.date)
            Text(minutes > 0 ? String(localized: "in \(minutes) min") : String(localized: "now"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
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
