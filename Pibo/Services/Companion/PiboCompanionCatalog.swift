import Foundation
import PiboCore
import os

/// Decision 054 companion copy: prompts, scene lines and the custom-reply pool,
/// loaded from `pibo-companion.zh-Hans.jsonl` (byte-identical to HarmonyOS).
/// Every eligibility, budget and selection rule is decided by pibo-core; this
/// type only validates and indexes the authored content.
struct PiboCompanionCatalog: Equatable {
    enum HideSeekCondition: Equatable { case any, found, none }

    struct Conditions: Equatable {
        var stateMask: UInt32 = 0
        var patContextMask: UInt32 = 0
        var weatherMask: UInt32 = 0
        var phaseMask: UInt32 = 0
        var hideSeek: HideSeekCondition = .any
    }

    struct Echo: Equatable {
        let id: String
        let lines: [String]
        let weatherMask: UInt32
        let phaseMask: UInt32
    }

    struct Option: Equatable {
        let id: String
        let label: String
        let reaction: [String]
        let mood: PiboCoreCompanionMood
        let echoes: [Echo]
    }

    struct Prompt: Equatable {
        let id: String
        let slotMask: UInt32
        let conditions: Conditions
        let tier: Int
        let retention: PiboCoreCompanionRetention
        let topic: String
        let cooldownDays: Double
        let weight: Int
        let lines: [String]
        let options: [Option]
    }

    struct Line: Equatable {
        let id: String
        let slotMask: UInt32
        let conditions: Conditions
        let lines: [String]
    }

    enum CatalogError: Error, Equatable {
        case invalid(String)
    }

    static let resourceName = "pibo-companion.zh-Hans"
    /// Parsed once per process.
    static let shared: PiboCompanionCatalog? = bundled()
    private static let optionLabelMax = 6

    private(set) var prompts: [Prompt] = []
    private(set) var sceneLines: [Line] = []
    private(set) var customReactions: [Line] = []
    private(set) var customEchoes: [Line] = []

