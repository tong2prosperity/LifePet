import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class OrnamentUnlockFlowCoordinator {
    enum Phase: Equatable {
        case hidden
        case presenting(PiboOrnament.ID)
        case browsing(PiboOrnament.ID)
        case placementPreview(PiboOrnament.ID)
        case holding(PiboOrnament.ID)
        case committing(PiboOrnament.ID)
        case materializing(PiboOrnament.ID)
        case success(PiboOrnament.ID)
        case returning(PiboOrnament.ID)
        case dismissing
    }

    private(set) var phase: Phase = .hidden
    private(set) var holdProgress: CGFloat = 0
    private(set) var travelProgress: CGFloat = 0
    private(set) var travelSource: CGRect = .zero
    private(set) var travelTarget: CGRect = .zero
    var message: String?

    @ObservationIgnored private var holdTask: Task<Void, Never>?
    @ObservationIgnored private var sequenceTask: Task<Void, Never>?
    @ObservationIgnored private let holdDuration: Duration

    init(holdDuration: Duration = .milliseconds(650)) {
        self.holdDuration = holdDuration
    }

    var selectedID: PiboOrnament.ID? {
        switch phase {
        case .presenting(let id), .browsing(let id), .placementPreview(let id),
             .holding(let id), .committing(let id), .materializing(let id),
             .success(let id), .returning(let id):
            id
        case .hidden, .dismissing:
            nil
        }
    }

    var isBusy: Bool {
        switch phase {
        case .holding, .committing, .materializing, .success, .returning, .dismissing:
            true
        default:
            false
        }
    }

    /// The active hold must remain visually and semantically enabled after its
    /// first touch. Other controls stay locked while that hold is in progress.
    func canContinueHold(_ id: PiboOrnament.ID) -> Bool {
        phase == .browsing(id) || phase == .holding(id)
    }

    var previewedID: PiboOrnament.ID? {
        guard case .placementPreview(let id) = phase else { return nil }
        return id
    }

    var returningID: PiboOrnament.ID? {
        guard case .returning(let id) = phase else { return nil }
        return id
    }

    func present(selected id: PiboOrnament.ID, reduceMotion: Bool) {
        cancelTasks()
        message = nil
        phase = .presenting(id)
        if reduceMotion {
            phase = .browsing(id)
        } else {
            sequenceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, let self, self.phase == .presenting(id) else { return }
                self.phase = .browsing(id)
            }
        }
    }

    func select(_ id: PiboOrnament.ID) {
        guard !isBusy else { return }
        message = nil
        phase = .browsing(id)
    }

    func beginPlacementPreview(_ id: PiboOrnament.ID) {
        guard !isBusy, selectedID == id else { return }
        message = nil
        phase = .placementPreview(id)
    }

    func endPlacementPreview() {
        guard case .placementPreview(let id) = phase else { return }
        phase = .browsing(id)
    }

    func beginHold(
        _ id: PiboOrnament.ID,
        reduceMotion: Bool,
        completion: @escaping @MainActor () -> Void
    ) {
        guard !isBusy, selectedID == id else { return }
        cancelHold()
        message = nil
        phase = .holding(id)
        holdProgress = 0
        LPHaptics.tap()

        if reduceMotion {
            completion()
            return
        }

        withAnimation(.linear(duration: 0.65)) {
            holdProgress = 1
        }
        holdTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: holdDuration)
            guard !Task.isCancelled, let self, self.phase == .holding(id) else { return }
            completion()
        }
    }

    func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        guard case .holding(let id) = phase else {
            holdProgress = 0
            return
        }
        withAnimation(.easeOut(duration: 0.12)) {
            holdProgress = 0
        }
        phase = .browsing(id)
    }

    func beginCommit(_ id: PiboOrnament.ID) -> Bool {
        guard phase == .holding(id) || phase == .browsing(id) else { return false }
        holdTask?.cancel()
        holdTask = nil
        holdProgress = 1
        phase = .committing(id)
        return true
    }

    func beginMaterializing(_ id: PiboOrnament.ID) {
        guard phase == .committing(id) else { return }
        phase = .materializing(id)
    }

    func completeMaterialization(_ id: PiboOrnament.ID) {
        guard phase == .materializing(id) || phase == .committing(id) else { return }
        holdProgress = 0
        phase = .success(id)
    }

    func showFailure(_ text: String, item id: PiboOrnament.ID) {
        cancelHold()
        message = text
        phase = .browsing(id)
    }

    func beginReturn(
        _ id: PiboOrnament.ID,
        source: CGRect,
        target: CGRect,
        reduceMotion: Bool,
        completion: @escaping @MainActor () -> Void
    ) {
        guard phase == .success(id) else { return }
        message = nil
        travelSource = source
        travelTarget = target
        travelProgress = reduceMotion ? 1 : 0
        phase = .returning(id)

        if reduceMotion {
            completion()
            return
        }
        withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: 0.42)) {
            travelProgress = 1
        }
        sequenceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            completion()
        }
    }

    func beginDismiss(reduceMotion: Bool, completion: @escaping @MainActor () -> Void) {
        guard !isBusy else { return }
        cancelTasks()
        phase = .dismissing
        if reduceMotion {
            completion()
            return
        }
        sequenceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            completion()
        }
    }

    /// Returns an item whose committed visual sequence must be completed
    /// immediately before the app is suspended.
    func prepareForBackground() -> PiboOrnament.ID? {
        switch phase {
        case .placementPreview(let id), .holding(let id):
            cancelTasks()
            holdProgress = 0
            phase = .browsing(id)
            return nil
        case .committing(let id), .materializing(let id), .returning(let id):
            cancelTasks()
            holdProgress = 0
            travelProgress = 1
            phase = .success(id)
            return id
        default:
            return nil
        }
    }

    func finishDismissal() {
        cancelTasks()
        holdProgress = 0
        travelProgress = 0
        phase = .hidden
    }

    /// A parent transition can remove the overlay without going through its
    /// authored dismissal path. Do not leave delayed callbacks retaining that
    /// presentation after the view has gone away.
    func dispose() {
        cancelTasks()
    }

    private func cancelTasks() {
        holdTask?.cancel()
        holdTask = nil
        sequenceTask?.cancel()
        sequenceTask = nil
    }
}
