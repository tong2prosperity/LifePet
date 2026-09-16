import SwiftUI

enum HomeSpeechBubbleLayout {
    private static let referenceWidth: CGFloat = 393
    private static let referenceHeight: CGFloat = 852
    /// Stable dialogue band used until the stage reports the pose's container
    /// top (2026-09-09: moved down from 317 toward Pibo).
    private static let referenceBubbleBottom: CGFloat = 367
    /// Gap between the tail and the bo container top, design units.
    private static let anchorGap: CGFloat = 6
    /// The bubble may never climb over the balance chip / corner entries.
    private static let minimumBottomBelowSafeTop: CGFloat = 180

    static func scale(in size: CGSize) -> CGFloat {
        max(size.width / referenceWidth, size.height / referenceHeight)
    }

    static func frameHeight(in size: CGSize) -> CGFloat {
        let scale = scale(in: size)
        let originY = (size.height - referenceHeight * scale) / 2
        return max(0, originY + referenceBubbleBottom * scale)
    }

    /// Bubble bottom in global coordinates: just above the current pose's bo
    /// container, clamped below the top chrome.
    static func bottom(
        anchorY: CGFloat?,
        screenSize: CGSize,
        safeTop: CGFloat
    ) -> CGFloat {
        let fallback = frameHeight(in: screenSize)
        let raw = anchorY.map { $0 - anchorGap * scale(in: screenSize) } ?? fallback
        return max(raw, safeTop + minimumBottomBelowSafeTop)
    }
}

enum HomeSpeechOverlay {
    static func make(
        line: PiboSpeechLine,
        anchorY: CGFloat? = nil,
        onDetail: @escaping () -> Void,
        onChoice: ((String) -> Void)? = nil,
        onCustomReply: (() -> Void)? = nil
    ) -> some View {
        GeometryReader { geometry in
            let global = geometry.frame(in: .global)
            let screen = CGSize(
                width: global.width,
                height: global.maxY + geometry.safeAreaInsets.bottom
            )
            let bottom = HomeSpeechBubbleLayout.bottom(
                anchorY: anchorY,
                screenSize: screen,
                safeTop: global.minY
            ) - global.minY
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                PiboSpeechBubbleView(
                    line: line,
                    maxAvailableWidth: max(120, geometry.size.width - 40),
                    onDetail: line.data == nil ? nil : onDetail,
                    onChoice: onChoice,
                    onCustomReply: onCustomReply
                )
                .transition(PiboSpeechBubbleView.transition)
            }
            .frame(width: geometry.size.width, height: max(0, bottom))
        }
        .allowsHitTesting(line.data != nil || line.interaction != nil)
    }
}
