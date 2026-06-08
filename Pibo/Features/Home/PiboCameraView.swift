import SwiftUI

/// 拍照交互 (spec §4): 露珠相机 → 拍摄 → 扫描线 → 预览 + Pibo 弹幕 → 保存/重拍.
///
/// The capture itself is synthesized (a soft placeholder frame) so the flow runs
/// everywhere incl. the simulator; wiring a real `AVCaptureSession` later only
/// swaps the viewfinder/preview image. No AI recognition — 弹幕 are time-bucketed
/// + a generic pool (spec §4.1).
struct PiboCameraView: View {
    @Environment(\.dismiss) private var dismiss
    var onPhotoSaved: () -> Void = {}

    private enum Phase { case viewfinder, scanning, preview }
    @State private var phase: Phase = .viewfinder
    @State private var comment: String = ""
    @State private var capturedAt = Date()
    @State private var scanY: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // The "frame" — viewfinder dim, captured placeholder once shot.
            capturedFrame
                .ignoresSafeArea()
                .overlay { if phase == .viewfinder { viewfinderChrome } }
                .overlay { if phase == .scanning { scanLine } }

            VStack {
                topBar
                Spacer()
                switch phase {
                case .viewfinder: shutterBar
                case .scanning:   EmptyView()
                case .preview:    previewBar
                }
            }
            .padding(LP.Spacing.l)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Frame

    private var capturedFrame: some View {
        LinearGradient(
            colors: phase == .viewfinder
                ? [Color(hex: 0x2A2A2E), Color(hex: 0x17171A)]
                : [Color(hex: 0xC9D6C2), Color(hex: 0xE7DCC6), Color(hex: 0xCBB79A)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var viewfinderChrome: some View {
        ZStack {
            // Corner reticle.
            RoundedRectangle(cornerRadius: LP.Radius.l)
                .strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                .padding(LP.Spacing.xxl5)
            Image(systemName: "drop.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var scanLine: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(LinearGradient(colors: [.clear, LP.Fill.foundationAccent.opacity(0.8), .clear],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: 120)
                .offset(y: scanY)
                .onAppear {
                    scanY = -120
                    withAnimation(.easeInOut(duration: 0.9)) { scanY = geo.size.height }
                }
        }
        .ignoresSafeArea()
    }

    // MARK: Bars

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.black.opacity(0.35)))
            }
            .buttonStyle(.plain)
            Spacer()
            if phase != .viewfinder {
                Text(timestampLabel)
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, LP.Spacing.s)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.35)))
            }
        }
    }

    private var shutterBar: some View {
        Button(action: capture) {
            ZStack {
                Circle().stroke(.white, lineWidth: 3).frame(width: 72, height: 72)
                Circle().fill(.white).frame(width: 58, height: 58)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text("拍摄"))
    }

    private var previewBar: some View {
        VStack(spacing: LP.Spacing.l) {
            // Pibo 弹幕.
            Text(comment)
                .lpText(LP.Typography.b2Medium)
                .foregroundStyle(LP.Content.primary)
                .padding(.horizontal, LP.Spacing.l)
                .padding(.vertical, LP.Spacing.s)
                .background(
                    RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous)
                        .fill(LP.Fill.bgContainer.opacity(0.96))
                )
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: LP.Spacing.m) {
                Button { reset() } label: {
                    Text(AppLocalization.text("重拍"))
                        .lpText(LP.Typography.b2Medium)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LP.Spacing.m)
                        .background(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                Button { save() } label: {
                    Text(AppLocalization.text("保存"))
                        .lpText(LP.Typography.b2Medium)
                        .foregroundStyle(LP.Fill.foundationOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LP.Spacing.m)
                        .background(Capsule().fill(LP.Fill.foundationAccent))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Actions

    private func capture() {
        LPHaptics.tap()
        capturedAt = Date()
        comment = Self.comment(at: capturedAt)
        withAnimation { phase = .scanning }
        Task {
            try? await Task.sleep(for: .seconds(1.0))
            withAnimation { phase = .preview }
        }
    }

    private func reset() {
        withAnimation { phase = .viewfinder }
    }

    private func save() {
        LPHaptics.tap()
        onPhotoSaved()
        dismiss()
    }

    // MARK: Copy + format

    private var timestampLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.M.d HH:mm a"
        f.amSymbol = "AM"; f.pmSymbol = "PM"
        return f.string(from: capturedAt)
    }

    /// 时段硬卡文案 + 通用池 (spec §4.1).
    static func comment(at date: Date) -> String {
        let h = Calendar.current.component(.hour, from: date)
        let bucket: [String]
        switch h {
        case 6...10:  bucket = ["…颜色…？", "…地球…早上…吃…？", "…圆…？", "…形状…怪…"]
        case 11...14: bucket = ["…亮…", "…这个…？", "…能吃…？", "…颜色…记…"]
        case 17...20: bucket = ["…暗了…还吃…？", "…一天…几次…？", "…饱…？"]
        default:      bucket = ["…又吃了…？", "…Pibo记住了…", "…好奇特的味道…"]
        }
        return (bucket + genericComments).randomElement() ?? "…这个…能吃？"
    }

    static let genericComments = [
        "…这个…能吃？", "…地球的…食物…好奇怪…", "…#@!%…闻起来…", "…花…不吃…这个…",
        "…人的能量…从这儿来…？", "…Pibo…只能…光合作用…", "…看起来…比土壤…好吃…",
        "…颜色…没…见过…", "…形状…不像…花…", "…地球…东西…都…能吃？",
    ]
}

#Preview {
    PiboCameraView()
}
