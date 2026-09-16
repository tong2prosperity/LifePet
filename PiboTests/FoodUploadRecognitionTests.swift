import Foundation
import Testing
import UIKit
@testable import Pibo

/// Captures every request the food client makes and answers from a script.
final class FoodUploadMockProtocol: URLProtocol, @unchecked Sendable {
    struct Recorded: Sendable {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data
    }

    nonisolated(unsafe) static var recorded: [Recorded] = []
    nonisolated(unsafe) static var responder: (URLRequest) -> (Int, Data) = { _ in (500, Data()) }
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 16_384)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            stream.close()
        }
        Self.lock.lock()
        Self.recorded.append(Recorded(
            method: request.httpMethod ?? "",
            url: request.url!,
            headers: request.allHTTPHeaderFields ?? [:],
            body: body
        ))
        let (status, data) = Self.responder(request)
        Self.lock.unlock()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
@MainActor
struct FoodUploadRecognitionTests {
    private static let uploadURL = "https://cos.example.com/pibo/food-input/v1/users/u/x.jpg?sign=abc"
    private static let sessionID = "tok.en/with+chars"

    private func makeService(
        makeJPEG: @escaping @Sendable (UIImage) -> Data? = { _ in Data(repeating: 0xFF, count: 2048) }
    ) -> (FoodRecognitionService, TokenStore) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FoodUploadMockProtocol.self]
        let tokens = TokenStore(service: "PiboTests.food.\(UUID().uuidString)")
        tokens.save(access: "access", refresh: "refresh", userId: "u")
        let api = APIClient(
            config: APIConfig(baseURL: URL(string: "https://test-api.example.com/pibo/v1")!),
            tokens: tokens,
            session: URLSession(configuration: configuration)
        )
        FoodUploadMockProtocol.recorded = []
        return (FoodRecognitionService(api: api, makeUploadJPEG: makeJPEG), tokens)
    }

    private static func happyResponder(putStatus: Int = 200) -> (URLRequest) -> (Int, Data) {
        { request in
            let path = request.url?.path ?? ""
            if request.url?.host == "cos.example.com" { return (putStatus, Data()) }
            if path.hasSuffix("/api/v1/food/uploads") {
                return (201, Data(#"""
                {"session_id":"\#(sessionID)","object_key":"pibo/food-input/v1/users/u/x.jpg",
                 "upload_url":"\#(uploadURL)",
                 "headers":{"Content-Type":"image/jpeg","x-cos-security_token":"t"},
                 "expires_at":"2026-09-16T10:00:00Z"}
                """#.utf8))
            }
            if path.hasSuffix("/complete") {
                return (200, Data(#"{"object_key":"pibo/food-input/v1/users/u/x.jpg"}"#.utf8))
            }
            if path.hasSuffix("/api/v1/food/recognize") {
                return (200, Data(#"""
                {"is_food":true,"dish_name":"番茄炒蛋","total_calories":320,"items":[]}
                """#.utf8))
            }
            return (404, Data())
        }
    }

    @Test func derivativeCapsLongestEdgeAt1280() {
        #expect(FoodUploadImage.targetPixelSize(width: 4032, height: 3024) == CGSize(width: 1280, height: 960))
        #expect(FoodUploadImage.targetPixelSize(width: 3024, height: 4032) == CGSize(width: 960, height: 1280))
        #expect(FoodUploadImage.targetPixelSize(width: 800, height: 600) == CGSize(width: 800, height: 600))
        #expect(FoodUploadImage.targetPixelSize(width: 1280, height: 20) == CGSize(width: 1280, height: 20))
        #expect(FoodUploadImage.targetPixelSize(width: 20_000, height: 1) == CGSize(width: 1280, height: 1))
        #expect(FoodUploadImage.jpegQuality == 0.72)
    }

    @Test func derivativeJPEGHasExactPixelSizeRegardlessOfImageScale() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        // 1344 x 1008 points @3x = 4032 x 3024 pixels.
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1344, height: 1008), format: format)
            .image { context in
                UIColor.orange.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1344, height: 1008))
            }
        let data = try #require(FoodUploadImage.jpegData(from: image))
        let decoded = try #require(UIImage(data: data)?.cgImage)
        #expect(decoded.width == 1280)
        #expect(decoded.height == 960)
    }

    @Test func recognizesThroughUploadSessionInOrder() async throws {
        FoodUploadMockProtocol.responder = Self.happyResponder()
        let (service, tokens) = makeService()
        defer { tokens.clear() }

        let outcome = await service.recognize(
            requestID: UUID(), fullImage: UIImage(), hint: "午饭", meal: .lunch
        )
        guard case .food(let analysis) = outcome else {
            Issue.record("expected food, got \(outcome)")
            return
        }
        #expect(analysis.dishName == "番茄炒蛋")

        let calls = FoodUploadMockProtocol.recorded
        try #require(calls.count == 4)
        #expect(calls[0].method == "POST")
        #expect(calls[0].url.absoluteString == "https://test-api.example.com/pibo/v1/api/v1/food/uploads")
        #expect(calls[0].headers["Authorization"] == "Bearer access")
        let create = try JSONSerialization.jsonObject(with: calls[0].body) as? [String: Any]
        #expect(create?["content_type"] as? String == "image/jpeg")
        #expect(create?["content_length"] as? Int == 2048)

        #expect(calls[1].method == "PUT")
        #expect(calls[1].url.absoluteString == Self.uploadURL)
        #expect(calls[1].headers["Authorization"] == nil)
        #expect(calls[1].headers["Content-Type"] == "image/jpeg")
        // Signed header names reach COS untouched by the snake_case strategy.
        #expect(calls[1].headers["x-cos-security_token"] == "t")
        #expect(calls[1].body.count == 2048)

        #expect(calls[2].method == "POST")
        #expect(calls[2].url.absoluteString.hasPrefix("https://test-api.example.com/pibo/v1/api/v1/food/uploads/"))
        #expect(calls[2].url.absoluteString.hasSuffix("/complete"))
        #expect(calls[2].url.absoluteString.contains("tok.en%2Fwith"))
        let complete = try JSONSerialization.jsonObject(with: calls[2].body) as? [String: Any]
        #expect(complete?["object_key"] as? String == "pibo/food-input/v1/users/u/x.jpg")

        #expect(calls[3].url.absoluteString == "https://test-api.example.com/pibo/v1/api/v1/food/recognize")
        let recognize = try #require(try JSONSerialization.jsonObject(with: calls[3].body) as? [String: Any])
        #expect(recognize["object_key"] as? String == "pibo/food-input/v1/users/u/x.jpg")
        #expect(recognize["upload_session_id"] as? String == Self.sessionID)
        #expect(recognize["mime_type"] as? String == "image/jpeg")
        #expect(recognize["image_base64"] == nil)
        #expect(recognize["hint"] as? String == "午饭")
    }

    @Test func derivativeFailureMakesNoRequest() async {
        FoodUploadMockProtocol.responder = Self.happyResponder()
        let (service, tokens) = makeService(makeJPEG: { _ in nil })
        defer { tokens.clear() }
        let outcome = await service.recognize(
            requestID: UUID(), fullImage: UIImage(), hint: nil, meal: .dinner
        )
        #expect(outcome == .failed)
        #expect(FoodUploadMockProtocol.recorded.isEmpty)
    }

    @Test func uploadFailureNeverReachesRecognize() async {
        FoodUploadMockProtocol.responder = Self.happyResponder(putStatus: 403)
        let (service, tokens) = makeService()
        defer { tokens.clear() }
        let outcome = await service.recognize(
            requestID: UUID(), fullImage: UIImage(), hint: nil, meal: .breakfast
        )
        #expect(outcome == .failed)
        let paths = FoodUploadMockProtocol.recorded.map(\.url.path)
        #expect(paths.count == 2)
        #expect(!paths.contains { $0.hasSuffix("/recognize") })
        #expect(!paths.contains { $0.hasSuffix("/complete") })
    }

    @Test func retryRegeneratesTheDerivativeFromTheKeptOriginal() async {
        FoodUploadMockProtocol.responder = Self.happyResponder()
        let counter = DerivativeCounter()
        let (service, tokens) = makeService(makeJPEG: { _ in
            counter.increment()
            return Data(repeating: 1, count: 10)
        })
        defer { tokens.clear() }
        _ = await service.recognize(requestID: UUID(), fullImage: UIImage(), hint: nil, meal: .lunch)
        _ = await service.recognize(requestID: UUID(), fullImage: UIImage(), hint: nil, meal: .lunch)
        #expect(counter.value == 2)
        #expect(FoodUploadMockProtocol.recorded.filter { $0.method == "PUT" }.count == 2)
    }
}

final class DerivativeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
