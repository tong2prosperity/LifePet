import Foundation
import PiboCore

@MainActor
struct HomePatInputProvider {
    let store: PetStateStore
    let history: HealthHistoryStore
    let animationPresentation: HomeAnimationPresentationController
    let healthAvailability: HealthDataService.DataAvailability
    let storyStage: PiboCoreStorySpeechStage

    func input() -> PiboPatConversationInput {
        let state = animationPresentation.state
        return PiboPatConversationInput(
            state: state,
            episodeKey: animationPresentation.patEpisodeKey,
            stableThinking: false,
            ambientEvent: ambientEvent(for: state),
            dataUnknownReason: dataUnknownReason,
            storyStage: storyStageKey,
            values: baseValues,
            events: eventCandidates(for: state)
        )
    }

    private var storyStageKey: String {
        switch storyStage {
        case .event01Completed: "event01"
        case .event02Completed: "event02"
        case .event03Completed: "event03"
        default: "unresponded"
        }
    }

    private var dataUnknownReason: PiboCorePatDataUnknownReason {
        switch healthAvailability {
        case .unavailable: .unavailable
        case .needsAuthorization: .authorization
        case .temporarilyInterrupted(let lastReadableAt):
            lastReadableAt == nil ? .interruptedNoTrustedState : .waitingData
        case .checking, .noReadableData, .available: .waitingData
        }
    }

    private var baseValues: [String: String] {
        var values: [String: String] = [:]
        if store.hasStepsData { values["steps"] = String(store.rawSteps) }
        if store.rawSleepHours > 0 {
            values["sleepDuration"] = String(
                format: "%.1f %@",
                store.rawSleepHours,
                AppLocalization.text("小时")
            )
        }
        return values
    }

    private func ambientEvent(for state: PiboActivityState) -> PiboCorePatEvent {
        if state == .waking,
           animationPresentation.decision?.pendingCause == .insufficientSleep {
            return .insufficientSleep
        }
        return .none
    }

    private func eventCandidates(for state: PiboActivityState) -> [PiboPatEventCandidate] {
        switch state {
        case .stable:
            var candidates: [PiboPatEventCandidate] = []
            if let sleepEvent { candidates.append(sleepEvent) }
            if store.hasStepsData, store.rawSteps > 0 {
                candidates.append(PiboPatEventCandidate(
                    event: .steps,
                    token: "steps:\(dayToken(.now))",
                    values: ["steps": String(store.rawSteps)]
                ))
            }
            return candidates
        case .energetic:
            return energeticEvent.map { [$0] } ?? []
        case .tired:
            guard animationPresentation.decision?.cause == .insufficientSleep else { return [] }
            return [PiboPatEventCandidate(
                event: .insufficientSleep,
                token: "insufficientSleep:\(animationPresentation.patEpisodeKey)"
            )]
        default:
            return []
        }
    }

    private var sleepEvent: PiboPatEventCandidate? {
        guard store.rawSleepHours > 0 else { return nil }
        let start = store.rawSleepStart
        let wake = animationPresentation.wakeStartedAt
        let end = start?.addingTimeInterval(store.rawSleepHours * 3_600)
        let sleptTogether = if let start, let end, let wake {
            wake >= start && wake <= end
        } else {
            false
        }
        return PiboPatEventCandidate(
            event: sleptTogether ? .sleepTogether : .sleep,
            token: "sleep:\(start?.timeIntervalSince1970 ?? dayToken(.now))",
            values: baseValues
        )
    }

    private var energeticEvent: PiboPatEventCandidate? {
        guard let decision = animationPresentation.decision else { return nil }
        switch decision.cause {
        case .recentWorkout:
            let workout = history.workouts(on: .now).max(by: { $0.end < $1.end })
            let endedAt = store.lastWorkoutEndedAt ?? workout?.end ?? .now
            return PiboPatEventCandidate(
                event: workoutEvent(workout?.kind ?? .other),
                token: "workout:\(endedAt.timeIntervalSince1970):\(workout?.kindRaw ?? "other")"
            )
        case .activityMilestone:
            return PiboPatEventCandidate(
                event: .activityMilestone,
                token: "activityMilestone:\(animationPresentation.patEpisodeKey)"
            )
        case .goodSleep:
            return PiboPatEventCandidate(
                event: .goodSleep,
                token: "goodSleep:\(animationPresentation.patEpisodeKey)"
            )
        default:
            return nil
        }
    }

    private func workoutEvent(_ kind: HealthEvent.WorkoutKind) -> PiboCorePatEvent {
        switch kind {
        case .run: .workoutRun
        case .walk: .workoutWalk
        case .cycle: .workoutCycle
        case .swim: .workoutSwim
        case .hiit: .workoutHiit
        case .yoga: .workoutYoga
        case .other: .workoutOther
        }
    }

    private func dayToken(_ date: Date) -> TimeInterval {
        Calendar.current.startOfDay(for: date).timeIntervalSince1970
    }
}
