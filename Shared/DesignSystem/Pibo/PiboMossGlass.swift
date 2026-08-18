import SwiftUI

/// Semantic UI layer for forest-backed sheets, meal capture, and recovery
/// surfaces. The existing LP foundation remains authoritative; this namespace
/// gives the new surfaces stable product roles without re-theming History.
enum PiboMoss {
    enum Color {
        static let canvasMist = SwiftUI.Color(hex: 0xEAF1F2)
        static let sheetMoss = SwiftUI.Color(hex: 0xE5F0E8)
        static let raisedNeutral = SwiftUI.Color(hex: 0xF5F7F4)
        static let forestInk = SwiftUI.Color(hex: 0x263632)
        static let secondaryInk = SwiftUI.Color(hex: 0x667570)
        static let tertiaryInk = SwiftUI.Color(hex: 0x8A9893)
        static let hairline = SwiftUI.Color(hex: 0xBFD1C9)
        static let foundationTeal = SwiftUI.Color(hex: 0x24B596)
        static let activityCyan = SwiftUI.Color(hex: 0x28AFC0)
        static let stepsGreen = SwiftUI.Color(hex: 0x46A95F)
        static let sleepIndigo = SwiftUI.Color(hex: 0x56659A)
        static let carbsAmber = SwiftUI.Color(hex: 0xD4A447)
        static let proteinBerry = SwiftUI.Color(hex: 0xC76A72)
        static let fatBlue = SwiftUI.Color(hex: 0x558FB3)
        static let forestVeil = SwiftUI.Color(hex: 0x0B201A, alpha: 0.40)
        static let cameraDeck = SwiftUI.Color(hex: 0x213730, alpha: 0.86)
        static let cameraControl = SwiftUI.Color(hex: 0x2B433B, alpha: 0.72)
        static let cameraHairline = SwiftUI.Color(hex: 0xDDE9E3, alpha: 0.58)
        static let onDarkPrimary = SwiftUI.Color.white.opacity(0.95)
        static let onDarkSecondary = SwiftUI.Color.white.opacity(0.75)
        static let disabledFill = SwiftUI.Color(hex: 0xBFD1C9, alpha: 0.48)
        static let disabledInk = SwiftUI.Color(hex: 0x667570, alpha: 0.62)
    }

    enum Radius {
        static let control: CGFloat = 14
        static let media: CGFloat = 16
        static let card: CGFloat = 20
        static let sheet: CGFloat = 32
    }

    enum Control {
        static let minimumHit: CGFloat = 44
        static let buttonHeight: CGFloat = 52
        static let shutterDiameter: CGFloat = 72
        static let handleWidth: CGFloat = 36
        static let handleHeight: CGFloat = 5
    }
}

struct PiboMossSheetHandle: View {
    var body: some View {
        Capsule()
            .fill(PiboMoss.Color.secondaryInk.opacity(0.25))
            .frame(
                width: PiboMoss.Control.handleWidth,
                height: PiboMoss.Control.handleHeight
            )
            .accessibilityHidden(true)
    }
}

struct PiboMossPrimaryButton: View {
    let title: String
    var disabledReason: String?
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(isEnabled ? title : (disabledReason ?? title))
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(isEnabled ? .white : PiboMoss.Color.disabledInk)
                .frame(maxWidth: .infinity, minHeight: PiboMoss.Control.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: PiboMoss.Radius.control, style: .continuous)
                        .fill(isEnabled ? PiboMoss.Color.foundationTeal : PiboMoss.Color.disabledFill)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityHint(isEnabled ? "" : (disabledReason ?? "不可用"))
    }
}

struct PiboMossSecondaryButton: View {
    let title: String
    var isEnabled = true
    var onDark = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: PiboMoss.Control.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: PiboMoss.Radius.control, style: .continuous)
                        .fill(onDark ? PiboMoss.Color.cameraControl : .clear)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: PiboMoss.Radius.control, style: .continuous)
                        .strokeBorder(
                            onDark ? PiboMoss.Color.cameraHairline : PiboMoss.Color.hairline.opacity(0.70),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var foreground: SwiftUI.Color {
        guard isEnabled else { return PiboMoss.Color.disabledInk }
        return onDark ? PiboMoss.Color.onDarkPrimary : PiboMoss.Color.forestInk
    }
}

struct PiboMossSkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14

    var body: some View {
        Capsule()
            .fill(PiboMoss.Color.hairline.opacity(0.52))
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

struct PiboMossInlineNotice: View {
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: LP.Spacing.m) {
                VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                    Text(title)
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(PiboMoss.Color.forestInk)
                    Text(detail)
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(PiboMoss.Color.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let actionTitle {
                    Text(actionTitle)
                        .lpText(LP.Typography.c1Medium)
                        .foregroundStyle(PiboMoss.Color.foundationTeal)
                }
            }
            .padding(.horizontal, LP.Spacing.l)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                RoundedRectangle(cornerRadius: PiboMoss.Radius.media, style: .continuous)
                    .fill(PiboMoss.Color.sheetMoss.opacity(0.94))
            )
            .overlay {
                RoundedRectangle(cornerRadius: PiboMoss.Radius.media, style: .continuous)
                    .strokeBorder(PiboMoss.Color.hairline.opacity(0.68), lineWidth: 1)
            }
            .shadow(color: SwiftUI.Color(hex: 0x17342B, alpha: 0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

#if os(iOS)
private struct PiboMossSheetBackground: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(PiboMoss.Color.sheetMoss.opacity(0.88))
    }
}

extension View {
    /// Standard Moss Glass sheet treatment. Native sheet presentation keeps the
    /// forest spatially present while this surface supplies the shared tint,
    /// corner, and type scaling rules.
    func piboMossSheet(detents: Set<PresentationDetent>) -> some View {
        presentationDetents(detents)
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(PiboMoss.Radius.sheet)
            .presentationBackground { PiboMossSheetBackground() }
            .presentationBackgroundInteraction(.enabled)
            .lpDynamicTypeScaling()
    }
}
#endif
