import SwiftUI

struct PiboBreathingGuideView: View {
    let snapshot: CRCSnapshot?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expansion = 0.0

    private var phase: CRCBreathingPhase { snapshot?.phase ?? .inhale }
    private var phaseDuration: Double {
        let rate = max(snapshot?.guidedBreathingRate ?? CRCConstants.initialGuidedBreathingRate, 0.1)
        return 60 / rate * (phase == .inhale ? CRCConstants.inhaleRatio : CRCConstants.exhaleRatio)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let p = reduceMotion ? 0.32 : expansion
            ZStack {
                Circle()
                    .fill(Color(red: 0.20, green: 0.78, blue: 0.63).opacity(0.07 + p * 0.08))
                    .frame(width: 200 + p * 18, height: 200 + p * 18)
                    .blur(radius: 18)

                breathingGround(progress: p)

                feet
                bodyLayer(progress: p)
                sproutLayer(progress: p)
                faceLayer(progress: p)
                armsLayer(progress: p)
            }
            .frame(width: 300, height: 300)
            .scaleEffect(side / 240)
            .offset(y: -4)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear { synchronize() }
        .onChange(of: phase) { _, _ in synchronize() }
    }

    private var feet: some View {
        ZStack {
            orphan_default_0_0()
            orphan_default_1_1()
        }
        .frame(width: 300, height: 300)
    }

    private func bodyLayer(progress: Double) -> some View {
        ZStack {
            WatchPiboMorphPolygonShape(
                fromPoly: polygon(for: "body", in: .default),
                toPoly: polygon(for: "body", in: .default),
                progress: 1
            )
            .fill(.white)
            orphan_default_2_2()
        }
        .frame(width: 300, height: 300)
        .scaleEffect(x: 1 + progress * 0.035, y: 1 + progress * 0.09, anchor: .bottom)
        .offset(y: -progress * 2.6)
    }

    private func sproutLayer(progress: Double) -> some View {
        ZStack {
            WatchPiboMorphPolygonShape(
                fromPoly: polygon(for: "bo", in: .default),
                toPoly: polygon(for: "bo", in: .default),
                progress: 1
            )
            .fill(Color(red: 0.57, green: 0.89, blue: 0.39))
            WatchPiboMorphShape(
                from: segments(for: "boline", subpath: 0, in: .default),
                to: segments(for: "boline", subpath: 0, in: .default),
                progress: 1
            )
            .stroke(.white.opacity(0.96), style: StrokeStyle(lineWidth: 0.84, lineCap: .round))
        }
        .frame(width: 300, height: 300)
        .scaleEffect(x: 1 + progress * 0.025, y: 1 + progress * 0.05, anchor: UnitPoint(x: 0.53, y: 0.39))
        .rotationEffect(.degrees(-progress * 1.8), anchor: UnitPoint(x: 0.53, y: 0.48))
        .offset(y: -progress * 6.2)
    }

    private func faceLayer(progress: Double) -> some View {
        ZStack {
            orphan_default_3_3()
            orphan_default_4_4()
            orphan_default_5_5()
            orphan_default_6_6()
            orphan_default_7_7()
        }
        .frame(width: 300, height: 300)
        .offset(y: -progress * 4.8)
    }

    private func armsLayer(progress: Double) -> some View {
        ZStack {
            orphan_default_8_8()
                .rotationEffect(.degrees(-progress * 4.0), anchor: UnitPoint(x: 0.39, y: 0.57))
            orphan_default_9_9()
                .rotationEffect(.degrees(progress * 4.0), anchor: UnitPoint(x: 0.66, y: 0.57))
        }
        .frame(width: 300, height: 300)
        .offset(y: -progress * 2.2)
    }

    private func breathingGround(progress: Double) -> some View {
        Canvas { context, _ in
            for index in 0..<4 {
                let width = 116.0 - Double(index) * 18
                let rect = CGRect(
                    x: 150 - width / 2,
                    y: 250 + Double(index) * 3,
                    width: width,
                    height: 8
                )
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(Color(red: 0.20, green: 0.78, blue: 0.63).opacity(0.46 + progress * 0.12)),
                    lineWidth: 1.0
                )
            }
        }
        .frame(width: 300, height: 300)
    }

    private func synchronize() {
        guard !reduceMotion else { expansion = 0.32; return }
        withAnimation(.easeInOut(duration: phaseDuration)) {
            expansion = phase == .inhale ? 1 : 0
        }
    }
}
