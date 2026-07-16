import Foundation
import PiboCore

enum PiboCoreGreetingAdapter {
    enum Band {
        case dawn
        case morning
        case midday
        case afternoon
        case dusk
        case evening
        case lateNight
    }

    static func band(at date: Date) -> Band {
        let hour = Calendar.current.component(.hour, from: date)
        switch PiboCoreGreeting.band(localHour: Double(hour)) {
        case .dawn: return Band.dawn
        case .morning: return Band.morning
        case .midday: return Band.midday
        case .afternoon: return Band.afternoon
        case .dusk: return Band.dusk
        case .evening: return Band.evening
        case .lateNight: return Band.lateNight
        }
    }

    static func lineIndex(at date: Date, lineCount: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return PiboCoreGreeting.lineIndex(
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0,
            lineCount: lineCount
        )
    }

    static func usesOwnerName(dayCount: Int, hasOwnerName: Bool) -> Bool {
        PiboCoreGreeting.usesOwnerName(
            relationshipDayCount: dayCount,
            hasOwnerName: hasOwnerName
        )
    }
}
