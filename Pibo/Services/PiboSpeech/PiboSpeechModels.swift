import Foundation

/// A semantic fact that may give Pibo something worth saying. Callers describe
/// what happened; they never choose copy, tone, priority, or cooldowns.
struct PiboSpeechCue: Hashable, Sendable {
    let key: String
    let topic: String
    let values: [String: String]
    let priority: Int

    private init(
        key: String,
        topic: String? = nil,
        values: [String: String] = [:],
        priority: Int
    ) {
        self.key = key
        self.topic = topic ?? key
        self.values = values
        self.priority = priority
    }

    static func weather(_ weather: PiboSpeechWeather) -> PiboSpeechCue {
        PiboSpeechCue(key: "weather.\(weather.rawValue)", priority: 10)
    }

    static func idle(activity: String? = nil) -> PiboSpeechCue {
        PiboSpeechCue(
            key: "ambient.idle",
            values: activity.map { ["activity": $0] } ?? [:],
            priority: 1
        )
    }

    static func sleepShorter(minutes: Int) -> PiboSpeechCue {
        PiboSpeechCue(
            key: "sleep.shorter",
            topic: "sleep.change",
            values: ["minutes": String(abs(minutes))],
            priority: 40
        )
    }

    static func sleepLonger(minutes: Int) -> PiboSpeechCue {
        PiboSpeechCue(
            key: "sleep.longer",
            topic: "sleep.change",
            values: ["minutes": String(abs(minutes))],
            priority: 40
        )
    }

    static func stepsMore(count: Int) -> PiboSpeechCue {
        PiboSpeechCue(
            key: "steps.more",
            topic: "steps.change",
            values: ["steps": String(abs(count))],
            priority: 30
        )
    }

    static func stepsFewer(count: Int) -> PiboSpeechCue {
        PiboSpeechCue(
            key: "steps.fewer",
            topic: "steps.change",
            values: ["steps": String(abs(count))],
            priority: 30
        )
    }

    static func workoutCompleted(minutes: Int) -> PiboSpeechCue {
        PiboSpeechCue(
            key: "workout.completed",
            values: ["minutes": String(max(0, minutes))],
            priority: 25
        )
    }

    static let healthAccumulating = PiboSpeechCue(
        key: "health.accumulating",
        priority: 5
    )

    static let healthDataMissing = PiboSpeechCue(
        key: "health.missing",
        priority: 5
    )

    static func walkCompleted(distanceMeters: Double, duration: TimeInterval) -> PiboSpeechCue {
        let kilometers = distanceMeters / 1_000
        return PiboSpeechCue(
            key: "walk.completed",
            values: [
                "distance": kilometers >= 1
                    ? String(format: "%.1f", kilometers)
                    : String(Int(distanceMeters.rounded())),
                "distanceUnit": kilometers >= 1 ? "公里" : "米",
                "minutes": String(max(1, Int((duration / 60).rounded()))),
            ],
            priority: 35
        )
    }
}

enum PiboSpeechWeather: String, Sendable {
    case clear
    case cloudy
    case rain
    case thunderstorm
    case snow
}

enum PiboSpeechSurface: String, Codable, Sendable {
    case home
    case dashboard
    case sleepCard
    case walkCard
    case game
}

enum PiboSpeechTrigger: String, Sendable {
    case entered
    case expanded
    case completed
    case idle
    case environmentChanged
    case userAction
}

enum PiboSpeechLength: Int, Sendable {
    case tiny = 0
    case short = 1
    case medium = 2
}

struct PiboSpeechContext: Hashable, Sendable {
    let surface: PiboSpeechSurface
    let trigger: PiboSpeechTrigger
    let length: PiboSpeechLength

    static func home(
        trigger: PiboSpeechTrigger,
        length: PiboSpeechLength = .short
    ) -> PiboSpeechContext {
        PiboSpeechContext(surface: .home, trigger: trigger, length: length)
    }

    static func dashboard(
        trigger: PiboSpeechTrigger = .entered,
        length: PiboSpeechLength = .short
    ) -> PiboSpeechContext {
        PiboSpeechContext(surface: .dashboard, trigger: trigger, length: length)
    }

    static func walk(
        trigger: PiboSpeechTrigger,
        length: PiboSpeechLength = .short
    ) -> PiboSpeechContext {
        PiboSpeechContext(surface: .walkCard, trigger: trigger, length: length)
    }
}

enum PiboSpeechPresentation: String, Codable, Sendable {
    case normal
    case angry
    case murmur
    case story
}

struct PiboSpeech: Equatable, Sendable {
    let id: String
    let text: String
    let presentation: PiboSpeechPresentation
    let cueKey: String
}
