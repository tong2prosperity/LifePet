import Foundation
import SwiftUI

// MARK: - 识别到用户的活动 → 发芽 flow (Figma 74:6102)
//
// When the app opens with a freshly-detected workout (`store.pendingWorkout`),
// the home auto-plays a close-up of Pibo's head: 毛抖动 → 发力 → 长出叶片,
// then pulls back and confirms that the workout record was synced. The first
// acknowledged workout is what
// sprouts the 魔丸 「?」卷芽 into a leaf (pibo头顶发生变化); later collections
// play the small in-place head shake instead.
//
// `HomeView` owns the phase state; the SpriteKit stage performs the placeholder
// animation (`PiboStageScene.playSproutCloseup`).

/// **The animation seam.** The designer's close-up is planned as a Lottie
/// (Figma note: 暂定为lottie素材 — 毛抖动-发力-长出叶片, not yet delivered).
/// Until it lands, the stage placeholder animates the existing sprites.
///
/// To plug the real asset in: add a Lottie runtime (SwiftPM), build a
/// full-screen player view for the `.lottie` case in `HomeView.startEnergyFlow`,
/// and flip `current`. The phase callbacks (`SproutCloseupPhase`) are the
/// contract either implementation must honor.
enum SproutAnimationStyle {
    /// Shipped placeholder: SpriteKit camera zoom + sprite wiggle/swap.
    case stagePlaceholder
    /// TODO(design): designer-delivered Lottie close-up.
    case lottie(asset: String)

    static let current: SproutAnimationStyle = .stagePlaceholder
}

/// Where the home currently is in the energy-collection choreography.
enum SproutFlowPhase: Equatable {
    case idle
    case collecting   // camera in, 毛抖动 — 新运动记录
    case sprouted     // 长出叶片 — Pibo 记下变化
    case pop          // back on the home floor — 记录已同步 card
}

/// Resolves whether a pending workout can start the Home sprout choreography
/// and which existing renderer path it should use. Playback and phase changes
/// stay in `HomeView`; this type only packages the decision inputs.
enum HomeSproutFlowStartResolver {
    enum Animation: Equatable {
        case stageCloseup
        case lottieCloseup(asset: String)
        case inPlaceGrowth
    }

    struct Request: Equatable {
        let workoutID: UUID
        let growthStart: Double
        let growthTarget: Double
        let animation: Animation
    }

    static func resolve(
        pendingWorkout: @autoclosure () -> PendingWorkout?,
        phase: @autoclosure () -> SproutFlowPhase,
        sheetPresented: @autoclosure () -> Bool,
        fullScreenFeaturePresented: @autoclosure () -> Bool,
        growthStart: @autoclosure () -> Double,
        growthTarget: (PendingWorkout) -> Double,
        canSprout: @autoclosure () -> Bool,
        animationStyle: @autoclosure () -> SproutAnimationStyle
    ) -> Request? {
        guard let workout = pendingWorkout(),
              phase() == .idle,
              !sheetPresented(),
              !fullScreenFeaturePresented()
        else { return nil }

        let start = growthStart()
        let target = growthTarget(workout)
        let animation: Animation
        if canSprout() {
            switch animationStyle() {
            case .stagePlaceholder:
                animation = .stageCloseup
            case .lottie(let asset):
                animation = .lottieCloseup(asset: asset)
            }
        } else {
            animation = .inPlaceGrowth
        }

        return Request(
            workoutID: workout.id,
            growthStart: start,
            growthTarget: target,
            animation: animation
        )
    }
}

// MARK: - Close-up caption (Figma Frame 9397 — centered, top of the screen)

struct SproutCaptionView: View {
    let text: String

    var body: some View {
        Text(AppLocalization.text(text))
            .lpText(LP.Typography.uiH5)
            .foregroundStyle(LP.Content.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, LP.Spacing.l)
            .padding(.top, LP.Spacing.xxl3)
            .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Workout record synced pop (Figma `pop` 76:6725, used in 70:4549)

/// White rounded card floated over a muted scrim: hand glyph, two-line copy
/// The existing visual choreography remains, but the copy describes the durable
/// workout fact instead of inventing a separate collectible-energy source.
struct EnergyCollectedPop: View {
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            LP.Fill.maskMuted
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: LP.Spacing.xl) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(LP.Content.secondary)
                    .frame(width: 72, height: 72)

                VStack(spacing: 2) {
                    Text(AppLocalization.text("运动记录已同步"))
                    Text(AppLocalization.text("会用于之后的可见积累"))
                }
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.secondary)
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, LP.Spacing.xxl)
            .padding(.vertical, LP.Spacing.l)
            .frame(minWidth: 199, minHeight: 189)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(alignment: .topTrailing) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(LP.Content.secondary.opacity(0.2))
                        .padding(LP.Spacing.m)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.text("关闭"))
            }
            .lpShadow(LP.Shadow.elevation3)
            .onTapGesture(perform: onDismiss)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }
}

#Preview {
    ZStack {
        Color(hex: 0xF4F8F9).ignoresSafeArea()
        EnergyCollectedPop(onDismiss: {})
    }
}
