import Foundation

/// 早 / 中 / 晚 — the three meal slots offered after choosing “记录卡路里” in the
/// camera. A meal capture is sent to the backend for 卡路里/营养 recognition;
/// Every release camera record selects one of these meals before capture.
enum MealType: String, CaseIterable, Codable, Identifiable, Sendable {
    case breakfast
    case lunch
    case dinner

    var id: String { rawValue }

    /// Compact camera-choice glyph — 早 / 中 / 晚.
    var shortLabel: String {
        switch self {
        case .breakfast: return "早"
        case .lunch:     return "中"
        case .dinner:    return "晚"
        }
    }

    /// Full name used in the modal title and sent to the server as context.
    var title: String {
        switch self {
        case .breakfast: return "早餐"
        case .lunch:     return "午餐"
        case .dinner:    return "晚餐"
        }
    }

    /// SF Symbol shown in the camera meal choice.
    var symbol: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch:     return "sun.max.fill"
        case .dinner:    return "moon.stars.fill"
        }
    }
}
