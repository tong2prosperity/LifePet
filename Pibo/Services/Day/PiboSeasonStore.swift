import Foundation
import Observation

// The story, kept on this phone only (decisions 059 and 062): which beats Pibo has
// played, when the seed went in, the report it wrote and the letters that came back —
// then, across the creek, the planks, the notebook and the old pod. Core decides when
// each beat is due and how far the seed has grown; this only remembers what happened.
//
// Ported from HarmonyPibo `services/day/PiboSeasonStore.ets`. HarmonyOS keeps
// `preferences` store `pibo_season` with key `state.v1`; iOS uses one `UserDefaults` key,
// `pibo_season/state.v1`, holding the same JSON snapshot (including the nested `two`).

/// Letters kept for re-reading on the mailbox; older ones fall off.
private let lettersKeep = 24
private let planksMax = 5

/// One letter from home, as the mailbox keeps it.
struct PiboSeasonLetter: Equatable {
    /// The letter's `kind` in the story copy.
    var index = 0
    var day = 0
    var read = false
}

/// One notebook page Pibo corrected: which page, and whether your own days proved it wrong.
struct PiboNotebookPage: Equatable {
    var page = 0
    var backed = false
    var day = 0
}

/// Local day number: whole days since the epoch in this phone's time zone.
func piboLocalDay(_ now: Double, timeZone: TimeZone = .current) -> Int {
    let date = Date(timeIntervalSince1970: now / 1000)
    let shifted = now / 1000 + Double(timeZone.secondsFromGMT(for: date))
    return Int((shifted / 86_400).rounded(.down))
}

@MainActor
@Observable
final class PiboSeasonStore {
    static let defaultsKey = "pibo_season/state.v1"

    // Season one, "种子".
    var completedBeats = 0
    var lastBeatDay = -1
    var plantedDay = -1
    /// The lifetime `bo` count when the seed went in, so growth counts only `bo` since.
    var boAtPlanting = 0
    var seasonDoneDay = -1
    var lastLetterDay = -1
    var lettersReceived = 0
    private(set) var letters: [PiboSeasonLetter] = []
    /// The report's lines, kept as written so it reads the same every time.
    private(set) var report: [String] = []

    // Season two, "小溪那边".
    private(set) var twoCompleted = 0
    private(set) var twoLastBeatDay = -1
    private(set) var planks = 0
    private(set) var lastPlankDay = -1
    private(set) var pages: [PiboNotebookPage] = []
    private(set) var twoDoneDay = -1
    private(set) var lastRereadDay = -1
    /// Whether the notebook's first page was proved wrong by your own days (beat four).
    private(set) var firstPageBacked = false

    private(set) var revision = 0

    private let defaults: UserDefaults
    private let persistenceKey: String

    init(defaults: UserDefaults = .standard,
         persistenceKey: String = PiboSeasonStore.defaultsKey) {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        restore(defaults.string(forKey: persistenceKey) ?? "")
    }

