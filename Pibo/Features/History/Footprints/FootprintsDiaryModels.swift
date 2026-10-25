import Foundation

// The footprints diary (决定 063): one page per local day, with what Pibo wrote that day on
// top and your own records below. Pure bookkeeping over facts already recorded elsewhere:
// nothing here scores, ranks or judges a day.
//
// Ported from HarmonyPibo `models/FootprintsDiaryModels.ets`.

enum FootprintsDiaryKind: Int {
    case readout = 0
    case first = 1
    case beat = 2
    case walk = 3
    case meal = 4
    case polaroid = 5
}

/// A shared first as recorded. `kind` is the raw value of Pibo's first kinds (决定 056).
struct FootprintsFirstFact {
    var kind = 0
    var at: Double = 0
}

/// A beat as it was told.
struct FootprintsBeatFact {
    var key = ""
    var at: Double = 0
    var lines: [String] = []
}

/// A walk diary entry with its names already worded by the day presentation.
struct FootprintsWalkFact {
    var at: Double = 0
    var destination = ""
    var find = ""
    var steps = 0
    var item = -1
}

struct FootprintsMealFact {
    var id = ""
    var at: Double = 0
    var mealTypeRaw = ""
    /// The cut-out PNG, if the row still has one.
    var pngData: Data?
    /// The dish as the backend named it; '' when unnamed.
    var name = ""
    /// Shown when there is no sticker (legacy and debug rows).
    var glyph = "🍽️"
    /// The specimen number; 0 when the meal is not (or no longer) food.
    var sample = 0
}

struct FootprintsPolaroidFact {
    var at: Double = 0
    var path = ""
    var caption = ""
    /// The print's file as it can be opened now (the stored path may be stale).
    var filePath = ""
}

/// Everything recorded for one day, unfiltered: the builder keeps only what falls on it.
struct FootprintsDayFacts {
    /// The readout's conclusion for that day; '' when no current-algorithm snapshot exists.
    var readout = ""
    var firsts: [FootprintsFirstFact] = []
    var beats: [FootprintsBeatFact] = []
    var walks: [FootprintsWalkFact] = []
    var meals: [FootprintsMealFact] = []
    var polaroids: [FootprintsPolaroidFact] = []
}

struct FootprintsDiaryItem: Identifiable {
    var kind: FootprintsDiaryKind = .readout
    /// Stable per page: kind plus what it points at.
    var id = ""
    var at: Double = 0
    /// Pibo's line, never with a number in it; for a walk, the destination's name; for a
    /// meal, its sticker.
    var line = ""
    /// For a walk, the find's name (the view words both); for a meal, the dish; else ''.
    var note = ""
    var steps = 0
    /// The meal id or polaroid path a tap opens; '' when the item does not open.
    var ref = ""
    var mealTypeRaw = ""
    var sample = 0
    var item = -1
    var glyph = ""
    /// The cut-out sticker of a meal, when the row has one.
    var pngData: Data?
    /// A polaroid's print, resolved to a file that opens now.
    var imagePath = ""
}

enum FootprintsDayMark: Int {
    case none = 0
    /// Something was recorded that day.
    case dot = 1
    /// A shared first happened that day.
    case star = 2
}

struct FootprintsCalendarCell: Identifiable {
    /// Local midnight; `nil` for a padding cell before the first of the month.
    var day: Date?
    var date = 0
    var mark: FootprintsDayMark = .none
    var meeting = false
    var today = false
    /// Inside the relationship: from the meeting day to today.
    var enabled = false

    var id: String { day.map { "\($0.timeIntervalSince1970)" } ?? "pad-\(date)" }
}

let FOOTPRINTS_EMPTY_LINE = "这一天 Pibo 没写什么，安安静静过去了。"

func footprintsDayStart(_ value: Double) -> Date {
    Calendar.current.startOfDay(for: Date(timeIntervalSince1970: value))
}

func footprintsAddDays(_ day: Date, _ delta: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: delta,
                          to: Calendar.current.startOfDay(for: day)) ?? day
}

/// A stable day ordinal in UTC, so a day is one number regardless of DST.
private func dayOrdinal(_ day: Date) -> Int {
    let localParts = Calendar.current.dateComponents([.year, .month, .day], from: day)
    var utcCalendar = Calendar(identifier: .gregorian)
    utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    let stamp = utcCalendar.date(from: localParts) ?? day
    return Int((stamp.timeIntervalSince1970 / 86_400).rounded())
}

/// 地球第 N 天 of a date: the meeting day is day 1, as `PetStateStore.dayCount` counts.
func footprintsDayNumber(_ day: Date, meetingDay: Date) -> Int {
    max(1, dayOrdinal(day) - dayOrdinal(meetingDay) + 1)
}

/// Pages stop at the meeting day and at today.
func footprintsClampDay(_ day: Date, meetingDay: Date, today: Date) -> Date {
    let value = Calendar.current.startOfDay(for: day)
    let first = Calendar.current.startOfDay(for: min(meetingDay, today))
    let last = Calendar.current.startOfDay(for: today)
    return min(last, max(first, value))
}

