import Combine
import SwiftUI

// The sample camera's pixel parts: the viewfinder's corner marks, the scan line over the
// photo while it is checked, and Pibo peeking in from the bottom edge. Presentation only:
// whether a photo is food is the backend's answer, never Pibo's.
//
// Ported from HarmonyPibo `pixel/ui/PixelViewfinder.ets`.

enum PixelPeekMood: Int {
    /// Peeking over the edge, eyes drifting across the frame.
    case watch = 0
    /// The shutter: eyes shut tight.
    case snap = 1
    /// Checking the photo: a little sniff, bobbing.
    case sniff = 2
    /// Not food, or not sure: one eye wide, a question mark.
    case puzzled = 3
}

/// Pibo's top half over an edge. Cut off below the belly, as if leaning on the frame.
struct PixelPeekPibo: View {
    var mood: PixelPeekMood = .watch
    var badge: PiboPixelBadge = .none
    var peekSize: CGFloat = 72
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tick = 0

    private let timer = Timer.publish(every: 0.32, on: .main, in: .common).autoconnect()

    var body: some View {
        PixelCanvas(logicalWidth: 44, logicalHeight: 30,
                    revision: mood.rawValue * 4096 + badge.rawValue * 1024 + tick) { frame in
            paint(frame)
        }
        .frame(width: peekSize, height: peekSize * 30 / 44)
        .onReceive(timer) { _ in
            guard !reduceMotion else { return }
            tick = (tick + 1) % 1024
        }
    }

    private func paint(_ frame: PixelFrame) {
        let pose = PiboPixelPose()
        pose.badge = badge
        pose.leafGrowth = 0.7
        switch mood {
        case .snap:
            pose.eyes = .squint
        case .sniff:
            pose.eyes = tick % 2 == 0 ? .open : .happy
            pose.squash = tick % 2 == 0 ? 0 : 1
            pose.lookUp = true
        case .puzzled:
            pose.eyes = .uneven
            pose.mouth = .open
            pose.lean = 2
        case .watch:
            // Eyes drift left, centre, right, centre: watching the frame.
            let drift: [Double] = [0, -1, 0, 1]
            pose.lookX = drift[(tick / 4) % drift.count]
            pose.lookUp = true
            pose.sproutSway = drift[(tick / 2) % drift.count]
        }
        // Ground well below the frame: only the head, the leaf and the top of the belly show.
        drawPiboPixel(frame, 22, 48, pose)
        if mood == .puzzled { drawPixelQuestion(frame, 35, 2, Double(tick) * 320) }
    }
}

/// The four corner marks of the framing guide, square and chunky.
struct PixelFinderCorners: View {
    var color: Color = .white
    var arm: CGFloat = 26
    var thick: CGFloat = 5

    var body: some View {
        ZStack {
            corner(.topLeading)
            corner(.topTrailing)
            corner(.bottomLeading)
            corner(.bottomTrailing)
        }
        .accessibilityHidden(true)
    }

    private func corner(_ alignment: Alignment) -> some View {
        ZStack(alignment: alignment) {
            Rectangle().fill(color).frame(width: arm, height: thick)
            Rectangle().fill(color).frame(width: thick, height: arm)
        }
        .frame(width: arm, height: arm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

/// A bright band sweeping down and up the photo while the backend checks it.
struct PixelScanLine: View {
    var color: Color = PixelUIColor.leafLight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var down = false

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(color)
                .frame(height: 6)
                .opacity(0.85)
                .shadow(color: .white.opacity(0.4), radius: 0, x: 0, y: 4)
                .offset(y: down ? proxy.size.height * 0.96 : proxy.size.height * 0.04)
                .animation(reduceMotion ? nil
                           : .linear(duration: 1.4).repeatForever(autoreverses: true),
                           value: down)
                .onAppear { down = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
