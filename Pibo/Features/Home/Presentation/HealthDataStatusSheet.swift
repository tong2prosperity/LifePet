import SwiftUI
import UIKit

/// Persistent repair surface for `dataUnknown` and recoverable HealthKit
/// interruptions. It reports only facts the platform can actually know.
struct HealthDataStatusSheet: View {
    @Environment(HealthDataService.self) private var health
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: LP.Spacing.l) {
                Image(systemName: statusIcon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(LP.Content.accent)
                    .frame(width: 56, height: 56)
                    .background(LP.Fill.bgContainer, in: Circle())
                    .accessibilityHidden(true)

                Text(statusTitle)
                    .lpText(LP.Typography.uiH5)
                    .foregroundStyle(LP.Content.primary)
                    .accessibilityAddTraits(.isHeader)

                Text(statusMessage)
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(LP.Content.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if case .temporarilyInterrupted(let lastReadableAt) = health.dataAvailability,
                   let lastReadableAt {
                    Text(AppLocalization.format(
                        "上次成功读取：%@",
                        lastReadableAt.formatted(date: .abbreviated, time: .shortened)
                    ))
                    .lpText(LP.Typography.b4Regular)
                    .foregroundStyle(LP.Content.tertiary)
                }

                Spacer(minLength: LP.Spacing.m)

                if let actionLabel {
                    Button(action: runPrimaryAction) {
                        HStack(spacing: LP.Spacing.s) {
                            if isWorking { ProgressView().tint(LP.Fill.foundationOnAccent) }
                            Text(actionLabel)
                        }
                        .lpText(LP.Typography.b1Medium)
                        .foregroundStyle(LP.Fill.foundationOnAccent)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                                .fill(LP.Fill.foundationAccent)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                }
            }
            .padding(.horizontal, LP.Spacing.xl)
            .padding(.top, LP.Spacing.xl)
            .padding(.bottom, LP.Spacing.l)
            .background(LP.Fill.bgSurface.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalization.text("关闭")) { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var statusIcon: String {
        switch health.dataAvailability {
        case .unavailable: "heart.slash"
        case .needsAuthorization: "heart.text.clipboard"
        case .checking: "arrow.trianglehead.2.clockwise.rotate.90"
        case .noReadableData: "waveform.path.ecg.rectangle"
        case .available: "checkmark.circle"
        case .temporarilyInterrupted: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        }
    }

    private var statusTitle: String {
        switch health.dataAvailability {
        case .unavailable: AppLocalization.text("这台设备无法提供健康数据")
        case .needsAuthorization: AppLocalization.text("需要允许读取健康数据")
        case .checking: AppLocalization.text("正在检查健康数据")
        case .noReadableData: AppLocalization.text("暂时没有可读取的记录")
        case .available: AppLocalization.text("健康数据已经恢复")
        case .temporarilyInterrupted: AppLocalization.text("健康数据同步暂时中断")
        }
    }

    private var statusMessage: String {
        switch health.dataAvailability {
        case .unavailable:
            AppLocalization.text("Pibo 会保持安全状态，不会因为缺少数据扣除 bo 或推断你的健康情况。")
        case .needsAuthorization:
            AppLocalization.text("允许读取睡眠、步数或锻炼中的任意一种后，Pibo 才能根据真实记录判断状态。")
        case .checking:
            AppLocalization.text("Pibo 正在确认最近是否有可读取的睡眠、步数或锻炼记录。")
        case .noReadableData:
            AppLocalization.text("HealthKit 不会告诉 App 具体关闭了哪个读取开关。请检查权限，或等待设备同步第一条记录。")
        case .available:
            AppLocalization.text("已经重新读取到记录，Pibo 会自动回到由真实数据决定的状态。")
        case .temporarilyInterrupted:
            AppLocalization.text("已有状态会保留，不会被当作低健康。你可以现在重试；后续同步到达时也会自动恢复。")
        }
    }

    private var actionLabel: String? {
        switch health.dataAvailability {
        case .needsAuthorization: AppLocalization.text("允许读取健康数据")
        case .noReadableData: AppLocalization.text("打开设置")
        case .temporarilyInterrupted: AppLocalization.text("重新检查")
        case .available: AppLocalization.text("完成")
        case .checking, .unavailable: nil
        }
    }

    private func runPrimaryAction() {
        switch health.dataAvailability {
        case .needsAuthorization:
            isWorking = true
            Task { @MainActor in
                await health.requestAuthorization()
                isWorking = false
            }
        case .noReadableData:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        case .temporarilyInterrupted:
            isWorking = true
            Task { @MainActor in
                await health.reconcile()
                isWorking = false
            }
        case .available:
            dismiss()
        case .checking, .unavailable:
            break
        }
    }
}
