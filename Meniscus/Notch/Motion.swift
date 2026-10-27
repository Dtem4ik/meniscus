import SwiftUI

/// Every motion parameter of the island lives here, so the feel can be tuned in one file.
///
/// Only springs are used for movement. `duration` is the perceived duration and `bounce` is how
/// much the spring overshoots (0 = none, 0.3 = playful); see `Animation.spring(duration:bounce:)`.
nonisolated enum Motion {
    // MARK: Shape

    /// Notch → island. A little overshoot, like Dynamic Island on iPhone.
    static let expand = Animation.spring(duration: 0.46, bounce: 0.24)
    /// Island → notch. Settles without overshoot so the notch never "wobbles" past the hardware.
    static let collapse = Animation.spring(duration: 0.36, bounce: 0.0)
    /// How long the shape waits before collapsing, so content fades out first.
    static let collapseDelay: Double = 0.07

    // MARK: Content

    /// Content appears once the shape is mostly open: blur → sharp, slightly scaled up.
    static let contentIn = Animation.smooth(duration: 0.32)
    static let contentInDelay: Double = 0.14
    /// Content leaves quickly, before the shape closes.
    static let contentOut = Animation.smooth(duration: 0.14)
    static let contentBlurRadius: CGFloat = 12
    static let contentScale: CGFloat = 0.94

    /// Artwork and text of the next track cross-fade in place.
    static let trackChange = Animation.smooth(duration: 0.35)
    /// Player buttons dip slightly while pressed and spring back.
    static let controlPress = Animation.spring(duration: 0.22, bounce: 0.35)
    static let controlPressScale: CGFloat = 0.88
    /// Hover highlight behind player buttons.
    static let controlHover = Animation.smooth(duration: 0.15)

    /// How long "Saved" shows after a quick capture before the island closes.
    static let captureSavedHold: Duration = .milliseconds(900)

    // MARK: Pointer intent

    /// How long the pointer must rest on the notch before it opens. Prevents accidental opening
    /// when the pointer passes the notch on its way across the menu bar.
    static let hoverIntentDelay: Duration = .milliseconds(180)
    /// How long the pointer may be outside the island before it closes.
    static let collapseGrace: Duration = .milliseconds(120)

    // MARK: Accessibility and debugging

    /// With Reduce Motion on, the shape does not morph: the island cross-fades in and out.
    static let reducedMotionFade = Animation.smooth(duration: 0.18)
    /// Speed multiplier of the "Slow Animations" developer option.
    static let slowMotionFactor: Double = 0.2
}

/// The animations for one transition, adjusted for Reduce Motion and the slow-motion option.
nonisolated struct MotionProfile: Sendable {
    var reduceMotion: Bool
    var slowMotion: Bool

    var expand: Animation { tuned(reduceMotion ? Motion.reducedMotionFade : Motion.expand) }
    var collapse: Animation {
        tuned(reduceMotion ? Motion.reducedMotionFade : Motion.collapse.delay(Motion.collapseDelay))
    }
    var contentIn: Animation {
        tuned(reduceMotion ? Motion.reducedMotionFade : Motion.contentIn.delay(Motion.contentInDelay))
    }
    var contentOut: Animation { tuned(reduceMotion ? Motion.reducedMotionFade : Motion.contentOut) }

    private func tuned(_ animation: Animation) -> Animation {
        slowMotion ? animation.speed(Motion.slowMotionFactor) : animation
    }
}

/// Blur-to-sharp reveal for island content.
struct ContentRevealModifier: ViewModifier {
    var isRevealed: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            .blur(radius: isRevealed ? 0 : Motion.contentBlurRadius)
            .scaleEffect(isRevealed ? 1 : Motion.contentScale, anchor: .top)
    }
}

extension AnyTransition {
    static var contentReveal: AnyTransition {
        .modifier(active: ContentRevealModifier(isRevealed: false), identity: ContentRevealModifier(isRevealed: true))
    }
}
