import Foundation
import AVFAudio
import PiboCore
import SwiftUI
import UIKit

/// A full-screen overlay over the live forest. The forest remains mounted so
/// preview and reveal use one continuous spatial model instead of navigating
/// to an unrelated store page.
struct BoUnlockOverlay: View {
    let stageCommands: PiboStageCommandController
    let onDismiss: () -> Void

    @Environment(BoLedgerStore.self) private var ledger
    @Environment(OrnamentUnlockStore.self) private var unlocks
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PiboPersistenceKeys.Defaults.ambientSoundEnabled) private var soundEnabled = true

    @State private var flow = OrnamentUnlockFlowCoordinator()
    @State private var sound = OrnamentUnlockSoundService()
    @State private var dictionaryExpanded: PiboOrnament.ID?
    @State private var artworkGlobalFrames: [PiboOrnament.ID: CGRect] = [:]
    @State private var overlayGlobalFrame: CGRect = .zero
    @State private var pendingUnlockConfirmation: PiboOrnament.ID?
    @AccessibilityFocusState private var headingFocused: Bool

    /// The first-version forest presents one concrete next goal instead of a
    /// store-like catalogue. Once everything is awake, keep the last owned item
    /// inspectable rather than exposing an empty overlay.
    private var ornaments: [PiboOrnament] {
        if let selectedID = flow.selectedID,
           let selected = PiboOrnament.ornament(selectedID) {
            return [selected]
        }
        if let next = unlocks.nextLocked { return [next] }
        if let lastOwned = PiboOrnament.ordered.last(where: { unlocks.isUnlocked($0.id) }) {
            return [lastOwned]
        }
        return PiboOrnament.ordered.first.map { [$0] } ?? []
    }
    private var selectedID: PiboOrnament.ID {
        flow.selectedID ?? unlocks.nextLocked?.id ?? ornaments.last!.id
    }

    private var isPreviewingPlacement: Bool { flow.previewedID != nil }
    private var contentOpacity: Double {
        if isPreviewingPlacement { return 0.18 }
        if case .dismissing = flow.phase { return 0 }
        if case .returning = flow.phase { return 0 }
        return 1
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LP.Fill.bgSurface
                    .opacity(isPreviewingPlacement ? 0.10 : 0.90)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())

                VStack(spacing: 0) {
                    header
                    balanceHeader
                    ornamentList
                    footer
                }
                .opacity(contentOpacity)
                .allowsHitTesting(!isPreviewingPlacement && !isReturning)

                if let id = flow.returningID,
                   let ornament = PiboOrnament.ornament(id) {
                    travellingArtwork(ornament)
                }

                if isPreviewingPlacement {
                    placementPreviewHint
                }
            }
            .onPreferenceChange(OrnamentArtworkFrameKey.self) { artworkGlobalFrames = $0 }
            .onAppear { overlayGlobalFrame = geometry.frame(in: .global) }
            .onChange(of: geometry.frame(in: .global)) { _, frame in
                overlayGlobalFrame = frame
            }
            .accessibilityAddTraits(.isModal)
            .task { present() }
            .onChange(of: selectedID) { _, id in
                stageCommands.setOrnamentConstructionMode(enabled: true, selected: id)
            }
            .onChange(of: flow.previewedID) { _, id in
                stageCommands.setOrnamentPlacementPreview(id)
            }
            .onChange(of: soundEnabled) { _, _ in updateSoundEnabled() }
            .onChange(of: reduceMotion) { _, _ in updateSoundEnabled() }
            .onChange(of: scenePhase) { _, phase in handleScenePhase(phase) }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) {
                sound.handleInterruption($0)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: AVAudioSession.silenceSecondaryAudioHintNotification
            )) {
                sound.handleSecondaryAudioHint($0)
            }
            .task(id: materializationTaskID) {
                await finishMaterializationIfNeeded()
            }
            .onDisappear {
                flow.dispose()
                sound.stop()
                stageCommands.cancelOrnamentPresentation()
            }
            .confirmationDialog(
                unlockConfirmationTitle,
                isPresented: Binding(
                    get: { pendingUnlockConfirmation != nil },
                    set: { if !$0 { pendingUnlockConfirmation = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let id = pendingUnlockConfirmation,
                   let ornament = PiboOrnament.ornament(id) {
                    Button(AppLocalization.format("唤醒%@ · %d bo", ornament.localizedName, ornament.cost)) {
                        pendingUnlockConfirmation = nil
                        commit(id, input: "tap_confirmation")
                    }
                }
                Button(AppLocalization.text("取消"), role: .cancel) {
                    pendingUnlockConfirmation = nil
                }
            }
        }
    }

    private var isReturning: Bool {
        if case .returning = flow.phase { return true }
        return false
    }

    private var header: some View {
        ZStack {
            Text(AppLocalization.text("下一件共同物件"))
                .lpText(LP.Typography.b1Medium)
                .foregroundStyle(LP.Content.primary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)

            HStack {
                Button(action: dismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(LP.Content.primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(flow.isBusy)
                .accessibilityLabel(AppLocalization.text("返回森林"))
                Spacer()
            }
        }
        .frame(height: 52)
        .padding(.horizontal, LP.Spacing.m)
        .padding(.top, LP.Spacing.s)
    }

    private var balanceHeader: some View {
        HStack(spacing: LP.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.text("可以唤醒"))
                    .lpText(LP.Typography.b4Medium)
                    .foregroundStyle(LP.Content.tertiary)
                Text(AppLocalization.text("投入 bo 后，它会留在森林里"))
                    .lpText(LP.Typography.b3Regular)
                    .foregroundStyle(LP.Content.secondary)
            }
            Spacer(minLength: LP.Spacing.s)
            HStack(spacing: LP.Spacing.xs) {
                PiboBoGlyph()
                    .frame(width: 24, height: 34)
                    .accessibilityHidden(true)
                Text(AppLocalization.format("%d bo", ledger.availableBo))
                    .lpText(LP.Typography.b1Medium)
                    .foregroundStyle(LP.Content.accent)
                    .contentTransition(.numericText())
                    .monospacedDigit()
            }
            .padding(.horizontal, LP.Spacing.m)
            .frame(minHeight: 44)
            .background(Capsule().fill(LP.Fill.bgContainer.opacity(0.94)))
            .overlay(Capsule().strokeBorder(LP.Border.secondary, lineWidth: LP.BorderWidth.hair))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppLocalization.format("当前可投入 %d bo", ledger.availableBo))
        }
        .padding(.horizontal, LP.Spacing.xl)
        .padding(.bottom, LP.Spacing.l)
    }

    private var ornamentList: some View {
        ScrollView {
            LazyVStack(spacing: LP.Spacing.m) {
                ForEach(ornaments) { ornament in
                    ornamentRow(ornament)
                }
            }
            .padding(.horizontal, LP.Spacing.xl)
            .padding(.bottom, LP.Spacing.xl)
        }
        .scrollDisabled(flow.isBusy || isPreviewingPlacement)
        .disabled(flow.isBusy)
    }

    private func ornamentRow(_ ornament: PiboOrnament) -> some View {
        let selected = selectedID == ornament.id
        return HStack(alignment: .top, spacing: LP.Spacing.m) {
            progressNode(for: ornament)
                .padding(.top, selected ? 34 : 26)
            Group {
                if selected {
                    expandedCard(ornament)
                } else {
                    collapsedCard(ornament)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func progressNode(for ornament: PiboOrnament) -> some View {
        let owned = unlocks.isUnlocked(ornament.id)
        let current = unlocks.nextLocked?.id == ornament.id
        return ZStack {
            Circle()
                .fill(owned ? LP.Fill.foundationAccent : LP.Fill.bgContainer)
                .frame(width: 22, height: 22)
                .overlay {
                    Circle().strokeBorder(
                        current ? LP.Fill.foundationAccent : LP.Border.primary,
                        lineWidth: current ? 3 : 1
                    )
                }
            if owned {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LP.Fill.foundationOnAccent)
            } else if current {
                Circle().fill(LP.Fill.foundationAccent).frame(width: 6, height: 6)
            }
        }
        .frame(width: 22, height: 22)
        .background(alignment: .top) {
            if ornament.id != ornaments.last?.id {
                Rectangle()
                    .fill(LP.Border.secondary)
                    .frame(width: 1.5, height: selectedID == ornament.id ? 420 : 96)
                    .offset(y: 22)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progressAccessibilityLabel(ornament))
    }

    private func collapsedCard(_ ornament: PiboOrnament) -> some View {
        Button {
            Analytics.track(.boUnlockItemSelect, screen: "bo_unlock", [
                "item": .string(ornament.id.rawValue),
                "item_state": .string(itemStateName(ornament)),
            ])
            withAnimation(reduceMotion ? nil : .timingCurve(0.65, 0, 0.35, 1, duration: 0.24)) {
                flow.select(ornament.id)
            }
        } label: {
            HStack(spacing: LP.Spacing.l) {
                OrnamentArtwork(ornament: ornament, locked: !unlocks.isUnlocked(ornament.id))
                    .frame(width: 64, height: 72)
                VStack(alignment: .leading, spacing: LP.Spacing.xs) {
                    Text(ornament.localizedName)
                        .lpText(LP.Typography.b1Medium)
                        .foregroundStyle(LP.Content.primary)
                    Text(capability(for: ornament.id))
                        .lpText(LP.Typography.b4Regular)
                        .foregroundStyle(LP.Content.secondary)
                        .lineLimit(2)
                    Text(AppLocalization.format("%d bo", ornament.cost))
                        .lpText(LP.Typography.b4Medium)
                        .foregroundStyle(LP.Content.accent)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LP.Content.tertiary)
            }
            .padding(LP.Spacing.l)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(cardBackground(radius: 18))
        .accessibilityHint(AppLocalization.text("展开物件详情"))
    }

    private func expandedCard(_ ornament: PiboOrnament) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.l) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: LP.Spacing.m) {
                    artwork(ornament).frame(maxWidth: .infinity)
                    titleAndCost(ornament)
                }
            } else {
                HStack(alignment: .top, spacing: LP.Spacing.l) {
                    artwork(ornament)
                        .frame(width: 126, height: 142)
                    titleAndCost(ornament)
                }
            }

            VStack(alignment: .leading, spacing: LP.Spacing.s) {
                Text(AppLocalization.text("唤醒后 Pibo 会"))
                    .lpText(LP.Typography.b4Medium)
                    .foregroundStyle(LP.Content.accent)

                ForEach(capabilityDetails(for: ornament.id), id: \.self) { detail in
                    Label(detail, systemImage: "checkmark.circle.fill")
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(LP.Content.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(permissionNote(for: ornament.id))
                    .lpText(LP.Typography.b4Regular)
                    .foregroundStyle(LP.Content.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(LP.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LP.Fill.bgSurfaceSecondary.opacity(0.70))
            )

            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.20)) {
                    dictionaryExpanded = dictionaryExpanded == ornament.id ? nil : ornament.id
                }
            } label: {
                HStack {
                    Text(AppLocalization.text("Pibo 词典记录"))
                        .lpText(LP.Typography.b4Medium)
                    Spacer()
                    Image(systemName: dictionaryExpanded == ornament.id ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(LP.Content.secondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(dictionaryExpanded == ornament.id
                                ? AppLocalization.text("已展开")
                                : AppLocalization.text("已折叠"))

            if dictionaryExpanded == ornament.id {
                Text(ornament.localizedEntry)
                    .lpText(LP.Typography.b4Regular)
                    .foregroundStyle(LP.Content.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            if let message = flow.message {
                Label(message, systemImage: "info.circle")
                    .lpText(LP.Typography.b4Medium)
                    .foregroundStyle(LP.Content.secondary)
            }
        }
        .padding(LP.Spacing.l)
        .background(cardBackground(radius: 22))
    }

    private func artwork(_ ornament: PiboOrnament) -> some View {
        OrnamentMaterializationArtwork(
            ornament: ornament,
            locked: !unlocks.isUnlocked(ornament.id),
            isMaterializing: isMaterializing(ornament.id),
            reduceMotion: reduceMotion
        )
            .frame(width: dynamicTypeSize.isAccessibilitySize ? 160 : 126,
                   height: dynamicTypeSize.isAccessibilitySize ? 160 : 142)
            .opacity(flow.returningID == ornament.id ? 0 : 1)
            .contentShape(Rectangle())
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: OrnamentArtworkFrameKey.self,
                        value: [ornament.id: proxy.frame(in: .global)]
                    )
                }
            }
            .onLongPressGesture(
                minimumDuration: 0.18,
                maximumDistance: 12,
                pressing: { pressing in
                    if !pressing { flow.endPlacementPreview() }
                },
                perform: {
                    flow.beginPlacementPreview(ornament.id)
                    Analytics.track(.boUnlockPlacementPreview, screen: "bo_unlock", [
                        "item": .string(ornament.id.rawValue),
                        "input": .string("touch"),
                    ])
                }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppLocalization.format("预览%@在森林中的位置", ornament.localizedName))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: AppLocalization.text("预览位置")) {
                flow.beginPlacementPreview(ornament.id)
                Analytics.track(.boUnlockPlacementPreview, screen: "bo_unlock", [
                    "item": .string(ornament.id.rawValue),
                    "input": .string("accessibility"),
                ])
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    flow.endPlacementPreview()
                }
            }
    }

    private func titleAndCost(_ ornament: PiboOrnament) -> some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text(ornament.localizedName)
                .lpText(LP.Typography.uiH5)
                .foregroundStyle(LP.Content.primary)
                .accessibilityAddTraits(.isHeader)
            Text(AppLocalization.format("需要 %d bo · 当前可投入 %d bo", ornament.cost, ledger.availableBo))
                .lpText(LP.Typography.b1Medium)
                .foregroundStyle(LP.Content.accent)
                .monospacedDigit()
            Text(itemStatusText(ornament))
                .lpText(LP.Typography.b4Medium)
                .foregroundStyle(LP.Content.tertiary)
            Text(AppLocalization.text("按住插画，可以先看它会留在哪里。"))
                .lpText(LP.Typography.b4Regular)
                .foregroundStyle(LP.Content.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: LP.Spacing.s) {
            LPDashedRule(color: LP.Border.secondary, lineWidth: 1, dash: [4, 4])
            footerControl
        }
        .padding(.horizontal, LP.Spacing.xl)
        .padding(.top, LP.Spacing.m)
        .padding(.bottom, LP.Spacing.l)
        .background(LP.Fill.bgSurface.opacity(0.96))
    }

    @ViewBuilder
    private var footerControl: some View {
        let ornament = PiboOrnament.ornament(selectedID)!
        if isMaterializing(ornament.id) {
            HStack(spacing: LP.Spacing.m) {
                PiboBoGlyph()
                    .frame(width: 17, height: 24)
                    .accessibilityHidden(true)
                Text(AppLocalization.text("正在唤醒物件"))
                    .lpText(LP.Typography.b1Medium)
                    .foregroundStyle(LP.Content.accent)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, LP.Spacing.l)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LP.Fill.foundationAccent.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(LP.Fill.foundationAccent.opacity(0.42), lineWidth: 1)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppLocalization.format("正在唤醒%@", ornament.localizedName))
        } else if flow.phase == .success(ornament.id) {
            Button {
                returnToForest(ornament)
            } label: {
                Text(AppLocalization.text("回到森林"))
                    .lpText(LP.Typography.b1Medium)
                    .foregroundStyle(LP.Fill.foundationOnAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LP.Fill.foundationAccent)
                    )
            }
            .buttonStyle(.plain)
        } else if unlocks.state(ornament.id, balance: ledger.availableBo) == .purchasable {
            Button {
                pendingUnlockConfirmation = ornament.id
            } label: {
                Text(AppLocalization.format("唤醒%@", ornament.localizedName))
                    .lpText(LP.Typography.b1Medium)
                    .foregroundStyle(LP.Fill.foundationOnAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LP.Fill.foundationAccent)
                    )
            }
            .buttonStyle(.plain)
        } else {
            Text(footerUnavailableText(ornament))
                .lpText(LP.Typography.b1Medium)
                .foregroundStyle(LP.Content.tertiary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LP.Fill.bgSurfaceSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(LP.Border.secondary, lineWidth: LP.BorderWidth.hair)
                )
                .accessibilityLabel(footerUnavailableText(ornament))
        }
    }

    private var placementPreviewHint: some View {
        VStack {
            Spacer()
            Text(AppLocalization.text("松开即可回到物件说明"))
                .lpText(LP.Typography.b4Medium)
                .foregroundStyle(LP.Content.primary)
                .padding(.horizontal, LP.Spacing.l)
                .frame(minHeight: 44)
                .background(Capsule().fill(LP.Fill.bgPop.opacity(0.94)))
                .overlay(Capsule().strokeBorder(LP.Border.secondary, lineWidth: 1))
                .padding(.bottom, 40)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func travellingArtwork(_ ornament: PiboOrnament) -> some View {
        let frame = interpolatedTravelFrame
        return OrnamentArtwork(ornament: ornament, locked: false)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var interpolatedTravelFrame: CGRect {
        let p = flow.travelProgress
        let source = flow.travelSource
        let target = flow.travelTarget
        return CGRect(
            x: source.minX + (target.minX - source.minX) * p,
            y: source.minY + (target.minY - source.minY) * p,
            width: source.width + (target.width - source.width) * p,
            height: source.height + (target.height - source.height) * p
        )
    }

    private func cardBackground(radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LP.Fill.bgContainer.opacity(0.96))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LP.Border.secondary, lineWidth: LP.BorderWidth.hair)
            )
    }

    private func present() {
        let id = unlocks.nextLocked?.id ?? ornaments.last!.id
        unlocks.markUnlockGuideSeen()
        updateSoundEnabled()
        sound.refreshExternalAudioSuppression()
        stageCommands.setOrnamentConstructionMode(enabled: true, selected: id)
        flow.present(selected: id, reduceMotion: reduceMotion)
        DispatchQueue.main.async { headingFocused = true }
    }

    private func dismiss() {
        flow.beginDismiss(reduceMotion: reduceMotion) {
            stageCommands.cancelOrnamentPresentation()
            flow.finishDismissal()
            onDismiss()
        }
    }

    private func commit(_ id: PiboOrnament.ID, input: String) {
        guard flow.beginCommit(id), let ornament = PiboOrnament.ornament(id) else { return }
        Analytics.track(.boUnlockAttempt, screen: "bo_unlock", [
            "item": .string(id.rawValue),
            "cost": .int(ornament.cost),
            "input": .string(input),
        ])
        stageCommands.prepareOrnamentReveal(id)
        LPHaptics.confirm()

        switch unlocks.purchase(id, using: ledger) {
        case .purchased:
            sound.playInvestment()
            flow.beginMaterializing(id)
            Analytics.track(.boUnlock, screen: "bo_unlock", [
                "ornament": .string(id.rawValue),
                "cost": .int(ornament.cost),
                "remaining_balance": .int(ledger.availableBo),
                "input": .string(input),
            ])
        case .alreadyOwned:
            stageCommands.completeOrnamentReveal(id)
            flow.completeMaterialization(id)
        case .insufficientBalance:
            reportFailure(id, reason: "insufficient_balance", text: footerUnavailableText(ornament))
        case .prerequisiteMissing:
            reportFailure(id, reason: "prerequisite_missing", text: footerUnavailableText(ornament))
        case .unavailable:
            reportFailure(id, reason: "unavailable", text: AppLocalization.text("这件物件还不能唤醒。"))
        }
    }

    private func reportFailure(_ id: PiboOrnament.ID, reason: String, text: String) {
        stageCommands.completeOrnamentReveal(id)
        flow.showFailure(text, item: id)
        Analytics.track(.boUnlockFailed, screen: "bo_unlock", [
            "item": .string(id.rawValue),
            "reason": .string(reason),
        ])
    }

    private func returnToForest(_ ornament: PiboOrnament) {
        let fallback = CGRect(
            x: overlayGlobalFrame.minX + 150,
            y: overlayGlobalFrame.minY + 220,
            width: 96,
            height: 128
        )
        let sourceGlobal = artworkGlobalFrames[ornament.id] ?? fallback
        let targetGlobal = stageCommands.ornamentTargetFrame(ornament.id) ?? sourceGlobal
        let source = overlayLocalFrame(sourceGlobal)
        let target = overlayLocalFrame(targetGlobal)
        flow.beginReturn(
            ornament.id,
            source: source,
            target: target,
            reduceMotion: reduceMotion
        ) {
            stageCommands.completeOrnamentReveal(ornament.id)
            stageCommands.setOrnamentConstructionMode(enabled: false, selected: nil)
            Analytics.track(.boUnlockReturn, screen: "bo_unlock", [
                "item": .string(ornament.id.rawValue),
                "motion_mode": .string(reduceMotion ? "reduced" : "full"),
            ])
            flow.finishDismissal()
            onDismiss()
        }
    }

    @MainActor
    private func finishMaterializationIfNeeded() async {
        guard case .materializing(let id) = flow.phase,
              let ornament = PiboOrnament.ornament(id) else { return }
        if !reduceMotion {
            do {
                try await Task.sleep(for: OrnamentUnlockMotion.materializationDuration)
            } catch {
                return
            }
        }
        guard !Task.isCancelled, flow.phase == .materializing(id) else { return }
        flow.completeMaterialization(id)
        sound.playCompletion(for: id)
        LPHaptics.success()
        AccessibilityNotification.Announcement(
            AppLocalization.format("%@已唤醒", ornament.localizedName)
        ).post()
    }

    private func overlayLocalFrame(_ globalFrame: CGRect) -> CGRect {
        globalFrame.offsetBy(dx: -overlayGlobalFrame.minX, dy: -overlayGlobalFrame.minY)
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        guard phase != .active else {
            sound.refreshExternalAudioSuppression()
            return
        }
        sound.stop()
        if let id = flow.prepareForBackground() {
            stageCommands.completeOrnamentReveal(id)
        }
        stageCommands.setOrnamentPlacementPreview(nil)
    }

    private func updateSoundEnabled() {
        sound.setEnabled(soundEnabled && !reduceMotion)
    }

    private func capability(for id: PiboOrnament.ID) -> String {
        switch id {
        case .hammock: AppLocalization.text("Pibo 可以在这里睡觉和休息")
        case .chime: AppLocalization.text("Walk Doodle")
        case .statusObserver: AppLocalization.text("查看恢复状态")
        case .lantern: AppLocalization.text("魔法点灯")
        }
    }

    private func capabilityDetails(for id: PiboOrnament.ID) -> [String] {
        switch id {
        case .hammock:
            [
                AppLocalization.text("Pibo 睡觉或疲惫时可以使用吊床"),
                AppLocalization.text("睡眠回顾：在 App 内查看最近一次睡眠"),
                AppLocalization.text("睡醒通知：每天睡醒后提醒你查看"),
            ]
        case .chime:
            [
                AppLocalization.text("Walk Doodle：记录步行路线，把移动过程留成地图上的线条"),
            ]
        case .statusObserver:
            [AppLocalization.text("恢复状态：根据已授权的原始记录等待数据或校准")]
        case .lantern:
            [AppLocalization.text("魔法点灯：亲手点亮森林里的铃兰灯")]
        }
    }

    private func permissionNote(for id: PiboOrnament.ID) -> String {
        switch id {
        case .hammock:
            AppLocalization.text("需要已授权的睡眠记录。拒绝通知权限仍可在 App 内查看睡眠回顾。")
        case .chime:
            AppLocalization.text("精确定位权限只会在开始 Walk Doodle 时请求。")
        case .statusObserver:
            AppLocalization.text("只使用已授权的原始健康记录。数据不足时等待或校准，不生成恢复分数。")
        case .lantern:
            AppLocalization.text("无需新增权限。")
        }
    }

    private func itemStatusText(_ ornament: PiboOrnament) -> String {
        if isMaterializing(ornament.id) { return AppLocalization.text("正在唤醒") }
        if unlocks.isUnlocked(ornament.id) { return AppLocalization.text("已经唤醒") }
        if unlocks.nextLocked?.id == ornament.id { return AppLocalization.text("当前可以唤醒") }
        return AppLocalization.text("需要先完成前面的物件")
    }

    private func footerUnavailableText(_ ornament: PiboOrnament) -> String {
        switch unlocks.state(ornament.id, balance: ledger.availableBo) {
        case .owned:
            AppLocalization.text("已经唤醒")
        case .unavailable:
            AppLocalization.text("还不能唤醒")
        case .eligible:
            if let prerequisiteID = PiboOrnament.coreDefinition(ornament.id).prerequisiteID,
               let prerequisite = PiboOrnament.ordered.first(where: { $0.id.coreID == prerequisiteID }),
               !unlocks.isUnlocked(prerequisite.id) {
                AppLocalization.format("先唤醒「%@」", prerequisite.localizedName)
            } else {
                AppLocalization.format("还差 %d bo", max(0, ornament.cost - ledger.availableBo))
            }
        case .purchasable:
            AppLocalization.format("唤醒%@", ornament.localizedName)
        }
    }

    private func progressAccessibilityLabel(_ ornament: PiboOrnament) -> String {
        if unlocks.isUnlocked(ornament.id) {
            return AppLocalization.format("%@，已经唤醒", ornament.localizedName)
        }
        if unlocks.nextLocked?.id == ornament.id {
            return AppLocalization.format("%@，当前目标", ornament.localizedName)
        }
        return AppLocalization.format("%@，之后可以唤醒", ornament.localizedName)
    }

    private func itemStateName(_ ornament: PiboOrnament) -> String {
        if unlocks.isUnlocked(ornament.id) { return "owned" }
        if unlocks.nextLocked?.id == ornament.id { return "current" }
        return "future"
    }

    private func isMaterializing(_ id: PiboOrnament.ID) -> Bool {
        flow.phase == .materializing(id)
    }

    private var materializationTaskID: String {
        guard case .materializing(let id) = flow.phase else { return "idle" }
        return "\(id.rawValue):\(reduceMotion)"
    }

    private var unlockConfirmationTitle: String {
        guard let id = pendingUnlockConfirmation,
              let ornament = PiboOrnament.ornament(id) else {
            return AppLocalization.text("确认唤醒")
        }
        return AppLocalization.format("使用 %d bo 唤醒「%@」？", ornament.cost, ornament.localizedName)
    }
}

