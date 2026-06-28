import Foundation

/// Shared JSON coders for the backend layer. They mirror the Go server's wire
/// conventions exactly:
///   - snake_case keys  ⇄  Swift camelCase (no hand-written CodingKeys needed)
///   - RFC3339 timestamps, lenient on fractional seconds (Go marshals time.Time
///     as RFC3339Nano, which includes fractional seconds when present).
enum JSONCoding {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = isoFractional.date(from: raw) ?? isoPlain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "unrecognized RFC3339 date: \(raw)")
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFractional.string(from: date))
        }
        return e
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
