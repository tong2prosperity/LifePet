import SwiftUI

extension SproutFlowPhase {
    var closeupCaptionText: String? {
        switch self {
        case .collecting:
            "收到一条新的运动记录"
        case .sprouted:
            "Pibo 记下了这次变化"
        case .idle, .pop:
            nil
        }
    }

    var obscuresHomeChrome: Bool {
        switch self {
        case .collecting, .sprouted:
            true
        case .idle, .pop:
            false
        }
    }
}

/// Presents the SwiftUI portion of Home's sprout choreography. SpriteKit owns
/// the close-up animation; this view preserves its captions and completion pop.
struct HomeSproutOverlay: View {
    let phase: SproutFlowPhase
    let onDismissPop: () -> Void

    @ViewBuilder
    var body: some View {
        if let caption = phase.closeupCaptionText {
            VStack(spacing: 0) {
                SproutCaptionView(text: caption)
                Spacer()
            }
            .allowsHitTesting(false)
        }

        if phase == .pop {
            EnergyCollectedPop(onDismiss: onDismissPop)
        }
    }
}
