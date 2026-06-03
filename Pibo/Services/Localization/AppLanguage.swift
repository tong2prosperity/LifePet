import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var locale: Locale { Locale(identifier: rawValue) }

    var title: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    var shortTitle: String {
        switch self {
        case .chinese: return "中"
        case .english: return "EN"
        }
    }

    static var preferred: AppLanguage {
        for identifier in Locale.preferredLanguages {
            if let language = AppLanguage(rawValue: identifier) {
                return language
            }

            if identifier.hasPrefix("zh") {
                return .chinese
            }

            if identifier.hasPrefix("en") {
                return .english
            }
        }

        return .chinese
    }

    static var current: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: PiboPersistenceKeys.Defaults.appLanguage)
        return AppLanguage(rawValue: raw ?? "") ?? .preferred
    }
}

enum AppLocalization {
    static func text(_ key: String) -> String {
        String(
            localized: String.LocalizationValue(key),
            table: "Localizable",
            bundle: .main,
            locale: AppLanguage.current.locale
        )
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: text(key), locale: AppLanguage.current.locale, arguments: args)
    }
}

extension Text {
    init(lp key: String) {
        self.init(LocalizedStringKey(key))
    }
}
