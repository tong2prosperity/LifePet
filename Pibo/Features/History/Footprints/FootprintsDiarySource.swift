import Foundation
import PiboCore

// Gathers what each store already recorded into the footprints diary's plain facts (决定 063).
// Read-only: the diary never writes back, and nothing new is inferred about a day.
//
// Ported from HarmonyPibo `services/FootprintsDiarySource.ets`.

/// That day's readout conclusion, only when a current-algorithm snapshot gave a band.
func footprintsReadoutLine(history: HealthHistoryStore, day: Date) -> String {
    let snapshot = WellnessReadout.snapshot(of: history.record(on: day))
    guard let raw = snapshot?.readinessBand,
          let band = PiboCoreWellnessReadinessBand(rawValue: raw),
          band != .unavailable else { return "" }
    return WellnessReadout.conclusion(snapshot, availability: .available(lastCheckedAt: .now))
}

@MainActor
func footprintsDayFacts(day: Date, history: HealthHistoryStore, days: PiboDayStore,
                        polaroids: PolaroidStore,
                        timeline: PiboTimelineStore? = nil) -> FootprintsDayFacts {
    var facts = FootprintsDayFacts()
    facts.readout = footprintsReadoutLine(history: history, day: day)
    if let timeline {
        facts.firsts = timeline.firsts.map { first in
            FootprintsFirstFact(kind: first.kind, at: first.at)
        }
        facts.beats = timeline.toldLog.map { told in
            FootprintsBeatFact(key: told.key, at: told.at, lines: told.lines)
        }
    }
    facts.walks = days.diary.map { entry in
        FootprintsWalkFact(
            at: entry.at,
            destination: piboDestinationName(entry.destination),
            find: piboFindName(entry.item),
            steps: entry.steps,
            item: entry.item
        )
    }
    facts.meals = history.foodPhotos(on: day).map { food in
        FootprintsMealFact(
            id: food.id.uuidString,
            at: food.capturedAt.timeIntervalSince1970,
            mealTypeRaw: food.mealTypeRaw ?? "",
            pngData: food.pngData,
            name: food.dishName ?? food.subjectLabel ?? "",
            sample: history.foodSampleNumber(food.id)
        )
    }
    facts.polaroids = polaroids.shots.map { shot in
        FootprintsPolaroidFact(at: shot.takenAt, path: shot.path, caption: shot.caption,
                               filePath: shot.fileURL.path)
    }
    return facts
}

/// Days the calendar dots: any reading, meal, workout, walk, polaroid or told beat.
@MainActor
func footprintsRecordedDays(history: HealthHistoryStore, days: PiboDayStore,
                            polaroids: PolaroidStore,
                            timeline: PiboTimelineStore? = nil,
                            from start: Date, to end: Date) -> [Date] {
    let readings = history.records(from: start, to: end).filter(\.hasData).map(\.date)
    let walks = days.diary.map { Date(timeIntervalSince1970: $0.at) }
    let shots = polaroids.shots.map { Date(timeIntervalSince1970: $0.takenAt) }
    var result = readings + walks + shots
    if let timeline {
        let told = timeline.toldLog.filter { !$0.lines.isEmpty }.map { Date(timeIntervalSince1970: $0.at) }
        result += told
    }
    return result
}

/// Days the calendar stars: a shared first happened on them.
@MainActor
func footprintsFirstDays(timeline: PiboTimelineStore?) -> [Date] {
    guard let timeline else { return [] }
    return timeline.firsts.map { Date(timeIntervalSince1970: $0.at) }
}
