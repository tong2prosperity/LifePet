import PiboCore

enum PiboCorePatAdapter {
    enum Decision {
        case ignored
        case stateSpeech
        case storySpeech
    }

    static func decide(
        spokenIn24Hours: Int,
        spokenIn10Minutes: Int,
        speechRoll: Double,
        storyRoll: Double,
        hasUnrevealedStory: Bool
    ) -> Decision {
        switch PiboCorePat.decide(
            spokenIn24Hours: spokenIn24Hours,
            spokenIn10Minutes: spokenIn10Minutes,
            speechRoll: speechRoll,
            storyRoll: storyRoll,
            hasUnrevealedStory: hasUnrevealedStory
        ) {
        case .ignored: .ignored
        case .stateSpeech: .stateSpeech
        case .storySpeech: .storySpeech
        }
    }
}

