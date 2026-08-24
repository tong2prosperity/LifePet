import Foundation
import SwiftUI
import UIKit

/// A short-lived forest projection made from the transparent food cut-out.
/// It is presentation-only: calorie recognition and history persistence remain
/// owned by their existing services.
struct HomeFoodProjection: Identifiable, Equatable {
    let id: UUID
    let pngData: Data
    let meal: MealType
    let dishName: String
    let observation: String
    let isCutout: Bool
}

/// Approved 6.08-second `observe_food` performance. The verified sticker is a
/// temporary object in the forest, not another result panel: it appears beside
/// Pibo, Pibo leans toward it, says the server-authored observation, and both
/// return to the ambient scene. The durable calorie record remains in 足迹.
struct HomeFoodProjectionOverlay: View {
    let projection: HomeFoodProjection
    let state: PiboActivityState
    let onObserve: (_ onRight: Bool) -> Void
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stickerOpacity: Double = 0
    @State private var stickerScale: CGFloat = 0.94
    @State private var stickerOffsetY: CGFloat = 8
    @State private var bubbleOpacity: Double = 0

    private var onRight: Bool { state == .sleeping || state == .waking }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if let image = UIImage(data: projection.pngData) {
                    sticker(image, in: geometry.size)
                }

                HomeSpeechOverlay.make(
                    line: PiboSpeechLine(text: projection.observation),
                    onDetail: {}
                )
                .opacity(bubbleOpacity)
                .accessibilityHidden(bubbleOpacity < 0.5)
            }
        }
        .allowsHitTesting(false)
        .task(id: projection.id) {
            await perform()
        }
    }

    private func sticker(_ image: UIImage, in size: CGSize) -> some View {
        let scale = max(size.width / 393, size.height / 852)
        let stickerSize = min(126, max(104, 116 * size.width / 393))
        let margin = max(22, 28 * size.width / 393)
        let designY: CGFloat = switch state {
        case .sleeping, .waking: 338
        case .tired: 464
        default: 392
        }
        let centerX = onRight
            ? size.width - margin - stickerSize / 2
            : margin + stickerSize / 2
        let topY = min(
            size.height - stickerSize - 112,
            max(210, designY * scale)
        )
        return Group {
            if projection.isCutout {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: PiboMoss.Radius.media))
                    .overlay {
                        RoundedRectangle(cornerRadius: PiboMoss.Radius.media)
                            .strokeBorder(Color.white.opacity(0.97), lineWidth: 5)
                    }
                    .background(PiboMoss.Color.raisedNeutral)
            }
        }
        .frame(width: stickerSize, height: stickerSize)
        .position(x: centerX, y: topY + stickerSize / 2)
        .offset(y: stickerOffsetY)
        .scaleEffect(stickerScale)
        .opacity(stickerOpacity)
        .shadow(color: Color(hex: 0x17342B, alpha: 0.16), radius: 10, y: 5)
        .accessibilityLabel(
            AppLocalization.format("Pibo 正在观察%@", projection.dishName)
        )
    }

    private func perform() async {
        stickerScale = reduceMotion ? 1 : 0.94
        stickerOffsetY = reduceMotion ? 0 : 8
        if reduceMotion {
            stickerOpacity = 1
        } else {
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.26)) {
                stickerOpacity = 1
                stickerScale = 1
                stickerOffsetY = 0
            }
        }
        onObserve(onRight)
        do {
            try await Task.sleep(for: .milliseconds(760))
            withAnimation(.easeOut(duration: 0.18)) { bubbleOpacity = 1 }
            try await Task.sleep(for: .milliseconds(3_900))
            withAnimation(.easeIn(duration: 0.14)) { bubbleOpacity = 0 }
            try await Task.sleep(for: .milliseconds(1_180))
            withAnimation(.easeIn(duration: reduceMotion ? 0 : 0.18)) {
                stickerOpacity = 0
                if !reduceMotion { stickerOffsetY = -6 }
            }
            try await Task.sleep(for: .milliseconds(240))
            onComplete()
        } catch {
            return
        }
    }
}

struct HomeTransientNotice: View {
    let text: String

    var body: some View {
        Text(AppLocalization.text(text))
            .lpText(LP.Typography.b3Medium)
            .foregroundStyle(LP.Content.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, LP.Spacing.l)
            .padding(.vertical, LP.Spacing.m)
            .background(
                Capsule()
                    .fill(LP.Fill.bgContainer.opacity(0.96))
            )
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.55), lineWidth: LP.BorderWidth.hair)
            }
            .lpShadow(LP.Shadow.elevation2)
            .accessibilityAddTraits(.isStaticText)
    }
}
