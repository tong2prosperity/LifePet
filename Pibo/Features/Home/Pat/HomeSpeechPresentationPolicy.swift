import Foundation

enum HomeSpeechPresentationPolicy {
    static func line(for speech: PiboSpeech) -> PiboSpeechLine {
        let mood: PiboSpeechMood = switch speech.presentation {
        case .normal, .story: .normal
        case .angry: .angry
        case .murmur: .murmur
        }
        return PiboSpeechLine(
            text: speech.text,
            mood: mood,
            isStoryClue: speech.presentation == .story
        )
    }

    /// The bubble a pat earns while Core has authored content for the current
    /// pose. `sleep` is deliberately **not** a line of Pibo's: asleep it cannot
    /// answer, so the app posts a system notice instead of putting words in a
    /// sleeping character's mouth.
    static func animationPatLine(contentID: String, angry: Bool) -> PiboSpeechLine? {
        switch contentID {
        case "animation.sleep.pat":
            .system(AppLocalization.narrative("home.sleep.pat"))
        case "animation.awake.pat":
            PiboSpeechLine(
                text: AppLocalization.narrative("home.awake.pat"),
                mood: angry ? .angry : .normal
            )
        case "animation.angry.enter":
            PiboSpeechLine(
                text: AppLocalization.narrative("home.angry.enter"),
                mood: angry ? .angry : .normal
            )
        default:
            nil
        }
    }

    /// A system notice is a full sentence rather than a garbled fragment, so
    /// it holds a beat longer than ordinary speech.
    static func lingerDuration(for line: PiboSpeechLine) -> TimeInterval {
        if line.data != nil {
            5.0
        } else if line.source == .system {
            3.0
        } else if line.mood == .murmur || line.isStoryClue {
            3.4
        } else {
            2.0
        }
    }
}
