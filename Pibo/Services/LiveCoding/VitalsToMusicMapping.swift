import Foundation

nonisolated struct MusicParameters: Codable, Sendable, Hashable {
    var bpm: Double
    var rootMidi: Int
    var brightness: Double      // 0...1 — feeds low-pass cutoff
    var density: Double         // 0...1 — note density per bar
}

nonisolated enum VitalsToMusicMapping {
    /// Map a snapshot of vitals onto a musical parameter set.
    /// HR sets BPM; HRV biases density/brightness; SpO₂ biases brightness.
    static func parameters(from snapshot: VitalSnapshot) -> MusicParameters {
        let hr = snapshot.first(of: .heartRate)?.value ?? 70
        let hrv = snapshot.first(of: .hrv)?.value ?? 40
        let spo2 = snapshot.first(of: .spo2)?.value ?? 98

        let bpm = clamp(hr, 50, 160)
        let brightness = clamp((spo2 - 90) / 10, 0, 1)
        let density = clamp(hrv / 80, 0, 1)

        return MusicParameters(
            bpm: bpm,
            rootMidi: 60,
            brightness: brightness,
            density: density
        )
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }
}
