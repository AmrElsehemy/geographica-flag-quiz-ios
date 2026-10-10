import Foundation
import GameTimeExperience

/// Geographica's own sensory palette, built from GameTimeKit's reusable controllers.
/// GameTimeKit supplies the engines; this file supplies the feel.
enum FlagQuizFeedback {
    @MainActor
    static func makeController() -> GameFeedbackController {
        GameFeedbackController(
            audio: SynthAudioController(sounds: sounds),
            haptics: CoreHapticsController(patterns: patterns)
        )
    }

    // Mapping onto the kit's semantic events:
    //   .placement  -> correct answer
    //   .invalidMove -> wrong answer
    //   .solve      -> stop completed
    //   .milestone  -> three stars / new chapter
    //   .hint       -> low-fuel warning
    private static let sounds: [GameFeedbackEvent: SynthSound] = [
        .placement: .render(duration: 0.35) { t in 0.5 * SynthSound.bell(1046.5, at: t, decay: 9) },
        .invalidMove: .render(duration: 0.25) { t in 0.6 * sin(2 * .pi * 150 * t) * exp(-t * 12) },
        .hint: .render(duration: 0.3) { t in 0.45 * SynthSound.bell(660, at: t, decay: 8) },
        .solve: .render(duration: 0.9) { t in
            0.4 * (SynthSound.bell(523.25, at: t, decay: 6)
                + SynthSound.bell(659.25, at: t - 0.1, decay: 6)
                + SynthSound.bell(783.99, at: t - 0.2, decay: 6)
                + SynthSound.bell(1046.5, at: t - 0.3, decay: 5))
        },
        .milestone: .render(duration: 1.3) { t in
            0.35 * (SynthSound.bell(659.25, at: t, decay: 5)
                + SynthSound.bell(783.99, at: t - 0.12, decay: 5)
                + SynthSound.bell(1046.5, at: t - 0.24, decay: 5)
                + SynthSound.bell(1318.5, at: t - 0.36, decay: 4)
                + SynthSound.bell(1568.0, at: t - 0.5, decay: 3.5))
        }
    ]

    private static let patterns: [GameFeedbackEvent: HapticPattern] = [
        .placement: HapticPattern([.tap(intensity: 0.6, sharpness: 0.7)]),
        .invalidMove: HapticPattern([
            .tap(intensity: 0.9, sharpness: 0.3),
            .tap(at: 0.09, intensity: 0.7, sharpness: 0.3)
        ]),
        .hint: HapticPattern([.tap(intensity: 0.4, sharpness: 0.5)]),
        .solve: HapticPattern([
            .tap(intensity: 0.5, sharpness: 0.6),
            .tap(at: 0.1, intensity: 0.7, sharpness: 0.7),
            .tap(at: 0.2, intensity: 0.9, sharpness: 0.8)
        ]),
        .milestone: HapticPattern([
            .tap(intensity: 0.5, sharpness: 0.6),
            .tap(at: 0.12, intensity: 0.7, sharpness: 0.7),
            .tap(at: 0.24, intensity: 0.9, sharpness: 0.8),
            .rumble(at: 0.36, duration: 0.4, intensity: 0.6, sharpness: 0.4)
        ])
    ]
}
