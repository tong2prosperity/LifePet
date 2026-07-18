import Foundation
import os

struct PiboSpeechEntry: Codable, Equatable, Sendable {
    let id: String
    let cue: String
    let surfaces: [PiboSpeechSurface]
    let text: String
    var presentation: PiboSpeechPresentation = .normal
    var length: PiboSpeechLengthValue = .short
    var minimumStoryProgress: Int = 0
    var cooldownHours: Double = 0
    var topicCooldownHours: Double = 0
    var maximumUses: Int? = nil
    var weight: Int = 1

    private enum CodingKeys: String, CodingKey {
        case id, cue, surfaces, text, presentation, length
        case minimumStoryProgress, cooldownHours, topicCooldownHours, maximumUses, weight
    }

    init(
        id: String,
        cue: String,
        surfaces: [PiboSpeechSurface],
        text: String,
        presentation: PiboSpeechPresentation = .normal,
        length: PiboSpeechLengthValue = .short,
        minimumStoryProgress: Int = 0,
        cooldownHours: Double = 0,
        topicCooldownHours: Double = 0,
        maximumUses: Int? = nil,
        weight: Int = 1
    ) {
        self.id = id
        self.cue = cue
        self.surfaces = surfaces
        self.text = text
        self.presentation = presentation
        self.length = length
        self.minimumStoryProgress = minimumStoryProgress
        self.cooldownHours = cooldownHours
        self.topicCooldownHours = topicCooldownHours
        self.maximumUses = maximumUses
        self.weight = weight
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        cue = try values.decode(String.self, forKey: .cue)
        surfaces = try values.decode([PiboSpeechSurface].self, forKey: .surfaces)
        text = try values.decode(String.self, forKey: .text)
        presentation = try values.decodeIfPresent(
            PiboSpeechPresentation.self,
            forKey: .presentation
        ) ?? .normal
        length = try values.decodeIfPresent(PiboSpeechLengthValue.self, forKey: .length) ?? .short
        minimumStoryProgress = try values.decodeIfPresent(
            Int.self,
            forKey: .minimumStoryProgress
        ) ?? 0
        cooldownHours = try values.decodeIfPresent(Double.self, forKey: .cooldownHours) ?? 0
        topicCooldownHours = try values.decodeIfPresent(
            Double.self,
            forKey: .topicCooldownHours
        ) ?? 0
        maximumUses = try values.decodeIfPresent(Int.self, forKey: .maximumUses)
        weight = max(1, try values.decodeIfPresent(Int.self, forKey: .weight) ?? 1)
    }
}

enum PiboSpeechLengthValue: String, Codable, Sendable {
    case tiny
    case short
    case medium

    var value: PiboSpeechLength {
        switch self {
        case .tiny: return .tiny
        case .short: return .short
        case .medium: return .medium
        }
    }
}

struct PiboSpeechCatalog {
    private let entriesByCue: [String: [PiboSpeechEntry]]

    init(entries: [PiboSpeechEntry]) {
        entriesByCue = Dictionary(grouping: entries, by: \PiboSpeechEntry.cue)
    }

    func entries(
        for cue: PiboSpeechCue,
        context: PiboSpeechContext,
        storyProgress: Int
    ) -> [PiboSpeechEntry] {
        (entriesByCue[cue.key] ?? []).filter { entry in
            entry.surfaces.contains(context.surface)
                && entry.length.value.rawValue <= context.length.rawValue
                && entry.minimumStoryProgress <= storyProgress
        }
    }

    static func bundled(bundle: Bundle = .main) -> PiboSpeechCatalog {
        let resources = [
            "pibo-speech-ambient",
            "pibo-speech-health",
            "pibo-speech-walk",
            "pibo-speech-games",
            "pibo-speech-narrative",
        ]
        let decoder = JSONDecoder()
        var entries: [PiboSpeechEntry] = []

        for resource in resources {
            let url = bundle.url(forResource: resource, withExtension: "json")
                ?? bundle.url(
                    forResource: resource,
                    withExtension: "json",
                    subdirectory: "PiboSpeech"
                )
            guard let url else {
                LPLog.app.error("Pibo speech resource missing: \(resource, privacy: .public)")
                continue
            }
            do {
                let data = try Data(contentsOf: url)
                entries.append(contentsOf: try decoder.decode([PiboSpeechEntry].self, from: data))
            } catch {
                LPLog.app.error("Pibo speech resource invalid: \(resource, privacy: .public) \(error.localizedDescription, privacy: .public)")
            }
        }

        let duplicateIDs = Dictionary(grouping: entries, by: \PiboSpeechEntry.id)
            .filter { $0.value.count > 1 }
            .keys
        if !duplicateIDs.isEmpty {
            LPLog.app.error("Duplicate Pibo speech IDs: \(duplicateIDs.sorted().joined(separator: ","), privacy: .public)")
        }
        return PiboSpeechCatalog(entries: entries)
    }
}
