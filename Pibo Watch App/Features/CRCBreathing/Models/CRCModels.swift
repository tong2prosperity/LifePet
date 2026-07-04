import Foundation

nonisolated enum CRCConstants {
    static let targetHeartBreathRatio: Double = 8.0
    static let initialGuidedBreathingRate: Double = 6.0
    static let minGuidedBreathingRate: Double = 4.0
    static let maxGuidedBreathingRate: Double = 8.0
    static let minimumMeasuredBreathingRate: Double = 4.0
    static let maximumMeasuredBreathingRate: Double = 24.0
    static let baselineDuration: TimeInterval = 30
    static let recommendedTrainingDuration: TimeInterval = 5 * 60
    static let motionSampleRate: Double = 30
    static let couplingTickInterval: TimeInterval = 1
    static let inhaleRatio: Double = 0.45
    static let exhaleRatio: Double = 0.55
}

enum CRCFlowStep {
    case intro
    case baseline
    case coreTraining
    case report
    case error
}

/// Lightweight state layered on top of `coreTraining` as an overlay (not a flow step).
/// `menu` merges the old paused + endConfirm into one exit sheet.
enum CRCTransientState {
    case none
    case menu
    case unstable
}

enum CRCBreathingPhase: String, Codable, Sendable {
    case inhale
    case exhale

    var label: String {
        switch self {
        case .inhale: return "吸气"
        case .exhale: return "呼气"
        }
    }

    var nextLabel: String {
        switch self {
        case .inhale: return "呼气"
        case .exhale: return "吸气"
        }
    }
}

struct CRCBreathReading: Sendable {
    var breathsPerMinute: Double
    var phaseProgress: Double
    var amplitude: Double
    var amplitudeScore: Double
    var signalQuality: Double
    var selectedChannel: String
    var timestamp: Date
}

struct CRCPoseAssessment: Sendable {
    var poseConfidence: Double
    var orientationConfidence: Double
    var stillnessConfidence: Double
    var breathingSignalQuality: Double
    var isLikelyPlaced: Bool
    var guidance: String
}

struct CRCHeartReading: Sendable {
    var bpm: Double
    var confidence: Double
    var timestamp: Date
}

struct CRCSnapshot: Sendable {
    var timestamp: Date
    var heartRate: Double
    var measuredBreathingRate: Double
    var guidedBreathingRate: Double
    var previousGuidedBreathingRate: Double
    var heartBreathRatio: Double
    var couplingIndex: Double
    var syncScore: Double
    var phase: CRCBreathingPhase
    var phaseProgress: Double
    var pose: CRCPoseAssessment
    var breathSignalQuality: Double
    var amplitudeScore: Double
    var followQuality: Double
}

struct CRCTrainingReport: Sendable {
    var couplingIndex: Int
    var averageHeartRate: Int
    var averageBreathingRate: Double
    var syncStability: Double
    var duration: TimeInterval
    var recommendation: String
    /// Warm, tsundere Pibo close-out shown in place of a clinical score.
    var piboLine: String
    /// Authoritative post-session RMSSD (ms) from the recorded heartbeat series —
    /// `nil` when the watch captured no usable series this session.
    var sessionRMSSD: Double?
    /// Session-average of the live RSA/HRV estimate (ms) — the honest fallback
    /// shown when `sessionRMSSD` is nil (or alongside it as the live read).
    var liveHRVAverage: Double?
}

extension Double {
    nonisolated var crcClampedUnit: Double {
        min(1, max(0, self))
    }
}
