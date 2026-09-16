import SwiftUI

/// One-time, skippable Home guide after the daily first run (decision 049).
///
/// `.pat` invites a body double tap; the double tap itself runs the existing
/// Home/Core reaction and advances the guide (see `HomeStageInteractions`).
/// `.growth` then points at the tool entries and offers the optional
/// notification permission — the only place first run asks for it.
///
/// The card never blocks the forest and stays hidden while anything else owns
/// the moment (speech, sheets, covers, food projection), so the tools hint
/// appears only after the first real reply has left.
struct DailyHomeGuideOverlay: View {
    @Environment(OnboardingStateStore.self) private var onboarding

    /// True while another Home presentation should own the screen.
    let isBlocked: Bool

    var body: some View {
        if onboarding.dailyHomeGuide != .none, !isBlocked {
            VStack {
                Spacer()
                DailyHomeGuideCard(onboarding: onboarding)
                    .padding(.horizontal, LP.Spacing.l)
                    // Clear of the 足迹 button in the bottom-right corner.
                    .padding(.bottom, 96)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct DailyHomeGuideCard: View {
    @Environment(PetStateStore.self) private var store
    @Environment(HealthDataService.self) private var health
    @Environment(StressNotifier.self) private var stressNotifier
    @Environment(WorkoutCompletionNotifier.self) private var workoutNotifier

    let onboarding: OnboardingStateStore

    @State private var requesting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if onboarding.dailyHomeGuide == .pat {
                    patContent
                } else {
                    growthContent
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 480, maxHeight: 260)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LP.Fill.bgContainer.opacity(0.94))
        )
        .accessibilityIdentifier("pibo.daily-home-guide")
    }

    private var patContent: some View {
        Group {
            Text(DailyOnboardingCopy.patTitle)
                .lpText(LP.Typography.b2Medium)
                .foregroundStyle(LP.Content.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(healthMessage)
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                onboarding.dismissDailyHomeGuide()
            } label: {
                Text(DailyOnboardingCopy.patSkip)
                    .lpText(LP.Typography.b3Medium)
                    .foregroundStyle(LP.Content.secondary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var growthContent: some View {
        Group {
            Text(DailyOnboardingCopy.homeTitle)
                .lpText(LP.Typography.b2Medium)
                .foregroundStyle(LP.Content.primary)
            Text(DailyOnboardingCopy.tools)
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(DailyOnboardingCopy.notificationsBody)
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    onboarding.dismissDailyHomeGuide()
                } label: {
                    Text(DailyOnboardingCopy.done)
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(LP.Content.primary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color(hex: 0xE2EBDD), in: Capsule())
                }
                .buttonStyle(.plain)
                Button(action: requestNotifications) {
                    Text(requesting ? DailyOnboardingCopy.connecting : DailyOnboardingCopy.notificationsEnable)
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color(hex: 0x237653), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(requesting)
            }
        }
    }

    private var healthMessage: String {
        DailyHomeGuideHealthMessage.resolve(
            hasRealHealthData: store.hasRealHealthData,
            authState: health.authState
        )
    }

    private func requestNotifications() {
        guard !requesting else { return }
        requesting = true
        Task {
            // Full (non-provisional) request: the user chose it explicitly.
            await stressNotifier.requestAuthorization()
            // Already decided above, so this only mirrors the result.
            await workoutNotifier.requestAuthorization()
            onboarding.markNotificationRequestCompleted()
            onboarding.dismissDailyHomeGuide()
            requesting = false
        }
    }
}

enum DailyHomeGuideHealthMessage {
    static func resolve(
        hasRealHealthData: Bool,
        authState: HealthDataService.AuthState
    ) -> String {
        if hasRealHealthData { return DailyOnboardingCopy.dataReady }
        switch authState {
        case .unavailable: return DailyOnboardingCopy.dataUnavailable
        case .requesting: return DailyOnboardingCopy.dataRequesting
        case .granted: return DailyOnboardingCopy.dataWaiting
        case .unknown, .denied: return DailyOnboardingCopy.dataNotConnected
        }
    }
}
