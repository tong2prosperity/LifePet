import Foundation
import Observation

/// Decision 047: viewing the status observer is transient. Tapping the forest
/// instrument opens a floating panel over the running forest; closing it,
/// leaving Home or backgrounding ends the view. Nothing is persisted and the
/// legacy per-Pibo pin (`wellnessObserverPinnedPetIDs`) is never read again,
/// so launching Home can never reopen private health information by itself.
@MainActor
@Observable
final class StatusObserverPresentationStore {
    private(set) var isOpen = false
    private(set) var expanded = false
    /// DEBUG sample panel: labeled as sample data and never touches real
    /// health, Core scoring, rewards or ownership.
    private(set) var usesSample = false

    func open(sample: Bool = false) {
        #if DEBUG
        usesSample = sample
        #else
        usesSample = false
        #endif
        expanded = false
        isOpen = true
    }

    func close() {
        isOpen = false
        expanded = false
        usesSample = false
    }

    func setExpanded(_ expanded: Bool) {
        self.expanded = expanded
    }
}
