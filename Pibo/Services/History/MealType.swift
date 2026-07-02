import Foundation

/// 早 / 中 / 晚 — the three meal slots the home-screen icons capture into.
/// A photo captured through one of these icons is sent to the backend Kimi VLM
/// for 卡路里/营养 recognition (see `FoodRecognitionService`); a free 拍照 through
/// the 照相馆 has no meal and skips recognition.
enum MealType: String, CaseIterable, Codable, Identifiable, Sendable {
    case breakfast
    case lunch
    case dinner

    var id: String { rawValue }

    /// Compact chip glyph — 早 / 中 / 晚.
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

    /// SF Symbol shown in the home icon.
    var symbol: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch:     return "sun.max.fill"
        case .dinner:    return "moon.stars.fill"
        }
    }
}
