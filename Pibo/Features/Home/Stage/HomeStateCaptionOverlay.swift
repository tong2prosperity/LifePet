import Observation
import SwiftUI

/// When Home says how Pibo is (2026-09-28, mirrors HarmonyOS `PiboStage`):
/// on arrival, on returning to the forest, when the state or its cause
/// changes, and on a single-tap glance. Each showing holds about five seconds
/// and then gets out of the way; showing again while visible restarts the hold.
@MainActor
@Observable
final class HomeStateCaptionPresenter {
    static let arrivalDelay: Duration = .milliseconds(900)
    static let returnDelay: Duration = .milliseconds(700)
    static let changeDelay: Duration = .milliseconds(420)
    static let hold: Duration = .milliseconds(5_200)

    private(set) var isShown = false
    @ObservationIgnored private var task: Task<Void, Never>?

    func show(after delay: Duration) {
        task?.cancel()
        task = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self else { return }
            isShown = true
            try? await Task.sleep(for: Self.hold)
            guard !Task.isCancelled else { return }
            isShown = false
        }
    }

    func hide() {
        task?.cancel()
        task = nil
        isShown = false
    }
}

/// 「● 有点累 · 昨晚没睡够」 just under Pibo's feet. Words only, never numbers;
/// it never takes a touch and VoiceOver reads it through Pibo's own label.
struct HomeStateCaptionOverlay: View {
    let caption: PiboStateCaption
    /// Pibo's feet in full-screen coordinates, as reported by the stage.
    let anchor: CGPoint?
    let isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            if let anchor {
                let global = geometry.frame(in: .global)
                // Follow Pibo sideways, but keep the pill inside the stage.
                let limit = max(0, geometry.size.width / 2 - 140)
                let dx = min(max(anchor.x - global.minX - geometry.size.width / 2, -limit), limit)
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(0, anchor.y - global.minY + 10))
                    pill
                        .frame(maxWidth: max(0, geometry.size.width - 48))
                        .offset(x: dx, y: isPresented ? 0 : 6)
                    Spacer(minLength: 0)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .opacity(isPresented && anchor != nil ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.52), value: isPresented)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var pill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(caption.tone.color)
                .frame(width: 7, height: 7)
            Text(caption.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: 0xF6FAF4))
            Text(caption.detail)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0xDCE8E1))
                .lineLimit(1)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color(hex: 0x142820).opacity(0.6)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
    }
}
