import SwiftUI

// MARK: - Reusable editor controls
//
// Small, design-system-styled building blocks for `CustomPiboPage`: a titled
// section card, a labeled slider, a color row, and a shape-chip picker. Kept
// separate so the page reads as "what's editable", not "how a slider looks".

/// Bind a SwiftUI `ColorPicker` straight to a `PiboColor` field.
extension Binding where Value == PiboColor {
    var asColor: Binding<Color> {
        Binding<Color>(
            get: { self.wrappedValue.color },
            set: { self.wrappedValue = PiboColor($0) }
        )
    }
}

/// A titled, bordered section card grouping related controls.
struct CustomizeSection<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.m) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
                }
                Text(title).lpText(LP.Typography.b4Medium)
            }
            .foregroundStyle(LP.Content.tertiary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LP.Spacing.l)
        .background(RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous).fill(LP.Fill.bgContainer))
        .overlay(RoundedRectangle(cornerRadius: LP.Radius.l, style: .continuous).stroke(LP.Border.tertiary, lineWidth: 1))
    }
}

/// A label + value readout over a slider.
struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 0
    /// Custom value formatter (e.g. "18°", "1.2×"). Defaults to 2-decimal.
    var display: (Double) -> String = { String(format: "%.2f", $0) }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                    .lpText(LP.Typography.b4Regular)
                    .foregroundStyle(LP.Content.secondary)
                Spacer()
                Text(display(value))
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(LP.Content.tertiary)
                    .monospacedDigit()
            }
            if step > 0 {
                Slider(value: $value, in: range, step: step).tint(LP.Fill.foundationAccent)
            } else {
                Slider(value: $value, in: range).tint(LP.Fill.foundationAccent)
            }
        }
    }
}

/// A label + native color well, bound to a `PiboColor`.
struct ColorRow: View {
    let title: String
    @Binding var color: PiboColor

    var body: some View {
        HStack {
            Circle()
                .fill(color.color)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(LP.Border.secondary, lineWidth: 1))
            Text(title)
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(LP.Content.secondary)
            Spacer()
            ColorPicker("", selection: $color.asColor, supportsOpacity: false)
                .labelsHidden()
        }
    }
}

/// A toggle row (手 / 腿 显隐).
struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(LP.Content.secondary)
        }
        .tint(LP.Fill.foundationAccent)
    }
}

/// Horizontal chips for choosing one enum case. Each chip can show a tiny live
/// component preview (so the eye/brow/plant chips show the actual shape).
struct ChipPicker<T: Hashable>: View {
    let title: String
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    var icon: ((T) -> AnyView)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(LP.Content.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { opt in
                        chip(opt)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func chip(_ opt: T) -> some View {
        let selected = opt == selection
        return Button {
            LPHaptics.tap()
            selection = opt
        } label: {
            VStack(spacing: 5) {
                if let icon {
                    icon(opt)
                        .frame(width: 36, height: 26)
                }
                Text(label(opt))
                    .lpText(LP.Typography.c1Regular)
            }
            .frame(minWidth: 48)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                    .fill(selected ? LP.Fill.foundationAccent.opacity(0.14) : LP.Fill.bgSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                    .stroke(selected ? LP.Fill.foundationAccent : LP.Border.tertiary,
                            lineWidth: selected ? 1.5 : 1)
            )
            .foregroundStyle(selected ? LP.Content.primary : LP.Content.secondary)
        }
        .buttonStyle(.plain)
    }
}
