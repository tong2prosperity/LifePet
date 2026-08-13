import SwiftUI

enum HomeSpeechBubbleLayout {
    private static let referenceWidth: CGFloat = 393
    private static let referenceHeight: CGFloat = 852
    private static let referenceBubbleBottom: CGFloat = 317

    static func frameHeight(in size: CGSize) -> CGFloat {
        let scale = max(size.width / referenceWidth, size.height / referenceHeight)
        let originY = (size.height - referenceHeight * scale) / 2
        return max(0, originY + referenceBubbleBottom * scale)
    }
}

enum HomeSpeechOverlay {
    static func make(
        line: PiboSpeechLine,
        onDetail: @escaping () -> Void
    ) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                PiboSpeechBubbleView(
                    line: line,
                    onDetail: line.data == nil ? nil : onDetail
                )
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            .frame(
                width: geometry.size.width,
                height: HomeSpeechBubbleLayout.frameHeight(in: geometry.size)
            )
        }
        .allowsHitTesting(line.data != nil)
    }
}
