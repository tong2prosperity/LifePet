import Foundation

/// A draft compares with what was loaded, not a record that may be updated by recognition.
struct MealMetadataDraft {
    let photoID: UUID
    var name: String
    var meal: MealType
    private let originalName: String
    private let originalMeal: MealType

    init(photo: FoodPhoto, fallbackMeal: MealType) {
        photoID = photo.id
        name = photo.displayName
        meal = photo.meal ?? fallbackMeal
        originalName = name
        originalMeal = meal
    }

    var changed: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines) != originalName || meal != originalMeal
    }
}