func footprintsCanShift(_ day: Date, _ delta: Int, meetingDay: Date, today: Date) -> Bool {
    let next = footprintsAddDays(day, delta)
    return footprintsClampDay(next, meetingDay: meetingDay, today: today) == next
}

/// What the first of each kind is called on its day, in Pibo's words.
func footprintsFirstLine(_ kind: Int) -> String {
    switch kind {
    case 0: "你第一次拍我。"
    case 1: "你帮我收了第一枚 bo。"
    case 2: "你第一次看我睡在吊床上。"
    case 3: "你第一次给我看吃的。"
    default: ""
    }
}

func footprintsKindTitle(_ kind: FootprintsDiaryKind) -> String {
    switch kind {
    case .readout: "读数徽章"
    case .first: "共同的第一次"
    case .beat: "我说过的小事"
    case .walk: "散步日记"
    case .meal: "地球食物样本"
    case .polaroid: "森林拍立得"
    }
}

private func onDay(_ at: Double, _ day: Date) -> Bool {
    guard at.isFinite, at > 0 else { return false }
    return footprintsDayStart(at) == Calendar.current.startOfDay(for: day)
}

private func makeItem(_ kind: FootprintsDiaryKind, _ key: String, _ at: Double,
                      _ line: String) -> FootprintsDiaryItem {
    FootprintsDiaryItem(kind: kind, id: "\(kind.rawValue):\(key)", at: at, line: line)
}

/// What Pibo wrote on `day`, in a fixed order: the readout, firsts, beats, walks, samples,
/// the polaroid; by time within each. Only what really happened that day is listed.
func footprintsDiaryItems(day: Date, facts: FootprintsDayFacts) -> [FootprintsDiaryItem] {
    var items: [FootprintsDiaryItem] = []
    if !facts.readout.isEmpty {
        let at = Calendar.current.startOfDay(for: day).timeIntervalSince1970
        items.append(makeItem(.readout, "readout", at, facts.readout))
    }
    for first in facts.firsts
    .filter({ onDay($0.at, day) && !footprintsFirstLine($0.kind).isEmpty })
    .sorted(by: { $0.at < $1.at }) {
        items.append(makeItem(.first, "\(first.kind)", first.at, footprintsFirstLine(first.kind)))
    }
    for beat in facts.beats
    .filter({ onDay($0.at, day) && !$0.lines.isEmpty })
    .sorted(by: { $0.at < $1.at }) {
        items.append(makeItem(.beat, beat.key, beat.at, beat.lines.joined()))
    }
    for walk in facts.walks.filter({ onDay($0.at, day) }).sorted(by: { $0.at < $1.at }) {
        var entry = makeItem(.walk, "\(walk.at)", walk.at, walk.destination)
        entry.note = walk.find
        entry.steps = walk.steps
        entry.item = walk.item
        items.append(entry)
    }
    for meal in facts.meals
    .filter({ onDay($0.at, day) && $0.sample > 0 })
    .sorted(by: { $0.at < $1.at }) {
        var entry = makeItem(.meal, meal.id, meal.at, "")
        entry.ref = meal.id
        entry.note = meal.name
        entry.glyph = meal.glyph
        entry.mealTypeRaw = meal.mealTypeRaw
        entry.sample = meal.sample
        entry.pngData = meal.pngData
        items.append(entry)
    }
    for shot in facts.polaroids.filter({ onDay($0.at, day) }).sorted(by: { $0.at < $1.at }).prefix(1) {
        var entry = makeItem(.polaroid, shot.path, shot.at, shot.caption)
        entry.ref = shot.path
        entry.imagePath = shot.filePath
        items.append(entry)
    }
    return items
}

/// One month as a Monday-first grid. A mark only says that a day has something, never how
/// good it was; days outside the relationship are greyed and cannot be opened.
func footprintsCalendar(year: Int, month: Int, recordedDays: [Date], firstDays: [Date],
                         meetingDay: Date, today: Date) -> [FootprintsCalendarCell] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2
    var cells: [FootprintsCalendarCell] = []
    guard let first = calendar.date(from: DateComponents(year: year, month: month + 1, day: 1)) else {
        return cells
    }
    // Monday-first lead: Sunday (weekday 1) needs six blanks, Monday none.
    let weekday = calendar.component(.weekday, from: first)
    let lead = (weekday + 5) % 7
    for _ in 0..<lead {
        cells.append(FootprintsCalendarCell(day: nil, date: 0))
    }
    let startOf = { (value: Date) in Calendar.current.startOfDay(for: value) }
    let recorded = Set(recordedDays.map(startOf))
    let firsts = Set(firstDays.map(startOf))
    let meeting = startOf(meetingDay)
    let last = startOf(today)
    let length = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
    for date in 1...max(1, length) {
        guard let day = calendar.date(from: DateComponents(year: year, month: month + 1, day: date))
        else { continue }
        let key = startOf(day)
        let mark: FootprintsDayMark = firsts.contains(key)
            ? .star : (recorded.contains(key) ? .dot : .none)
        cells.append(FootprintsCalendarCell(
            day: key,
            date: date,
            mark: mark,
            meeting: key == meeting,
            today: key == last,
            enabled: key >= min(meeting, last) && key <= last
        ))
    }
    return cells
}
