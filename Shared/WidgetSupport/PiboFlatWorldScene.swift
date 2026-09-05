import Foundation

nonisolated enum PiboFlatWorldScene: String, CaseIterable, Codable, Sendable {
    case nightClouds
    case dawnCreek
    case riverValley
    case rainGorge
    case coralDusk

    static let widgetCycle: [Self] = [.rainGorge, .nightClouds, .riverValley]

    static func recommended(
        petName: String,
        date: Date = .now,
        calendar: Calendar = .current,
        choices: [Self] = allCases
    ) -> Self {
        guard !choices.isEmpty else { return .riverValley }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let civil = utc.date(from: components) ?? date
        let ordinal = Int(floor(civil.timeIntervalSince1970 / 86_400))
        let offset = petName.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .unicodeScalars
            .reduce(0) { (value, scalar) in
                (value &* 31 &+ Int(scalar.value)) % 2_147_483_647
            }
        return choices[(ordinal + offset).modulo(choices.count)]
    }
}

private nonisolated extension Int {
    func modulo(_ divisor: Int) -> Int {
        let value = self % divisor
        return value >= 0 ? value : value + divisor
    }
}
