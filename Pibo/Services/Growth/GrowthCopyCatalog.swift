import Foundation
import os
import PiboCore

/// One authored line. `band`, `kind` and `level` narrow a record to one
/// situation; records without them are the event's general pool.
struct GrowthCopyRecord: Equatable {
    let id: String
    let event: String
    let tone: String
    let band: Int?
    let kind: Int?
    let level: Int?
    let text: String
}

struct GrowthCopyQuery {
    var event: String
    var tone: PiboCoreGrowthTone
    var band: Int?
    var kind: Int?
    var level: Int?
    var values: [String: String]
    /// Only the lines written for the warmest tone the relationship has reached,
    /// so a story moment written once per tone plays in exactly one voice.
    var closestTone: Bool = false
}

/// Cursor storage for the rotation rule; `GrowthStore` is the production owner.
@MainActor
protocol GrowthCopyCursorStore: AnyObject {
    func copyCursor(key: String) -> Int
    func setCopyCursor(key: String, cursor: Int)
}

enum GrowthCopyCatalogError: Error {
    case missingResource(String)
    case invalidRecord(String)
}

/// Rank of a record's `tone` label. A line is eligible while its rank is at or
/// below the listener's tone, so `tone` acts as the record's `minTone`.
@MainActor
func growthToneRank(_ tone: String) -> Int {
    switch tone {
    case "gentle": return 0
    case "tease": return 1
    case "oldFriend": return 2
    default: return -1
    }
}

/// Substitutes `{name}` placeholders; nil when any placeholder has no value.
@MainActor
func renderGrowthTemplate(_ text: String, values: [String: String]) -> String? {
    guard let pattern = GrowthCopyCatalog.placeholderPattern else { return nil }
    let source = text as NSString
    let matches = pattern.matches(in: text, range: NSRange(location: 0, length: source.length))
    var rendered = ""
    var cursor = 0
    var missing = false
    for match in matches {
        rendered += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
        let key = source.substring(with: match.range(at: 1))
        if let value = values[key], !value.isEmpty {
            rendered += value
        } else {
            missing = true
        }
        cursor = match.range.location + match.range.length
    }
    rendered += source.substring(from: cursor)
    return missing ? nil : rendered
}

/// Growth moments' lines (decision 057). Tone gating follows Core's hearts
/// tiers; the next line inside the eligible pool is chosen by Core's record
/// cursor so the order matches the pat catalog's rotation rule.
///
/// Ported from HarmonyOS `entry/src/main/ets/services/growth/GrowthCopyCatalog.ets`.
@MainActor
final class GrowthCopyCatalog {
    static let resourceName = "pibo-growth.zh-Hans"
    static let placeholderPattern = try? NSRegularExpression(pattern: "\\{([a-zA-Z]+)\\}")

    /// Parsed once per process, like the other bundled catalogs.
    static let shared: GrowthCopyCatalog? = {
        do {
            return try bundled()
        } catch {
            GrowthLog.growth.error("growth catalog unavailable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }()

    private let byEvent: [String: [GrowthCopyRecord]]

    private init(byEvent: [String: [GrowthCopyRecord]]) {
        self.byEvent = byEvent
    }

    /// The growth lines by default; decision 058's day lines share the format and
    /// the cursors, so the resource name is a parameter.
    static func bundled(
        bundle: Bundle = .main,
        resource: String = GrowthCopyCatalog.resourceName
    ) throws -> GrowthCopyCatalog {
        guard let url = bundle.url(forResource: resource, withExtension: "jsonl"),
              let jsonl = try? String(contentsOf: url, encoding: .utf8) else {
            throw GrowthCopyCatalogError.missingResource(resource)
        }
        return try parse(jsonl)
    }

    static func parse(_ jsonl: String) throws -> GrowthCopyCatalog {
        var byEvent: [String: [GrowthCopyRecord]] = [:]
        var ids = Set<String>()
        for row in jsonl.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = row.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dictionary = object as? [String: Any] else {
                throw GrowthCopyCatalogError.invalidRecord(line)
            }
            let id = dictionary["id"] as? String ?? ""
            let event = dictionary["event"] as? String ?? ""
            // Decision 057 spells the tier `minTone`; the shipped table uses `tone`.
            let tone = dictionary["tone"] as? String ?? dictionary["minTone"] as? String ?? ""
            let text = dictionary["text"] as? String ?? ""
            guard !id.isEmpty, !ids.contains(id), !event.isEmpty, growthToneRank(tone) >= 0, !text.isEmpty else {
                throw GrowthCopyCatalogError.invalidRecord(id)
            }
            ids.insert(id)
            let record = GrowthCopyRecord(
                id: id,
                event: event,
                tone: tone,
                band: (dictionary["band"] as? NSNumber)?.intValue,
                kind: (dictionary["kind"] as? NSNumber)?.intValue,
                level: (dictionary["level"] as? NSNumber)?.intValue,
                text: text
            )
            byEvent[event, default: []].append(record)
        }
        return GrowthCopyCatalog(byEvent: byEvent)
    }

    func count(event: String) -> Int {
        byEvent[event]?.count ?? 0
    }

    /// Picks the next line for a moment, or nil when nothing fits.
    func select(_ query: GrowthCopyQuery, cursors: GrowthCopyCursorStore) -> String? {
        guard let records = byEvent[query.event], !records.isEmpty else { return nil }

        func fits(_ record: GrowthCopyRecord, specific: Bool) -> Bool {
            if growthToneRank(record.tone) > Int(query.tone.rawValue) { return false }
            if renderGrowthTemplate(record.text, values: query.values) == nil { return false }
            let narrowed = record.band != nil || record.kind != nil || record.level != nil
            if specific != narrowed { return false }
            if let band = record.band, band != query.band { return false }
            if let kind = record.kind, kind != query.kind { return false }
            if let level = record.level, level != query.level { return false }
            return true
        }

        // A line written for exactly this situation wins over the general pool.
        var eligible = records.map { fits($0, specific: true) }
        if !eligible.contains(true) {
            eligible = records.map { fits($0, specific: false) }
        }
        if query.closestTone {
            var top = -1
            for index in records.indices where eligible[index] {
                top = max(top, growthToneRank(records[index].tone))
            }
            for index in records.indices {
                eligible[index] = eligible[index] && growthToneRank(records[index].tone) == top
            }
        }
        let key = "growth.\(query.event)"
        guard let selected = Self.selectRecord(cursor: cursors.copyCursor(key: key), eligible: eligible) else {
            return nil
        }
        cursors.setCopyCursor(key: key, cursor: Self.nextRecordCursor(selected: selected, count: records.count))
        return renderGrowthTemplate(records[selected].text, values: query.values)
    }

    // MARK: - Core's rotation rule
    //
    // `pibo-core` exports `PatSelectRecord` / `PatNextRecordCursor` (HarmonyOS
    // binds them as `PiboCorePat.selectRecord` / `nextRecordCursor`), but the
    // Swift bindings in `PiboGrowth.swift` do not wrap them yet. These two
    // helpers mirror the Core rule verbatim — walk forward from the cursor to
    // the first eligible record, then advance one — so the rotation order is
    // identical; delete them once the Swift binding lands.

    static func selectRecord(cursor: Int, eligible: [Bool]) -> Int? {
        guard !eligible.isEmpty else { return nil }
        let start = max(0, cursor) % eligible.count
        for step in 0..<eligible.count {
            let index = (start + step) % eligible.count
            if eligible[index] { return index }
        }
        return nil
    }

    static func nextRecordCursor(selected: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (selected + 1) % count
    }
}