struct OrnamentArtwork: View {
    let ornament: PiboOrnament
    let locked: Bool

    var body: some View {
        Group {
            if let image = UIImage(named: ornament.thumbnailImage) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .saturation(locked ? 0.42 : 1)
                    .opacity(locked ? 0.62 : 1)
            } else {
                Image(systemName: "leaf")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(LP.Content.tertiary)
            }
        }
    }
}

/// Turns the committed transaction into a visible construction story without
/// inventing a second art style. The approved flat artwork is revealed in an
/// object-specific structural order; once layered masters arrive, the same
/// stage contract can drive those assets without changing purchase state.
private struct OrnamentMaterializationArtwork: View {
    let ornament: PiboOrnament
    let locked: Bool
    let isMaterializing: Bool
    let reduceMotion: Bool

    @State private var stage = 0
    @State private var flightProgress: CGFloat = 0

    private var regions: [OrnamentBuildRegion] {
        OrnamentBuildRegion.plan(for: ornament.id)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if !isMaterializing || reduceMotion {
                    OrnamentArtwork(ornament: ornament, locked: locked)
                } else {
                    OrnamentConstructionGuide()
                        .opacity(stage >= 1 && stage < 5 ? 1 : 0)

                    ForEach(Array(regions.enumerated()), id: \.element.id) { index, region in
                        OrnamentArtwork(ornament: ornament, locked: false)
                            .mask(OrnamentRegionMask(region: region))
                            .offset(
                                x: stage >= index + 2 ? 0 : region.entryOffset.width,
                                y: stage >= index + 2 ? 0 : region.entryOffset.height
                            )
                            .opacity(stage >= index + 2 ? 1 : 0)
                    }

                    InvestmentFlightPath()
                        .trim(
                            from: max(0, flightProgress - 0.32),
                            to: flightProgress
                        )
                        .stroke(
                            LP.Fill.foundationAccent.opacity(0.34),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                        )
                        .opacity(stage == 1 ? 1 : 0)

                    let point = InvestmentFlightPath.point(
                        at: flightProgress,
                        in: proxy.size
                    )
                    PiboBoGlyph()
                        .frame(width: 15, height: 22)
                        .position(point)
                        .scaleEffect(1 - flightProgress * 0.22)
                        .opacity(stage == 1 ? 1 : 0)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .task(id: materializationTaskID) {
            await runMaterializationIfNeeded()
        }
        .accessibilityHidden(true)
    }

    @MainActor
    private func runMaterializationIfNeeded() async {
        resetMotionState()
        guard isMaterializing, !reduceMotion else { return }

        withAnimation(.easeOut(duration: 0.12)) {
            stage = 1
        }
        withAnimation(OrnamentUnlockMotion.constructionAnimation(
            duration: OrnamentUnlockMotion.flightDuration
        )) {
            flightProgress = 1
        }
        guard await wait(.milliseconds(OrnamentUnlockMotion.flightMilliseconds)) else { return }

        for nextStage in 2...4 {
            withAnimation(OrnamentUnlockMotion.constructionAnimation(
                duration: OrnamentUnlockMotion.layerDuration
            )) {
                stage = nextStage
            }
            guard await wait(.milliseconds(OrnamentUnlockMotion.layerMilliseconds)) else { return }
        }

        withAnimation(.easeOut(duration: OrnamentUnlockMotion.confirmationDuration)) {
            stage = 5
        }
    }

    @MainActor
    private func resetMotionState() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            stage = 0
            flightProgress = 0
        }
    }

    private func wait(_ duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private var materializationTaskID: String {
        "\(isMaterializing):\(reduceMotion)"
    }
}

