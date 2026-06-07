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

enum CRCFlowStep: Int, CaseIterable, Identifiable {
    case welcome = 1
    case preparation
    case baseline
    case coreTraining
    case report
    case error

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "心呼耦合训练"
        case .preparation: return "准备就绪"
        case .baseline: return "今日节律建立"
        case .coreTraining: return "核心训练"
        case .report: return "训练完成"
        case .error: return "需要重新准备"
        }
    }
}

/// Lightweight states layered on top of `coreTraining` as overlays (not flow steps).
enum CRCTransientState {
    case none
    case paused
    case endConfirm
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
}

extension Double {
    nonisolated var crcClampedUnit: Double {
        min(1, max(0, self))
    }
}
