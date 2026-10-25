import Foundation

/// Controlled semantic values only; never user text, metrics or resource paths.
enum PiboAnalyticsKeys {
    static func scene(_ raw: Int) -> String {
        ["clearing", "creek", "hillside"].indices.contains(raw)
            ? ["clearing", "creek", "hillside"][raw] : "clearing"
    }

    static func form(_ raw: Int) -> String {
        let forms = ["none", "stone", "mushroom", "bike", "fish", "sapling", "spring", "pillow", "lamp", "bowl", "sneaker"]
        return forms.indices.contains(raw) ? forms[raw] : "none"
    }
}
