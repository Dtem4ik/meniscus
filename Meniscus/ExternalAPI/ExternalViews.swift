import AppKit
import SwiftUI

extension MiniBanner {
    /// The verified app's icon (or the neutral `app.badge`), the caller's title and subtitle, and
    /// the state on the right. The caller chooses none of the look.
    static func external(_ banner: ExternalNotices.Banner) -> MiniBanner {
        MiniBanner(
            leading: ExternalSourceIcon.image(for: banner.source).map { .appIcon($0) } ?? .symbol("app.badge"),
            title: banner.text.title,
            subtitle: banner.text.subtitle,
            trailing: banner.state == .info ? nil : .state(banner.state)
        )
    }
}

/// The left wing of a running external activity: the source's icon, or the neutral symbol.
struct ExternalSourceIcon: View {
    let source: APISource?

    static func image(for source: APISource?) -> NSImage? {
        guard let url = source?.appURL else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }

    var body: some View {
        if let image = Self.image(for: source) {
            Image(nsImage: image)
                .resizable()
                .frame(width: 18, height: 18)
                .accessibilityLabel(Text(source?.name ?? ""))
        } else {
            Image(systemName: "app.badge")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .accessibilityHidden(true)
        }
    }
}

/// The right wing: a quiet indicator, the attention glyph when something needs the user, and
/// the number of running tasks when there are several. No text: titles show in banners and in
/// the open island.
struct ExternalActivityIndicator: View {
    let group: ExternalNotices.Group?

    var body: some View {
        HStack(spacing: 4) {
            if group?.needsAttention == true {
                NoticeStateGlyph(state: .attention, size: 13)
            } else {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                    .accessibilityLabel(Text("Running"))
            }
            if let count = group?.count, count > 1 {
                Text(count.formatted())
                    .font(CompactText.font)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
        }
        .fixedSize()
    }
}
