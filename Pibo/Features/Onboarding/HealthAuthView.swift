import SwiftUI
import UserNotifications

enum OnboardingPresentationMode {
    case firstRun
    case storyRecovery
}

/// Six-scene first-run flow. SwiftUI owns presentation; all durable decisions
/// are written through `OnboardingStateStore` before the next scene appears.
struct HealthAuthView: View {
    @Environment(HealthDataService.self) private var health
    @Environment(BoLedgerStore.self) private var boLedger
    @Environment(OnboardingStateStore.self) private var onboarding

    @State private var showsCompactIntroduction = false
    @State private var permissionRequestInFlight = false

    let mode: OnboardingPresentationMode
    let onContinue: () -> Void

    init(
        mode: OnboardingPresentationMode = .firstRun,
        onContinue: @escaping () -> Void
    ) {
        self.mode = mode
        self.onContinue = onContinue
    }

    var body: some View {
        ZStack {
            Image("onboarding_forest_empty")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.08), .black.opacity(0.58)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: LP.Spacing.l) {
                    Spacer(minLength: 32)
                    piboArtwork
                    contentCard
                }
                .padding(.horizontal, LP.Spacing.xl)
                .padding(.bottom, LP.Spacing.xl)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .task {
            if mode == .firstRun {
                if onboarding.snapshot.firstRunStatus == .notStarted {
                    onboarding.begin(at: .encounter)
                }
                showsCompactIntroduction = onboarding.snapshot.usesCompactSetup
                    && onboarding.snapshot.compactIntroductionCompleted != true
            }
        }
    }

    private var piboArtwork: some View {
        Image("onboarding_pibo_normal")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 210, maxHeight: 280)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var contentCard: some View {
        if showsCompactIntroduction {
            compactSetupCard
        } else {
            switch currentCheckpoint {
            case .encounter: encounterCard
            case .identity: identityCard
            case .partnership: partnershipCard
            case .healthSetup: healthCard
            case .notificationSetup: notificationCard
            case .finishing: finishingCard
            }
        }
    }

    private var currentCheckpoint: FirstRunCheckpoint {
        if mode == .storyRecovery {
            return onboarding.storyRecoveryCheckpoint
        }
        return onboarding.snapshot.checkpoint
    }

    private var encounterCard: some View {
        storyCard(
            lines: ["onboarding.encounter.line1", "onboarding.encounter.line2"],
            primary: "onboarding.encounter.primary",
            secondary: mode == .firstRun ? "onboarding.later" : "onboarding.close",
            primaryAction: {
                onboarding.respond()
                onboarding.move(to: .identity)
            },
            secondaryAction: deferStory
        )
    }

    private var identityCard: some View {
        storyCard(
            lines: [
                "onboarding.identity.line1",
                "onboarding.identity.line2",
                "onboarding.identity.line3",
                "onboarding.identity.line4",
            ],
            primary: "onboarding.continue",
            secondary: "onboarding.later",
            primaryAction: { onboarding.move(to: .partnership) },
            secondaryAction: deferStory
        )
    }

    private var partnershipCard: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.m) {
            piboLines([
                "onboarding.partnership.line1",
                "onboarding.partnership.line2",
                "onboarding.partnership.line3",
            ])
            Divider().overlay(.white.opacity(0.2))
            informationBlock(
                title: "onboarding.partnership.bo.title",
                body: "onboarding.partnership.bo.body"
            )
            informationBlock(
                title: "onboarding.partnership.life.title",
                body: "onboarding.partnership.life.body"
            )
            Text(AppLocalization.narrative("onboarding.partnership.boundary"))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(.white.opacity(0.68))
            buttons(
                primary: "onboarding.partnership.accept",
                secondary: "onboarding.later",
                primaryAction: acceptPartnership,
                secondaryAction: deferStory
            )
        }
        .onboardingCard()
    }

    private var compactSetupCard: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.m) {
            title("onboarding.compact.title")
            Text(AppLocalization.narrative("onboarding.compact.body"))
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(.white.opacity(0.82))
            buttons(
                primary: "onboarding.continue",
                primaryAction: {
                    onboarding.completeCompactIntroduction()
                    showsCompactIntroduction = false
                    onboarding.move(to: .healthSetup)
                }
            )
        }
        .onboardingCard()
    }

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.m) {
            title("onboarding.health.title")
            Text(AppLocalization.narrative("onboarding.health.body"))
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(.white.opacity(0.82))
            informationBlock(title: "onboarding.health.rest.title", body: "onboarding.health.rest.body")
            informationBlock(title: "onboarding.health.activity.title", body: "onboarding.health.activity.body")
            informationBlock(title: "onboarding.health.signals.title", body: "onboarding.health.signals.body")
            Text(AppLocalization.narrative("onboarding.health.boundary"))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(.white.opacity(0.68))
            buttons(
                primary: "onboarding.health.connect",
                secondary: "onboarding.health.notNow",
                primaryAction: requestHealth,
                secondaryAction: { onboarding.move(to: .notificationSetup) }
            )
        }
        .onboardingCard()
        .disabled(permissionRequestInFlight)
    }

    private var notificationCard: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.m) {
            title("onboarding.notification.title")
            Text(AppLocalization.narrative("onboarding.notification.body"))
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(.white.opacity(0.82))
            Text(AppLocalization.narrative("onboarding.notification.items"))
                .lpText(LP.Typography.b3Regular)
                .foregroundStyle(.white.opacity(0.82))
            Text(AppLocalization.narrative("onboarding.notification.boundary"))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(.white.opacity(0.68))
            buttons(primary: "onboarding.continue", primaryAction: requestNotifications)
        }
        .onboardingCard()
        .disabled(permissionRequestInFlight)
    }

    private var finishingCard: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.m) {
            if onboarding.snapshot.connection == .accepted {
                piboLines([
                    onboarding.hasObservedHealthSource
                        ? "onboarding.finish.connected.line1"
                        : "onboarding.finish.noData.line1",
                    onboarding.hasObservedHealthSource
                        ? "onboarding.finish.connected.line2"
                        : "onboarding.finish.noData.line2",
                    onboarding.hasObservedHealthSource
                        ? "onboarding.finish.connected.line3"
                        : "onboarding.finish.noData.line3",
                ])
            } else {
                title("onboarding.finish.unanswered.title")
                Text(AppLocalization.narrative("onboarding.finish.unanswered.body"))
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(.white.opacity(0.82))
            }
            Text(AppLocalization.narrative("onboarding.finish.hint"))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(.white.opacity(0.68))
            buttons(primary: "onboarding.enterHome", primaryAction: finish)
        }
        .onboardingCard()
    }

    private func storyCard(
        lines: [String],
        primary: String,
        secondary: String? = nil,
        primaryAction: @escaping () -> Void,
        secondaryAction: @escaping () -> Void = {}
    ) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.m) {
            piboLines(lines)
            buttons(
                primary: primary,
                secondary: secondary,
                primaryAction: primaryAction,
                secondaryAction: secondaryAction
            )
        }
        .onboardingCard()
    }

    private func piboLines(_ keys: [String]) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text("Pibo")
                .lpText(LP.Typography.c1Medium)
                .foregroundStyle(.white.opacity(0.68))
            ForEach(keys, id: \.self) { key in
                Text(AppLocalization.narrative(key))
                    .lpText(LP.Typography.b2Regular)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func title(_ key: String) -> some View {
        Text(AppLocalization.narrative(key))
            .lpText(LP.Typography.uiH4)
            .foregroundStyle(.white)
    }

    private func informationBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(AppLocalization.narrative(title))
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(.white)
            Text(AppLocalization.narrative(body))
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private func buttons(
        primary: String,
        secondary: String? = nil,
        primaryAction: @escaping () -> Void,
        secondaryAction: @escaping () -> Void = {}
    ) -> some View {
        VStack(spacing: LP.Spacing.s) {
            Button(action: primaryAction) {
                Text(AppLocalization.narrative(primary))
                    .lpText(LP.Typography.b2Medium)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(LP.Colorful.teal600)

            if let secondary {
                Button(action: secondaryAction) {
                    Text(AppLocalization.narrative(secondary))
                        .lpText(LP.Typography.b3Medium)
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.78))
            }
        }
    }

    private func acceptPartnership() {
        let acceptedAt = onboarding.acceptTemporaryCooperation(
            boLifetimeMinted: boLedger.lifetimeMinted,
            boLifetimeCollected: boLedger.lifetimeCollected
        )
        boLedger.setEligibilityBoundary(acceptedAt, source: .temporaryCooperation)
        if mode == .storyRecovery {
            onContinue()
        } else {
            onboarding.move(to: .healthSetup)
        }
    }

    private func deferStory() {
        if mode == .storyRecovery {
            onContinue()
            return
        }
        onboarding.skipStory()
        showsCompactIntroduction = true
    }

    private func requestHealth() {
        guard !permissionRequestInFlight else { return }
        permissionRequestInFlight = true
        onboarding.move(to: .healthSetup)
        Task {
            await health.requestAuthorization()
            let readiness = await health.onboardingReadiness()
            onboarding.markHealthRequestCompleted(readiness: readiness)
            Analytics.track(.healthAuth, screen: "onboarding", ["observed_source": .bool(readiness.isReady)])
            permissionRequestInFlight = false
            onboarding.move(to: .notificationSetup)
        }
    }

    private func requestNotifications() {
        guard !permissionRequestInFlight else { return }
        permissionRequestInFlight = true
        onboarding.move(to: .notificationSetup)
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            onboarding.markNotificationRequestCompleted()
            permissionRequestInFlight = false
            onboarding.move(to: .finishing)
        }
    }

    private func finish() {
        onboarding.completeFirstRun()
        LPHaptics.success()
        onContinue()
    }
}

private extension View {
    func onboardingCard() -> some View {
        padding(LP.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            }
    }
}

#Preview {
    HealthAuthView(onContinue: {})
        .environment(HealthDataService(metrics: []))
        .environment(BoLedgerStore())
        .environment(OnboardingStateStore())
}
