import Foundation

nonisolated struct MusicGenerationRequest: Codable, Sendable {
    let sessionID: UUID
    let prompt: String
    let parameters: MusicParameters
    let durationSeconds: Int

    /// Seed a request from the whole session's snapshots — caller picks how to summarize them.
    static func fromSession(_ session: VitalSession, summary: MusicParameters, prompt: String, duration: Int = 90) -> MusicGenerationRequest {
        MusicGenerationRequest(
            sessionID: session.id,
            prompt: prompt,
            parameters: summary,
            durationSeconds: duration
        )
    }
}