    func restore(_ raw: String) {
        completedBeats = 0
        lastBeatDay = -1
        plantedDay = -1
        boAtPlanting = 0
        seasonDoneDay = -1
        lastLetterDay = -1
        lettersReceived = 0
        letters = []
        report = []
        restoreTwo(nil)
        if !raw.isEmpty, let data = raw.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            completedBeats = max(0, int(parsed["completedBeats"], 0))
            lastBeatDay = int(parsed["lastBeatDay"], -1)
            plantedDay = int(parsed["plantedDay"], -1)
            boAtPlanting = max(0, int(parsed["boAtPlanting"], 0))
            seasonDoneDay = int(parsed["seasonDoneDay"], -1)
            lastLetterDay = int(parsed["lastLetterDay"], -1)
            lettersReceived = max(0, int(parsed["lettersReceived"], 0))
            letters = (parsed["letters"] as? [[String: Any]] ?? []).compactMap { letter in
                guard let index = letter["index"] as? Int, index >= 0 else { return nil }
                return PiboSeasonLetter(index: index,
                                        day: letter["day"] as? Int ?? 0,
                                        read: letter["read"] as? Bool ?? false)
            }
            report = (parsed["report"] as? [String] ?? []).filter { !$0.isEmpty }
            restoreTwo(parsed["two"] as? [String: Any])
        }
        revision += 1
    }

    private func restoreTwo(_ two: [String: Any]?) {
        twoCompleted = max(0, int(two?["completedBeats"], 0))
        twoLastBeatDay = int(two?["lastBeatDay"], -1)
        planks = max(0, int(two?["planks"], 0))
        lastPlankDay = int(two?["lastPlankDay"], -1)
        pages = (two?["pages"] as? [[String: Any]] ?? []).compactMap { page in
            guard let index = page["page"] as? Int, index >= 0 else { return nil }
            return PiboNotebookPage(page: index,
                                    backed: page["backed"] as? Bool ?? false,
                                    day: page["day"] as? Int ?? 0)
        }
        twoDoneDay = int(two?["doneDay"], -1)
        lastRereadDay = int(two?["lastRereadDay"], -1)
        firstPageBacked = two?["firstPageBacked"] as? Bool ?? false
    }

    // --- Season one ---------------------------------------------------------------------

    /// The pod is screwed back on: the seed's story is over.
    var podFixed: Bool { completedBeats >= 4 }
    var hasMailbox: Bool { completedBeats >= 6 }
    var unreadLetter: PiboSeasonLetter? { letters.first { !$0.read } }
    /// The newest letter first.
    var latestLetter: PiboSeasonLetter? { letters.first }

    /// A beat played to the end: the next one waits for another day.
    func completeBeat(_ beat: Int, today: Int) {
        guard beat == completedBeats + 1 else { return }
        completedBeats = beat
        lastBeatDay = today
        persist()
    }

    func plant(today: Int, boLifetime: Int) {
        guard plantedDay < 0 else { return }
        plantedDay = today
        boAtPlanting = max(0, boLifetime)
        persist()
    }

    func writeReport(_ lines: [String]) {
        report = lines
        persist()
    }

    func receiveLetter(_ index: Int, today: Int) {
        let letter = PiboSeasonLetter(index: index, day: today, read: false)
        letters = Array(([letter] + letters).prefix(lettersKeep))
        lastLetterDay = today
        lettersReceived += 1
        persist()
    }

    func markLettersRead() {
        guard letters.contains(where: { !$0.read }) else { return }
        letters = letters.map { letter in
            var read = letter
            read.read = true
            return read
        }
        persist()
    }

    func finishSeason(today: Int) {
        guard seasonDoneDay < 0 else { return }
        seasonDoneDay = today
        persist()
    }

    /// Debug dock only: rewind to just before `beat` so it can be played again today.
    /// The seed is backdated so the sprout already shows the stage that beat expects.
    func debugRewind(beat: Int, today: Int) {
        completedBeats = max(0, beat - 1)
        lastBeatDay = -1
        if beat <= 2 {
            plantedDay = -1
        } else if beat >= 7 {
            plantedDay = today - 10
        } else if beat >= 5 {
            plantedDay = min(plantedDay < 0 ? today : plantedDay, today - 2)
        } else if plantedDay < 0 {
            plantedDay = today
        }
        if beat <= 5 { report = [] }
        if beat <= 6 { letters = [] }
        persist()
    }

    // --- Season two ---------------------------------------------------------------------

    /// The light across the creek has been seen.
    var farLight: Bool { twoCompleted >= 1 }
    var oldPodFound: Bool { twoCompleted >= 3 }
    var hasNotebook: Bool { twoCompleted >= 4 }
    var oldPodLit: Bool { twoCompleted >= 7 }

    var pagesUsedMask: UInt32 {
        var mask: UInt32 = 0
        for page in pages where page.page < 32 {
            mask |= 1 << UInt32(page.page)
        }
        return mask
    }

    func completeTwoBeat(_ index: Int, today: Int) {
        guard index == twoCompleted + 1 else { return }
        twoCompleted = index
        twoLastBeatDay = today
        persist()
    }

    /// A correction staged but the beat not finished yet: the day still counts as used.
    func noteTwoBeatDay(_ today: Int) {
        twoLastBeatDay = today
        persist()
    }

    func addPlank(_ today: Int) {
        planks = min(planksMax, planks + 1)
        lastPlankDay = today
        persist()
    }

    func addPage(_ page: Int, backed: Bool, today: Int) {
        pages.append(PiboNotebookPage(page: page, backed: backed, day: today))
        persist()
    }

    func setFirstPageBacked(_ backed: Bool) {
        firstPageBacked = backed
        persist()
    }

    func finishSeasonTwo(_ today: Int) {
        guard twoDoneDay < 0 else { return }
        twoDoneDay = today
        persist()
    }

    func noteReread(_ today: Int) {
        lastRereadDay = today
        persist()
    }

    /// Debug dock only: rewind season two to just before `beat` (1–7), with season one done.
    func debugRewindTwo(beat: Int, today: Int) {
        if completedBeats < 7 { completedBeats = 7 }
        if seasonDoneDay < 0 { seasonDoneDay = today - 8 }
        if plantedDay < 0 { plantedDay = today - 12 }
        twoCompleted = max(0, beat - 1)
        twoLastBeatDay = -1
        planks = beat >= 3 ? planksMax : 0
        lastPlankDay = -1
        if beat <= 5 { pages = [] }
        if beat <= 6 { twoDoneDay = -1 }
        persist()
    }

    func debugSetPlanks(_ count: Int) {
        planks = max(0, min(planksMax, count))
        persist()
    }

    func resetTwo() {
        restoreTwo(nil)
        persist()
    }

    func reset() {
        restore("")
        persist()
    }

    // --- Persistence --------------------------------------------------------------------

    private func int(_ value: Any?, _ fallback: Int) -> Int {
        guard let number = value as? NSNumber else { return fallback }
        return number.intValue
    }

    private func persist() {
        revision += 1
        let snapshot: [String: Any] = [
            "completedBeats": completedBeats,
            "lastBeatDay": lastBeatDay,
            "plantedDay": plantedDay,
            "boAtPlanting": boAtPlanting,
            "seasonDoneDay": seasonDoneDay,
            "lastLetterDay": lastLetterDay,
            "lettersReceived": lettersReceived,
            "letters": letters.map { ["index": $0.index, "day": $0.day, "read": $0.read] },
            "report": report,
            "two": [
                "completedBeats": twoCompleted,
                "lastBeatDay": twoLastBeatDay,
                "planks": planks,
                "lastPlankDay": lastPlankDay,
                "pages": pages.map { ["page": $0.page, "backed": $0.backed, "day": $0.day] },
                "doneDay": twoDoneDay,
                "lastRereadDay": lastRereadDay,
                "firstPageBacked": firstPageBacked,
            ],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: snapshot),
           let raw = String(data: data, encoding: .utf8) {
            defaults.set(raw, forKey: persistenceKey)
        }
    }
}
