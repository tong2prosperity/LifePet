/// Owns the shared Analytics and presentation-state mutations for Home's camera
/// entry points. Callers retain their existing availability policy.
@MainActor
enum HomeCameraPresentationCoordinator {
    struct Handlers {
        let trackOpen: (MealType?) -> Void
        let setInitialMeal: (MealType?) -> Void
        let presentCamera: () -> Void
    }

    static func open(
        meal: MealType?,
        presentation: HomePresentationState
    ) {
        open(
            meal: meal,
            handlers: Handlers(
                trackOpen: { meal in
                    Analytics.track(
                        .cameraOpen,
                        screen: "home",
                        ["meal": .string(meal?.rawValue ?? "none")]
                    )
                },
                setInitialMeal: { presentation.cameraInitialMeal = $0 },
                presentCamera: { presentation.showCamera = true }
            )
        )
    }

    static func openIfEnabled(
        meal: MealType,
        isEnabled: Bool,
        presentation: HomePresentationState
    ) {
        guard isEnabled else { return }
        open(meal: meal, presentation: presentation)
    }

    static func open(meal: MealType?, handlers: Handlers) {
        handlers.trackOpen(meal)
        handlers.setInitialMeal(meal)
        handlers.presentCamera()
    }

    static func openIfEnabled(
        meal: MealType,
        isEnabled: Bool,
        handlers: Handlers
    ) {
        guard isEnabled else { return }
        open(meal: meal, handlers: handlers)
    }
}
