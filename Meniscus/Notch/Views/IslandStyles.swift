import SwiftUI

// Three experiments for going from the black hardware notch to Liquid Glass. In every style the
// collapsed state is solid black and matches the notch exactly; they differ only when expanded.

/// A · The whole island is black, like Dynamic Island. Glass is used only for the controls inside.
struct ObsidianIsland: View {
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
                IslandPlaceholderContent(controlsAreGlass: true, actions: context.actions)
            }
            .mask { shape }
        }
        // Black stays black in Light Mode, so the content must use dark-appearance colors.
        .environment(\.colorScheme, .dark)
    }
}

/// B · A black band around the notch flows into a glass panel below it.
struct MeniscusIsland: View {
    let context: IslandContext

    /// Height of the gradient from the black band into the glass.
    private static let bandFade: CGFloat = 22

    var body: some View {
        let shape = context.shape
        let layout = context.layout
        ZStack(alignment: .top) {
            IslandContentLayer(
                context: context,
                topInset: layout.notchHeight + Self.bandFade / 2,
                height: layout.contentHeight - Self.bandFade / 2,
                horizontalOffset: layout.centerOffset
            ) {
                IslandPlaceholderContent(controlsAreGlass: false, actions: context.actions)
            }
            .clipShape(shape)
            .glassEffect(context.isExpanded ? .regular : .identity, in: shape)

            shape
                .fill(.black)
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        Rectangle().frame(height: layout.notchHeight)
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.bandFade)
                        Spacer(minLength: 0)
                    }
                }
                .allowsHitTesting(false)
        }
    }
}

/// C · The notch stays as it is; a separate glass drop flows out from under it.
struct DropletIsland: View {
    let context: IslandContext

    var body: some View {
        let layout = context.layout
        let metrics = layout.metrics
        let expanded = context.isExpanded
        let notch = NotchShape(layout.shape(for: .collapsed), centerOffset: layout.centerOffset)

        // Collapsed, the drop is a small pill hidden behind the notch; expanded, it hangs below.
        let dropWidth = expanded ? layout.expandedWidth : layout.geometry.notchRect.width * 0.5
        let dropHeight = expanded ? layout.contentHeight - metrics.dropletGap : layout.notchHeight * 0.5
        let dropY = expanded ? layout.notchHeight + metrics.dropletGap : layout.notchHeight * 0.25
        let drop = RoundedRectangle(
            cornerRadius: expanded ? metrics.dropletCornerRadius : dropHeight / 2,
            style: .continuous
        )

        ZStack(alignment: .top) {
            IslandContentLayer(
                context: context,
                topInset: 0,
                height: layout.contentHeight - metrics.dropletGap
            ) {
                IslandPlaceholderContent(controlsAreGlass: false, actions: context.actions)
            }
            .frame(width: dropWidth, height: dropHeight, alignment: .top)
            .clipShape(drop)
            .glassEffect(expanded ? .regular : .identity, in: drop)
            .offset(x: layout.centerOffset, y: dropY)

            notch.fill(.black)
        }
    }
}

/// Stand-in content until the activities of stage 1 arrive. Lets us judge text and controls on
/// each style.
struct IslandPlaceholderContent: View {
    /// Glass controls on black (style A); plain controls when the panel itself is glass, because
    /// glass must not sit on glass.
    var controlsAreGlass: Bool
    var actions: NotchActions

    @State private var sparkleCount = 0

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Meniscus")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                Text("Nothing here yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            controls
        }
        .padding(.horizontal, 28)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var controls: some View {
        let buttons = HStack(spacing: 10) {
            Button {
                sparkleCount += 1
            } label: {
                Label("Sparkle", systemImage: "sparkles")
                    .symbolEffect(.bounce, value: sparkleCount)
            }
            Button(action: actions.openSettings) {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 15, weight: .medium))
        .controlSize(.large)

        if controlsAreGlass {
            GlassEffectContainer(spacing: 10) {
                buttons.buttonStyle(.glass)
            }
        } else {
            buttons.buttonStyle(.borderless)
        }
    }
}
