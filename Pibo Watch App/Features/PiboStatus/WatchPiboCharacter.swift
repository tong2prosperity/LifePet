import SwiftUI
import WatchKit

/// Watch playback of an action selected by Core on iPhone. This view never
/// changes the pet state, growth, conversation cursor or health records.
struct WatchPiboCharacter: View {
    let state: PiboVectorState
    var boProgress: Double = 1
    var actionID: String?
    var isInteractive = false
    var animates = true
    var petName = "Pibo"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reaction = WatchPatPose()
    @State private var reactionTask: Task<Void, Never>?
    @State private var isResponding = false

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            PiboStateAnimator(state: .constant(state), boProgress: boProgress, animates: animates)
                .id(state)
                .frame(width: 300, height: 300)
                .scaleEffect(side / 260)
                .scaleEffect(x: reaction.scaleX, y: reaction.scaleY, anchor: .bottom)
                .rotationEffect(.degrees(reaction.rotation), anchor: .bottom)
                .offset(y: reaction.offsetY)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .overlay {
                    if isResponding {
                        Ellipse().stroke(.mint.opacity(0.55), lineWidth: 2)
                            .frame(width: side * 0.76, height: side * 0.92)
                    }
                }
                .contentShape(WatchPiboBodyHitShape(state: state))
                .onTapGesture(count: PiboPatGesturePolicy.requiredTapCount) { respond() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(isInteractive ? "拍一拍\(petName)" : petName)
                .accessibilityValue(isResponding ? "已回应" : "")
                .accessibilityAddTraits(isInteractive ? .isButton : .isImage)
                .accessibilityAction { respond() }
        }
        .onChange(of: state) { _, _ in cancelReaction() }
        .onChange(of: actionID) { _, _ in cancelReaction() }
        .onChange(of: animates) { _, active in if !active { cancelReaction() } }
        .onDisappear { cancelReaction() }
    }

    private func respond() {
        guard isInteractive, animates else { return }
        reactionTask?.cancel()
        WKInterfaceDevice.current().play(.click)
        // Repeated accepted double taps restart feedback immediately, never queue.
        reaction = WatchPatPose()
        isResponding = true
        if !reduceMotion {
            withAnimation(.easeOut(duration: 0.18)) { reaction = .forAction(actionID) }
        }
        reactionTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.24)) { reaction = WatchPatPose() }
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled else { return }
            isResponding = false
        }
    }

    private func cancelReaction() {
        reactionTask?.cancel()
        reactionTask = nil
        reaction = WatchPatPose()
        isResponding = false
    }
}

/// Match the authored body silhouette; tapping the background or the bo does not
/// count as a physical pat. Accessibility activation remains an explicit action.
private struct WatchPiboBodyHitShape: Shape {
    let state: PiboVectorState

    func path(in rect: CGRect) -> Path {
        let points = polygon(for: "body", in: state)
        let scale = min(rect.width, rect.height) / 260
        var path = Path()
        for (index, point) in points.enumerated() {
            let mapped = CGPoint(x: rect.midX + (point.x - 150) * scale, y: rect.midY + (point.y - 150) * scale)
            if index == 0 { path.move(to: mapped) } else { path.addLine(to: mapped) }
        }
        path.closeSubpath()
        return path
    }
}

/// Native transforms are presentation values, not state-selection policy.
private struct WatchPatPose {
    var scaleX = 1.0
    var scaleY = 1.0
    var rotation = 0.0
    var offsetY = 0.0

    static func forAction(_ id: String?) -> Self {
        switch id {
        case "letSleep": Self(scaleX: 1.02, scaleY: 0.98, rotation: -2, offsetY: 1)
        case "morningGreeting": Self(scaleX: 0.97, scaleY: 1.05, rotation: 4, offsetY: -3)
        case "checkIn": Self(scaleX: 1.04, scaleY: 0.96, rotation: 3, offsetY: 1)
        case "play": Self(scaleX: 0.97, scaleY: 1.04, rotation: -5, offsetY: -8)
        case "rest": Self(scaleX: 1.03, scaleY: 0.97, rotation: 2, offsetY: 2)
        case "checkConnection": Self(scaleX: 1, scaleY: 1, rotation: -4, offsetY: 0)
        default: Self(scaleX: 1.02, scaleY: 0.98, rotation: 0, offsetY: 0)
        }
    }
}

/// Reveal the existing leaf asset outward from the point nearest Pibo's body.
/// The input is the ledger's exact continuous progress, with no stage thresholds.
struct WatchBoGrowthMask: Shape {
    let state: PiboVectorState
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let leaf = polygon(for: "bo", in: state)
        let body = polygon(for: "body", in: state)
        guard progress > 0, !leaf.isEmpty, !body.isEmpty else { return Path() }
        let center = CGPoint(
            x: body.map(\.x).reduce(0, +) / Double(body.count),
            y: body.map(\.y).reduce(0, +) / Double(body.count)
        )
        let root = leaf.min { hypot($0.x - center.x, $0.y - center.y) < hypot($1.x - center.x, $1.y - center.y) }!
        let radius = ((leaf.map { hypot($0.x - root.x, $0.y - root.y) }.max() ?? 0) + 2) * min(1, progress)
        return Path(ellipseIn: CGRect(x: root.x - radius, y: root.y - radius, width: radius * 2, height: radius * 2))
    }
}
