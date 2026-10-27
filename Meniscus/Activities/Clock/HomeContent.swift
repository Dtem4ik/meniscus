import SwiftUI

/// The default expanded content: time and date on the left, the next calendar event on the right.
/// Sized by its content; if the island is wider, the gap between the two grows.
struct HomeContent: View {
    let calendar: CalendarService
    let showCalendar: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Redraws once a minute, and only while the island is open.
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if showCalendar {
                Spacer(minLength: 18)
                Divider().frame(height: 40)
                UpcomingEventView(calendar: calendar)
                    .padding(.leading, 18)
            }
        }
    }
}

struct UpcomingEventView: View {
    let calendar: CalendarService

    var body: some View {
        switch calendar.access {
        case .notDetermined:
            Button {
                Task { await calendar.requestAccess() }
            } label: {
                Label("Show Calendar", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.borderless)
        case .denied:
            Button {
                CalendarService.openPrivacySettings()
            } label: {
                Label("Allow Calendar Access…", systemImage: "calendar.badge.exclamationmark")
            }
            .buttonStyle(.borderless)
        case .granted:
            if let event = calendar.upcoming {
                EventSummary(event: event)
            } else {
                Label("No more events today", systemImage: "calendar")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct EventSummary: View {
    let event: CalendarEventSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(event.title)
                    .font(.headline)
                    .lineLimit(1)
            }
            TimelineView(.everyMinute) { context in
                Text(subtitle(at: context.date))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var color: Color {
        guard let rgb = event.calendarColor else { return .accentColor }
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private func subtitle(at date: Date) -> String {
        if event.isAllDay { return String(localized: "All day") }
        let time = Date.FormatStyle(date: .omitted, time: .shortened)
        if event.isOngoing(at: date) {
            return String(localized: "Now · until \(event.end.formatted(time))")
        }
        let relative = event.start.formatted(.relative(presentation: .named, unitsStyle: .wide))
        return "\(event.start.formatted(time)) · \(relative)"
    }
}
