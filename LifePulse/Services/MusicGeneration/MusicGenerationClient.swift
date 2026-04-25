import Foundation

protocol MusicGenerationClient: Sendable {
    func generate(_ request: MusicGenerationRequest) async throws -> GeneratedTrack
}

actor HTTPMusicGenerationClient: MusicGenerationClient {
    private let baseURL: URL
    private let apiKey: String
    private let urlSession: URLSession

    init(baseURL: URL, apiKey: String, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    func generate(_ request: MusicGenerationRequest) async throws -> GeneratedTrack {
        // TODO: POST request, poll or stream until done, download bytes to Application Support.
        throw NSError(domain: "MusicGeneration", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
}
