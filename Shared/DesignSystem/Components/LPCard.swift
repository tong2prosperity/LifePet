import SwiftUI

/// A design-system card. Slots in top-to-bottom order:
///
/// - **label** — optional Mono kicker (e.g. "SLEEP · LAST NIGHT").
/// - **title** — optional H3 serif title.
/// - **header** — optional custom row that sits between the title and the body
///   (right-aligned pill, icon button, anything structured).
/// - **content** — the body. Free-form.
///
/// Two initializers. The full one takes a custom header builder; the convenience
/// (where `Header == EmptyView`) covers the common label + title + content case.
///
/// ```swift
/// LPCard(.coral, label: "RIGHT NOW", title: "它有点不舒服") {
///     Text("再观察一下").lpText(LP.Typography.body)
/// }
///
/// LPCard(
///     label: "TODAY",
///     header: { HStack { Spacer(); LPPill("v1.0") } },
///     content: { … }
/// )
/// ```
struct LPCard<Header: View, Content: View>: View {
    let variant: LP.CardVariant
    let label: String?
    let title: String?
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    init(
        _ variant: LP.CardVariant = .default,
        label: String? = nil,
        title: String? = nil,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.variant = variant
        self.label = label
        self.title = title
        self.header = header
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s2) {
            if let label {
                Text(label)
                    .lpText(LP.Typography.monoLabel)
                    .foregroundStyle(labelColor)
            }
            if let title {
                Text(title)
                    .lpText(LP.Typography.h3)
                    .foregroundStyle(LP.Colors.ink)
            }
            header()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lpCard(variant)
    }

    private var labelColor: Color {
        switch variant {
        case .coral: return LP.Colors.coral
        case .sage:  return LP.Colors.sage
        default:     return LP.Colors.muted
        }
    }
}

// MARK: - Header-less convenience

extension LPCard where Header == EmptyView {
    /// Most cards don't need a custom header row — this overload covers the
    /// common `label + title + content` case without forcing callers to pass
    /// `header: { EmptyView() }`.
    init(
        _ variant: LP.CardVariant = .default,
        label: String? = nil,
        title: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            variant,
            label: label,
            title: title,
            header: { EmptyView() },
            content: content
        )
    }
}

// MARK: - Previews

#Preview("Variants") {
    ScrollView {
        VStack(spacing: LP.Spacing.s4) {
            LPCard(label: "SLEEP · LAST NIGHT", title: "7h 12m") {
                Text("它醒来的时候，第一件事就是看看你有没有起床。")
                    .lpText(LP.Typography.serifBody)
                    .foregroundStyle(LP.Colors.ink2)
            }
            LPCard(.coral, label: "RIGHT NOW", title: "它有点不舒服") {
                Text("再观察一下，别让它自己扛着。")
                    .lpText(LP.Typography.body)
            }
            LPCard(.sage, label: "STREAK", title: "连续 5 天早睡") {
                Text("健康曲线在回升。")
                    .lpText(LP.Typography.body)
            }
            LPCard(.ghost, label: "COMING SOON", title: "邻居视角") {
                Text("v1.1 会解锁。")
                    .lpText(LP.Typography.caption)
                    .foregroundStyle(LP.Colors.muted)
            }
        }
        .padding(LP.Spacing.s5)
    }
    .lpPaper(.app)
}

#Preview("Custom header slot") {
    LPCard(
        label: "TODAY",
        header: {
            HStack {
                Text("昨晚你睡了 7 小时").lpText(LP.Typography.h3)
                Spacer()
                LPPill("v1.0", variant: .sage)
            }
        },
        content: {
            Text("具体细节。").lpText(LP.Typography.body)
        }
    )
    .padding(LP.Spacing.s5)
    .lpPaper(.app)
}
