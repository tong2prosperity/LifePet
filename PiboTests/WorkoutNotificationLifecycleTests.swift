import Foundation
import Testing
import UserNotifications
@testable import Pibo

@MainActor
struct WorkoutNotificationLifecycleTests {
    private final class State { var background = true }
    private final class Center: WorkoutNotificationScheduling {
        var requests: [UNNotificationRequest] = []
        var beforeStatusReturn: (() -> Void)?
        var afterAdd: (() -> Void)?
        func workoutAuthorizationStatus() async -> UNAuthorizationStatus {
            beforeStatusReturn?()
            return .authorized
        }
        func workoutRequestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
        func workoutAdd(_ request: UNNotificationRequest) async throws { requests.append(request); afterAdd?() }
        func workoutWithdraw(_ identifier: String) { requests.removeAll { $0.identifier == identifier } }
    }
    private func workout() -> PendingWorkout {
        .init(id: UUID(), kind: .run, label: "跑步", durationMin: 24, kcal: 180,
              endedAt: .now, gainVitality: 0)
    }

    @Test func disablingWhileAuthorizationIsBeingReadRejectsTheOldPublication() async throws {
        let key = "WorkoutNotificationLifecycleTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let center = Center(), state = State()
        let notifier = WorkoutCompletionNotifier(notificationCenter: center, defaults: defaults,
            preferenceDefaults: defaults, isBackground: { state.background })
        center.beforeStatusReturn = { notifier.pushEnabled = false }
        #expect(await notifier.notifyStepsAchievement() == false)
        #expect(center.requests.isEmpty)
    }

    @Test(arguments: [false, true])
    func anInFlightSystemAddCannotOutliveDisableOrForegroundReturn(foreground: Bool) async throws {
        let key = "WorkoutNotificationLifecycleTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let center = Center(), state = State()
        let notifier = WorkoutCompletionNotifier(notificationCenter: center, defaults: defaults,
            preferenceDefaults: defaults, isBackground: { state.background })
        center.afterAdd = {
            if foreground { state.background = false; notifier.invalidatePendingReminder() }
            else { notifier.pushEnabled = false }
        }
        let captured = workout()
        #expect(await notifier.maybeNotify(workout: captured, piboState: .stable) == false)
        #expect(center.requests.isEmpty)
        center.afterAdd = nil
        state.background = true
        notifier.pushEnabled = true
        #expect(await notifier.maybeNotify(workout: captured, piboState: .stable))
        #expect(await notifier.maybeNotify(workout: captured, piboState: .stable) == false)
        #expect(center.requests.count == 1, "only an accepted publication consumes the workout ID")
    }

    @Test func foregroundNeverPublishesEvenWithExistingPermission() async throws {
        let key = "WorkoutNotificationLifecycleTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let center = Center()
        let notifier = WorkoutCompletionNotifier(notificationCenter: center, defaults: defaults,
            preferenceDefaults: defaults, isBackground: { false })
        #expect(await notifier.notifyStepsAchievement() == false)
        #expect(await notifier.maybeNotify(workout: workout(), piboState: .stable) == false)
        #expect(center.requests.isEmpty)
    }
}
