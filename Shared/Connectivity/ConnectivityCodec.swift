import Foundation

nonisolated enum ConnectivityCodecError: Error {
    case missingPayload
}

nonisolated enum ConnectivityCodec {
    private static let payloadKey = "payload"

    static func encode(_ message: ConnectivityMessage) throws -> [String: Any] {
        let data = try makeEncoder().encode(message)
        return [payloadKey: data]
    }

    static func decode(_ dict: [String: Any]) throws -> ConnectivityMessage {
        guard let data = dict[payloadKey] as? Data else {
            throw ConnectivityCodecError.missingPayload
        }
        return try makeDecoder().decode(ConnectivityMessage.self, from: data)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
