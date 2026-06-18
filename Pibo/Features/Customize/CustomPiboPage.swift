import SwiftUI

// MARK: - 自定义 Pibo 页 (CustomPiboPage)
//
// The full customization editor: a live `PiboPortraitView` preview on top, a
// scrollable control panel below. Every control binds straight to
// `store.appearance` (the component-separated DNA), so edits render instantly
// and persist (UserDefaults JSON via `PetStateStore`). Reached from the 历史
// 数据页's bottom tab bar (`HistoryFloorView`).
//
// Because the parts are separated, each section here maps 1:1 to a component:
// 颜色 / 眼睛 / 眉毛 / 鼻子 / 身子 / 手脚 / 头顶植物.

struct CustomPiboPage: View {
    @Environment(PetStateStore.self) private var store
    @State private var showResetConfirm = false

    var body: some View {
        @Bindable var store = store
        let a = $store.appearance

        VStack(spacing: 0) {
            previewHeader(a, current: store.appearance)
            ScrollView(showsIndicators: false) {
                VStack(spacing: LP.Spacing.m) {
                    colorSection(a)
                    eyesSection(a, eyeColor: store.appearance.palette.eye.color)
                    browsSection(a, browColor: store.appearance.palette.brow.color)
                    noseSection(a, noseColor: store.appearance.palette.nose.color)
                    bodySection(a)
                    limbsSection(a)
                    plantSection(a, plantColor: store.appearance.palette.plant.color)
                    Color.clear.frame(height: LP.Spacing.l)   // tab bar clearance handled by safeAreaInset
                }
                .padding(.horizontal, LP.Spacing.l)
                .padding(.top, LP.Spacing.m)
            }
        }
        .padding(.top, 88)   // clear the #E8EEF1 二楼 ceiling crown (drawn on top)
        .confirmationDialog("恢复默认外形？", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("恢复默认", role: .destructive) {
                LPHaptics.tap()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    store.appearance = .default
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: Preview + presets + actions

    private func previewHeader(_ a: Binding<PiboAppearance>, current: PiboAppearance) -> some View {
        VStack(spacing: LP.Spacing.m) {
            ZStack {
                // Soft cool-grey canvas (like the Figma backdrop) so the white
                // Pibo and its pale parts read clearly.
                RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                    .fill(LP.Fill.bgSurfaceSecondary)
                    .overlay(RoundedRectangle(cornerRadius: LP.Radius.xl, style: .continuous)
                        .stroke(LP.Border.tertiary, lineWidth: 1))
                PiboPortraitView(appearance: current)
                    .padding(LP.Spacing.s)
            }
            .frame(height: 200)
            .padding(.horizontal, LP.Spacing.l)

            presetRow(a, current: current)

            HStack(spacing: LP.Spacing.s) {
                actionButton("随机一只", system: "dice") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        a.wrappedValue = .random()
                    }
                }
                actionButton("恢复默认", system: "arrow.counterclockwise") {
                    showResetConfirm = true
                }
            }
            .padding(.horizontal, LP.Spacing.l)
        }
    }

    private func presetRow(_ a: Binding<PiboAppearance>, current: PiboAppearance) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LP.Spacing.s) {
                ForEach(PiboAppearance.presets, id: \.name) { preset in
                    let selected = preset.appearance == current
                    Button {
                        LPHaptics.tap()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            a.wrappedValue = preset.appearance
                        }
                    } label: {
                        VStack(spacing: 4) {
                            PiboPortraitView(appearance: preset.appearance, showShadow: false)
                                .frame(width: 46, height: 56)
                                .background(LP.Fill.bgSurfaceSecondary,
                                            in: RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous))
                            Text(preset.name).lpText(LP.Typography.c1Regular)
                                .foregroundStyle(selected ? LP.Content.primary : LP.Content.tertiary)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                            .fill(selected ? LP.Fill.foundationAccent.opacity(0.12) : .clear))
                        .overlay(RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous)
                            .stroke(selected ? LP.Fill.foundationAccent : LP.Border.tertiary,
                                    lineWidth: selected ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, LP.Spacing.l)
        }
    }

    private func actionButton(_ title: String, system: String, action: @escaping () -> Void) -> some View {
        Button {
            LPHaptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: system).font(.system(size: 13, weight: .medium))
                Text(title).lpText(LP.Typography.b4Medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LP.Spacing.s)
            .foregroundStyle(LP.Content.secondary)
            .background(RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous).fill(LP.Fill.bgContainer))
            .overlay(RoundedRectangle(cornerRadius: LP.Radius.m, style: .continuous).stroke(LP.Border.tertiary, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Sections

    private func colorSection(_ a: Binding<PiboAppearance>) -> some View {
        CustomizeSection(title: "颜色", systemImage: "paintpalette") {
            ColorRow(title: "身体", color: a.palette.body)
            ColorRow(title: "轮廓", color: a.palette.outline)
            ColorRow(title: "眼睛", color: a.palette.eye)
            ColorRow(title: "眉毛", color: a.palette.brow)
            ColorRow(title: "鼻子 / 腮", color: a.palette.nose)
            ColorRow(title: "头顶植物", color: a.palette.plant)
            ColorRow(title: "手 / 腿", color: a.palette.limb)
        }
    }

    private func eyesSection(_ a: Binding<PiboAppearance>, eyeColor: Color) -> some View {
        CustomizeSection(title: "眼睛（大椭圆）", systemImage: "eye") {
            ChipPicker(title: "形状", options: PiboEyeShape.allCases, selection: a.eyes.shape,
                       label: { $0.label },
                       icon: { AnyView(PiboEye(shape: $0, size: CGSize(width: 30, height: 18), color: eyeColor)) })
            LabeledSlider(title: "眼间距", value: a.eyes.spacing, range: 0.15...0.5,
                          display: { String(format: "%.2f", $0) })
            LabeledSlider(title: "大小", value: a.eyes.size, range: 0.6...1.8,
                          display: { String(format: "%.2f×", $0) })
            LabeledSlider(title: "高低", value: a.eyes.height, range: 0.12...0.55,
                          display: { String(format: "%.2f", $0) })
            LabeledSlider(title: "倾斜", value: a.eyes.tilt, range: -30...30,
                          display: { String(format: "%.0f°", $0) })
        }
    }

    private func browsSection(_ a: Binding<PiboAppearance>, browColor: Color) -> some View {
        CustomizeSection(title: "眉毛（小圆）", systemImage: "eyebrow") {
            ChipPicker(title: "形状", options: PiboBrowShape.allCases, selection: a.brows.shape,
                       label: { $0.label },
                       icon: { AnyView(PiboBrow(shape: $0, size: CGSize(width: 16, height: 12), color: browColor, angle: 16)) })
            LabeledSlider(title: "大小", value: a.brows.size, range: 0.5...2.0,
                          display: { String(format: "%.2f×", $0) })
            LabeledSlider(title: "高低", value: a.brows.lift, range: 0...0.4,
                          display: { String(format: "%.2f", $0) })
            LabeledSlider(title: "间距", value: a.brows.spacing, range: 0...0.45,
                          display: { String(format: "%.2f", $0) })
            LabeledSlider(title: "斜挑角度", value: a.brows.angle, range: -25...25,
                          display: { String(format: "%.0f°", $0) })
        }
    }

    private func noseSection(_ a: Binding<PiboAppearance>, noseColor: Color) -> some View {
        CustomizeSection(title: "鼻子 / 腮", systemImage: "nose") {
            ChipPicker(title: "形状", options: PiboNoseShape.allCases, selection: a.nose.shape,
                       label: { $0.label },
                       icon: { AnyView(PiboNose(shape: $0, size: CGSize(width: 28, height: 16), color: noseColor)) })
            LabeledSlider(title: "大小", value: a.nose.size, range: 0.6...1.5,
                          display: { String(format: "%.2f×", $0) })
            LabeledSlider(title: "高低", value: a.nose.drop, range: 0.5...0.95,
                          display: { String(format: "%.2f", $0) })
        }
    }

    private func bodySection(_ a: Binding<PiboAppearance>) -> some View {
        CustomizeSection(title: "身子", systemImage: "oval.portrait") {
            LabeledSlider(title: "身宽", value: a.body.widthScale, range: 0.85...1.15,
                          display: { String(format: "%.2f×", $0) })
            LabeledSlider(title: "高瘦", value: a.body.aspect, range: 0.9...1.2,
                          display: { String(format: "%.2f", $0) })
        }
    }

    private func limbsSection(_ a: Binding<PiboAppearance>) -> some View {
        CustomizeSection(title: "手 / 腿", systemImage: "hand.raised") {
            ToggleRow(title: "显示手", isOn: a.arms.visible)
            LabeledSlider(title: "手长", value: a.arms.length, range: 0.6...1.4,
                          display: { String(format: "%.2f×", $0) })
            LabeledSlider(title: "手位置", value: a.arms.drop, range: 0...0.4,
                          display: { String(format: "%.2f", $0) })
            Divider().overlay(LP.Separator.secondary)
            ToggleRow(title: "显示腿", isOn: a.legs.visible)
            LabeledSlider(title: "脚间距", value: a.legs.spread, range: 0.5...1.5,
                          display: { String(format: "%.2f×", $0) })
            LabeledSlider(title: "脚大小", value: a.legs.length, range: 0.6...1.4,
                          display: { String(format: "%.2f×", $0) })
        }
    }

    private func plantSection(_ a: Binding<PiboAppearance>, plantColor: Color) -> some View {
        CustomizeSection(title: "头顶植物", systemImage: "leaf") {
            ChipPicker(title: "种类", options: PiboPlantKind.allCases, selection: a.plant.kind,
                       label: { $0.label },
                       icon: { AnyView(PiboPlant(kind: $0, size: 24, color: plantColor)) })
            LabeledSlider(title: "大小", value: a.plant.size, range: 0.6...1.6,
                          display: { String(format: "%.2f×", $0) })
            LabeledSlider(title: "摆动", value: a.plant.sway, range: -25...25,
                          display: { String(format: "%.0f°", $0) })
        }
    }
}

// MARK: - Randomizer

private extension PiboAppearance {
    /// A tasteful random remix — varies shapes, geometry, and the plant color
    /// while keeping the body soft. Powers the 「随机一只」 button.
    static func random() -> PiboAppearance {
        var a = PiboAppearance.default
        a.eyes.shape = PiboEyeShape.allCases.randomElement() ?? .ellipse
        a.eyes.spacing = .random(in: 0.26...0.44)
        a.eyes.size = .random(in: 0.85...1.5)
        a.eyes.height = .random(in: 0.20...0.42)
        a.eyes.tilt = .random(in: -24...24)
        a.brows.shape = PiboBrowShape.allCases.randomElement() ?? .dot
        a.brows.lift = .random(in: 0.0...0.18)
        a.brows.spacing = .random(in: 0.10...0.40)
        a.brows.angle = .random(in: -20...20)
        a.brows.size = .random(in: 0.7...1.6)
        a.nose.shape = PiboNoseShape.allCases.randomElement() ?? .doubleBump
        a.body.widthScale = .random(in: 0.9...1.12)
        a.body.aspect = .random(in: 0.92...1.15)
        a.plant.kind = PiboPlantKind.allCases.randomElement() ?? .singleLeaf
        a.plant.sway = .random(in: -16...16)
        a.plant.size = .random(in: 0.8...1.3)

        let plantHues: [UInt32] = [0x3E8E5A, 0xF3A9BE, 0x6FB98F, 0xF2C14E, 0x9B7EDE, 0xE08A5B]
        a.palette.plant = PiboColor(hex: plantHues.randomElement() ?? 0x3E8E5A)
        // Occasionally tint the body a soft pastel.
        if Bool.random() {
            let bodyTints: [UInt32] = [0xFFFFFF, 0xE7F0DA, 0xFDEAF0, 0xEAF1FA, 0xFBF1DE]
            let tint = bodyTints.randomElement() ?? 0xFFFFFF
            a.palette.body = PiboColor(hex: tint)
            a.palette.limb = PiboColor(hex: tint)
        }
        return a
    }
}

#Preview {
    CustomPiboPage()
        .environment(PetStateStore(demoMode: true))
        .background(LP.Fill.bgSurface.ignoresSafeArea())
}
