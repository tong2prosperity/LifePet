import Foundation
import PiboCore

/// The app-side seam for Core's single event-driven ambient-state lifecycle.
/// Calendar boundary construction and persistence are platform concerns;
/// thresholds, event ordering and transitions remain in `pibo-core`.
enum PiboCoreStateAdapter {
    struct Decision: Equatable {
        let state: PiboActivityState
        let cause: PiboCoreStateCause
        /// Sleep outcome held by Core while the visible state remains `waking`.
        /// Presentation can use it to select a waking behavior without
        /// reimplementing sleep thresholds in the App.
        let pendingState: PiboActivityState?
        let pendingCause: PiboCoreStateCause?
        let sleepStartMinute: Int
        let wakeMinute: Int
        let routineSource: PiboCoreRoutineSource
        let routineSampleCount: Int
        let routineRegularity: Int
        let routineShiftMinutes: Int
    }

    struct Resolution: Equatable {
        let decision: Decision
        let snapshot: PiboCoreStateSnapshot
    }

    private struct TimedEvent {
        let kind: PiboCoreStateEventKind
        let date: Date

        var sortOrder: Int {
            switch kind {
            case .scheduledWake: 0
            case .scheduledSleep: 1
            case .workoutCompleted: 2
            case .activityMilestone: 3
            default: 4
            }
        }
    }

    static func resolve(
        snapshot initialSnapshot: PiboCoreStateSnapshot,
        at date: Date,
        calendar: Calendar,
        hasActivityData: Bool,
        lastWorkoutEndedAt: Date?,
        activityMilestoneReachedAt: Date?,
        nights: [PiboCoreSleepWeeklyNight]
    ) -> Resolution {
        let routine = PiboCoreStatePolicy.routine(nights: nights)
        let sleepBoundary = mostRecentBoundary(
            minuteOfDay: routine.sleepStartMinute,
            at: date,
            calendar: calendar
        )
        let wakeBoundary = mostRecentBoundary(
            minuteOfDay: routine.wakeMinute,
            at: date,
            calendar: calendar
        )
        var events = [
            TimedEvent(kind: .scheduledSleep, date: sleepBoundary),
            TimedEvent(kind: .scheduledWake, date: wakeBoundary),
        ]
        if let lastWorkoutEndedAt,
           PiboCoreStatePolicy.workoutEventIsDiscoverable(
               ageSeconds: date.timeIntervalSince(lastWorkoutEndedAt)
           ) {
            events.append(TimedEvent(kind: .workoutCompleted, date: lastWorkoutEndedAt))
        }
        if let activityMilestoneReachedAt, date.timeIntervalSince(activityMilestoneReachedAt) >= 0 {
            events.append(TimedEvent(kind: .activityMilestone, date: activityMilestoneReachedAt))
        }
        events.sort {
            if $0.date == $1.date { return $0.sortOrder < $1.sortOrder }
            return $0.date < $1.date
        }

        var snapshot = initialSnapshot
        if snapshot.eventAt == nil {
            let initialDate = (events.first?.date ?? date).addingTimeInterval(-1)
            snapshot = reduce(
                snapshot,
                event: hasActivityData ? .reliableData : .missingData,
                at: initialDate
            )
        }

        var wakeStartedThisResolution = false
        for event in events {
            let transition = PiboCoreStatePolicy.reduce(
                snapshot,
                event: event.kind,
                occurredAt: event.date.timeIntervalSince1970
            )
            snapshot = transition.snapshot
            if event.kind == .scheduledWake, transition.eventAccepted {
                wakeStartedThisResolution = true
            }
        }

        if let wakeStartedAt = snapshot.wakeStartedAt {
            let classified = PiboCoreStatePolicy.sleepResult(
                nights: nights,
                stateBeforeSleep: snapshot.stateBeforeSleep
            )
            let shouldReplaceUnknownFallback = hasActivityData
                && (snapshot.state == .dataUnknown || snapshot.pendingState == .dataUnknown)
            if classified.state != nil
                || wakeStartedThisResolution
                || shouldReplaceUnknownFallback {
                let fallback = PiboCoreSleepStateResult(
                    state: hasActivityData ? .stable : .dataUnknown,
                    cause: hasActivityData ? .normalRhythm : .missingData
                )
                snapshot = PiboCoreStatePolicy.reduce(
                    snapshot,
                    event: .sleepResult,
                    occurredAt: wakeStartedAt,
                    sleepResult: classified.state == nil ? fallback : classified
                ).snapshot
            }
        }

        snapshot = PiboCoreStatePolicy.reduce(
            snapshot,
            event: .tick,
            occurredAt: date.timeIntervalSince1970
        ).snapshot

        if snapshot.state == .dataUnknown,
           hasActivityData,
           snapshot.wakeStartedAt == nil {
            snapshot = reduce(snapshot, event: .reliableData, at: date)
        }

        return Resolution(
            decision: Decision(
                state: PiboActivityState(core: snapshot.state),
                cause: snapshot.cause,
                pendingState: snapshot.pendingState.map(PiboActivityState.init(core:)),
                pendingCause: snapshot.pendingCause,
                sleepStartMinute: routine.sleepStartMinute,
                wakeMinute: routine.wakeMinute,
                routineSource: routine.routineSource,
                routineSampleCount: routine.routineSampleCount,
                routineRegularity: routine.routineRegularity,
                routineShiftMinutes: routine.routineShiftMinutes
            ),
            snapshot: snapshot
        )
    }

    private static func reduce(
        _ snapshot: PiboCoreStateSnapshot,
        event: PiboCoreStateEventKind,
        at date: Date
    ) -> PiboCoreStateSnapshot {
        PiboCoreStatePolicy.reduce(
            snapshot,
            event: event,
            occurredAt: date.timeIntervalSince1970
        ).snapshot
    }

    private static func mostRecentBoundary(
        minuteOfDay: Int,
        at date: Date,
        calendar: Calendar
    ) -> Date {
        let start = calendar.startOfDay(for: date)
        let hour = max(0, min(23, minuteOfDay / 60))
        let minute = max(0, min(59, minuteOfDay % 60))
        let today = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: start
        ) ?? start
        guard today > date else { return today }
        return calendar.date(byAdding: .day, value: -1, to: today) ?? today
    }
}

enum PiboStateLifecyclePersistence {
    static let key = "pibo.state.lifecycle.v1"

    static func load(from defaults: UserDefaults = .standard) -> PiboCoreStateSnapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(PiboCoreStateSnapshot.self, from: data)
        else { return PiboCoreStatePolicy.initialSnapshot() }
        return snapshot
    }

    static func save(
        _ snapshot: PiboCoreStateSnapshot,
        to defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
