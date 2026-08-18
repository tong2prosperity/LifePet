import SwiftUI
import UIKit

/// Persistent repair surface for `dataUnknown` and recoverable HealthKit
/// interruptions. It reports only facts the platform can actually know and
/// preserves the last trusted state while recovery is pending.
struct HealthDataStatusSheet: View {
    @Environment(HealthDataService.self) private var health
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LP.Spacing.l) {
                PiboMossSheetHandle()
                    .frame(maxWidth: .infinity)

                Text(AppLocalization.text("健康数据"))
                    .lpText(LP.Typography.c1Medium)
                    .foregroundStyle(PiboMoss.Color.secondaryInk)

                HStack(alignment: .top, spacing: LP.Spacing.m) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(PiboMoss.Color.foundationTeal)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(PiboMoss.Color.raisedNeutral.opacity(0.62)))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: LP.Spacing.s) {
                        Text(statusTitle)
                            .lpText(LP.Typography.uiH4)
                            .foregroundStyle(PiboMoss.Color.forestInk)
                            .accessibilityAddTraits(.isHeader)

                        Text(statusMessage)
                            .lpText(LP.Typography.b3Regular)
                            .foregroundStyle(PiboMoss.Color.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if case .temporarilyInterrupted(let lastReadableAt) = health.dataAvailability,
                   let lastReadableAt {
                    HStack(spacing: LP.Spacing.s) {
                        Image(systemName: "clock")
                            .foregroundStyle(PiboMoss.Color.foundationTeal)
                        Text(AppLocalization.format(
                            "上次成功读取 · %@",
                            lastReadableAt.formatted(date: .abbreviated, time: .shortened)
                        ))
                        .lpText(LP.Typography.b4Medium)
                        .foregroundStyle(PiboMoss.Color.forestInk)
                    }
                    .padding(.horizontal, LP.Spacing.m)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: PiboMoss.Radius.control)
                            .fill(PiboMoss.Color.raisedNeutral.opacity(0.56))
                    )
                }

                Text(integrityMessage)
                    .lpText(LP.Typography.c1Regular)
                    .foregroundStyle(PiboMoss.Color.secondaryInk)
                    .padding(LP.Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: PiboMoss.Radius.control)
                            .fill(PiboMoss.Color.raisedNeutral.opacity(0.48))
                    )

                if let actionLabel {
                    PiboMossPrimaryButton(
                        title: actionLabel,
                        disabledReason: AppLocalization.text("正在检查"),
                        isEnabled: !isWorking,
                        action: runPrimaryAction
                    )
                }

                if shouldOfferSettings {
                    PiboMossSecondaryButton(
                        title: AppLocalization.text("打开设置"),
                        isEnabled: !isWorking,
                        action: openSettings
                    )
                } else {
                    PiboMossSecondaryButton(
                        title: AppLocalization.text("稍后"),
                        isEnabled: !isWorking,
                        action: { dismiss() }
                    )
                }
            }
            .padding(.horizontal, LP.Spacing.xl)
            .padding(.top, LP.Spacing.m)
            .padding(.bottom, LP.Spacing.xxl)
        }
        .piboMossSheet(detents: [.fraction(0.64), .large])
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
        case .needsAuthorization: AppLocalization.text("还没有获得访问权限")
        case .checking: AppLocalization.text("正在检查健康数据")
        case .noReadableData: AppLocalization.text("暂时没有可读取的记录")
        case .available: AppLocalization.text("健康数据已经恢复")
        case .temporarilyInterrupted: AppLocalization.text("同步暂时中断")
        }
    }

    private var statusMessage: String {
        switch health.dataAvailability {
        case .unavailable:
            AppLocalization.text("Pibo 会保持安全状态，等待以后可以读取的数据。")
        case .needsAuthorization:
            AppLocalization.text("授权后，Pibo 会根据真实睡眠与活动改变状态。")
        case .checking:
            AppLocalization.text("正在确认最近是否有可读取的睡眠、步数或锻炼记录。")
        case .noReadableData:
            AppLocalization.text("HealthKit 不会说明具体关闭了哪个读取开关。请检查权限，或等待设备同步第一条记录。")
        case .available:
            AppLocalization.text("已经重新读取到记录，Pibo 会自动回到由真实数据决定的状态。")
        case .temporarilyInterrupted:
            AppLocalization.text("当前仍显示上次可信状态。恢复后会自动更新。")
        }
    }

    private var integrityMessage: String {
        switch health.dataAvailability {
        case .temporarilyInterrupted:
            AppLocalization.text("中断期间不会把缺失数据解释成低健康，也不会影响 bo。")
        default:
            AppLocalization.text("没有数据不会被当成低健康，也不会影响 bo。")
        }
    }

    private var actionLabel: String? {
        switch health.dataAvailability {
        case .needsAuthorization: AppLocalization.text("允许访问健康数据")
        case .temporarilyInterrupted: AppLocalization.text("重新检查")
        case .available: AppLocalization.text("完成")
        case .checking, .unavailable, .noReadableData: nil
        }
    }

    private var shouldOfferSettings: Bool {
        switch health.dataAvailability {
        case .noReadableData, .temporarilyInterrupted: true
        default: false
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
        case .temporarilyInterrupted:
            isWorking = true
            Task { @MainActor in
                await health.reconcile()
                isWorking = false
            }
        case .available:
            dismiss()
        case .checking, .unavailable, .noReadableData:
            break
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