    static func bundled(bundle: Bundle = .main) -> PiboCompanionCatalog? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "jsonl"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            LPLog.speech.error("companion catalog missing")
            return nil
        }
        do {
            return try parse(text)
        } catch {
            LPLog.speech.error("companion catalog invalid: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func prompt(_ id: String) -> Prompt? { prompts.first { $0.id == id } }

    // MARK: Parsing

    private struct RawConditions: Decodable {
        var state: [String]?
        var patContext: [String]?
        var weather: [String]?
        var phase: [String]?
        var hideSeek: String?
    }

    private struct RawEcho: Decodable {
        let id: String
        let lines: [String]
        var weather: [String]?
        var phase: [String]?
    }

    private struct RawOption: Decodable {
        let id: String
        let label: String
        let reaction: [String]
        var mood: String?
        var echoes: [RawEcho]?
    }

    private struct RawRecord: Decodable {
        let type: String
        let id: String
        let status: String
        var slots: [String]?
        var conditions: RawConditions?
        var tier: Int?
        var retention: String?
        var topic: String?
        var cooldownDays: Double?
        var weight: Int?
        let lines: [String]
        var options: [RawOption]?
    }

    static func parse(_ jsonl: String) throws -> PiboCompanionCatalog {
        var catalog = PiboCompanionCatalog()
        var ids = Set<String>()
        let decoder = JSONDecoder()
        for row in jsonl.split(whereSeparator: \.isNewline) {
            let trimmed = row.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let raw = try decoder.decode(RawRecord.self, from: Data(trimmed.utf8))
            guard raw.status == "approved" else { continue }
            guard !raw.id.isEmpty, ids.insert(raw.id).inserted else {
                throw CatalogError.invalid("duplicate id \(raw.id)")
            }
            switch raw.type {
            case "prompt":
                let options = try (raw.options ?? []).map { try option($0, promptID: raw.id) }
                guard options.count == 2, options[0].id != options[1].id else {
                    throw CatalogError.invalid("prompt needs two options \(raw.id)")
                }
                catalog.prompts.append(Prompt(
                    id: raw.id,
                    slotMask: try slotMask(raw.slots, id: raw.id),
                    conditions: try conditions(raw.conditions),
                    tier: min(3, max(1, raw.tier ?? 1)),
                    retention: try retention(raw.retention),
                    topic: raw.topic ?? raw.id,
                    cooldownDays: max(0, raw.cooldownDays ?? 7),
                    weight: max(1, raw.weight ?? 1),
                    lines: try lines(raw.lines, id: raw.id),
                    options: options
                ))
            case "sceneLine":
                catalog.sceneLines.append(Line(
                    id: raw.id,
                    slotMask: try slotMask(raw.slots, id: raw.id),
                    conditions: try conditions(raw.conditions),
                    lines: try lines(raw.lines, id: raw.id)
                ))
            case "customReaction", "customEcho":
                let record = Line(
                    id: raw.id,
                    slotMask: 0,
                    conditions: try conditions(raw.conditions),
                    lines: try lines(raw.lines, id: raw.id)
                )
                guard record.lines.contains(where: { $0.contains("「{custom}」") }) else {
                    throw CatalogError.invalid("custom line must quote 「{custom}」 \(raw.id)")
                }
                if raw.type == "customReaction" {
                    catalog.customReactions.append(record)
                } else {
                    catalog.customEchoes.append(record)
                }
            default:
                throw CatalogError.invalid("unknown type \(raw.type)")
            }
        }
        guard !catalog.customReactions.isEmpty, !catalog.customEchoes.isEmpty else {
            throw CatalogError.invalid("missing custom reply pools")
        }
        return catalog
    }

    static func slot(key: String) -> PiboCoreCompanionSlot? {
        switch key {
        case "pat.after": .patAfter
        case "waking.first": .wakingFirst
        case "return.short": .returnShort
        case "return.long": .returnLong
        case "event.meal": .eventMeal
        case "event.weather": .eventWeather
        case "event.boCollected": .eventBoCollected
        case "scene.grass": .sceneGrass
        case "scene.river": .sceneRiver
        case "scene.hammock": .sceneHammock
        case "hideSeek.timeout": .hideSeekTimeout
        default: nil
        }
    }

    static func key(for slot: PiboCoreCompanionSlot) -> String {
        switch slot {
        case .patAfter: "pat.after"
        case .wakingFirst: "waking.first"
        case .returnShort: "return.short"
        case .returnLong: "return.long"
        case .eventMeal: "event.meal"
        case .eventWeather: "event.weather"
        case .eventBoCollected: "event.boCollected"
        case .sceneGrass: "scene.grass"
        case .sceneRiver: "scene.river"
        case .sceneHammock: "scene.hammock"
        case .hideSeekTimeout: "hideSeek.timeout"
        }
    }

    private static func slotMask(_ keys: [String]?, id: String) throws -> UInt32 {
        var mask: UInt32 = 0
        for key in keys ?? [] {
            guard let slot = slot(key: key) else { throw CatalogError.invalid("slot \(key)") }
            mask |= slot.mask
        }
        guard mask != 0 else { throw CatalogError.invalid("no slot \(id)") }
        return mask
    }

    private static func conditions(_ raw: RawConditions?) throws -> Conditions {
        var result = Conditions()
        for key in raw?.state ?? [] {
            guard let state = stateRaw(key) else { throw CatalogError.invalid("state \(key)") }
            result.stateMask |= 1 << UInt32(state)
        }
        for key in raw?.patContext ?? [] {
            guard let context = PiboCorePatContext.allCases.first(where: { $0.catalogKey == key }) else {
                throw CatalogError.invalid("patContext \(key)")
            }
            result.patContextMask |= 1 << UInt32(context.rawValue)
        }
        result.weatherMask = try weatherMask(raw?.weather)
        result.phaseMask = try phaseMask(raw?.phase)
        switch raw?.hideSeek ?? "" {
        case "": result.hideSeek = .any
        case "found": result.hideSeek = .found
        case "none": result.hideSeek = .none
        default: throw CatalogError.invalid("hideSeek")
        }
        return result
    }

    private static func weatherMask(_ keys: [String]?) throws -> UInt32 {
        try (keys ?? []).reduce(UInt32(0)) { mask, key in
            let weather: PiboCoreCompanionWeather
            switch key {
            case "clear": weather = .clear
            case "cloudy": weather = .cloudy
            case "rain": weather = .rain
            case "snow": weather = .snow
            default: throw CatalogError.invalid("weather \(key)")
            }
            return mask | weather.mask
        }
    }

    private static func phaseMask(_ keys: [String]?) throws -> UInt32 {
        try (keys ?? []).reduce(UInt32(0)) { mask, key in
            let phase: PiboCoreCompanionPhase
            switch key {
            case "morning": phase = .morning
            case "day": phase = .day
            case "evening": phase = .evening
            case "night": phase = .night
            default: throw CatalogError.invalid("phase \(key)")
            }
            return mask | phase.mask
        }
    }

    static func stateRaw(_ key: String) -> Int32? {
        switch key {
        case "dataUnknown": 0
        case "sleeping": 1
        case "waking": 2
        case "stable": 3
        case "energetic": 4
        case "tired": 5
        default: nil
        }
    }

    private static func retention(_ key: String?) throws -> PiboCoreCompanionRetention {
        switch key ?? "today" {
        case "today": .today
        case "recent": .recent
        case "preference": .preference
        default: throw CatalogError.invalid("retention")
        }
    }

    private static func lines(_ values: [String], id: String) throws -> [String] {
        let result = values.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !result.isEmpty else { throw CatalogError.invalid("no lines \(id)") }
        return result
    }

    private static func option(_ raw: RawOption, promptID: String) throws -> Option {
        let label = raw.label.trimmingCharacters(in: .whitespaces)
        guard !raw.id.isEmpty, !label.isEmpty, label.count <= optionLabelMax else {
            throw CatalogError.invalid("option \(promptID)")
        }
        let echoes = try (raw.echoes ?? []).map { echo in
            Echo(
                id: echo.id,
                lines: try lines(echo.lines, id: "\(promptID):\(raw.id):\(echo.id)"),
                weatherMask: try weatherMask(echo.weather),
                phaseMask: try phaseMask(echo.phase)
            )
        }
        guard !echoes.isEmpty else { throw CatalogError.invalid("option echo \(promptID)") }
        let mood: PiboCoreCompanionMood
        switch raw.mood ?? "" {
        case "": mood = .none
        case "coolhide": mood = .coolhide
        case "dive": mood = .dive
        default: throw CatalogError.invalid("mood \(promptID)")
        }
        return Option(
            id: raw.id,
            label: label,
            reaction: try lines(raw.reaction, id: "\(promptID):\(raw.id)"),
            mood: mood,
            echoes: echoes
        )
    }
}