private struct OrnamentRegionMask: View {
    let region: OrnamentBuildRegion

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .frame(
                    width: proxy.size.width * region.frame.width,
                    height: proxy.size.height * region.frame.height
                )
                .offset(
                    x: proxy.size.width * region.frame.minX,
                    y: proxy.size.height * region.frame.minY
                )
        }
    }
}

private struct OrnamentConstructionGuide: View {
    var body: some View {
        Canvas { context, size in
            let color = LP.Fill.foundationAccent.opacity(0.22)
            let frame = Path(
                roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3),
                cornerRadius: 12
            )
            context.stroke(
                frame,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )

            var crosshair = Path()
            crosshair.move(to: CGPoint(x: size.width * 0.5, y: 8))
            crosshair.addLine(to: CGPoint(x: size.width * 0.5, y: size.height - 8))
            crosshair.move(to: CGPoint(x: 8, y: size.height * 0.5))
            crosshair.addLine(to: CGPoint(x: size.width - 8, y: size.height * 0.5))
            context.stroke(crosshair, with: .color(color.opacity(0.65)), lineWidth: 0.75)
        }
    }
}

private struct OrnamentArtworkFrameKey: PreferenceKey {
    static var defaultValue: [PiboOrnament.ID: CGRect] = [:]

    static func reduce(
        value: inout [PiboOrnament.ID: CGRect],
        nextValue: () -> [PiboOrnament.ID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

#Preview {
    ZStack {
        LP.Colorful.green50.ignoresSafeArea()
        BoUnlockOverlay(stageCommands: PiboStageCommandController(), onDismiss: {})
            .environment(BoLedgerStore())
            .environment(OrnamentUnlockStore())
    }
}
