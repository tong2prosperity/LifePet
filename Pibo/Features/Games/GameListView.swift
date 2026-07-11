import SwiftUI

// MARK: - 小游戏列表 (游戏场)

struct GameListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// A finished walk doodle — `HomeView` persists it + grants 运动能量.
    var onWalkDoodleSaved: (WalkDoodleResult) -> Void

    @State private var selectedGame: MiniGameKind?
    #if DEBUG
    @State private var debugOpenedGame = false
    #endif

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LP.Fill.bgSurfaceSecondary.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: LP.Spacing.xxl) {
                    header
                    ForEach(MiniGameKind.sections, id: \.category) { section in
                        gameSection(section.category, games: section.games)
                    }
                    Color.clear.frame(height: LP.Spacing.xxl)
                }
                .padding(.horizontal, LP.Spacing.xl)
                .padding(.top, 72)
            }

            closeButton
        }
        .lpDynamicTypeScaling()
        .accessibilityAddTraits(.isModal)
        .fullScreenCover(item: $selectedGame) { game in
            MiniGameHostView(kind: game, onWalkDoodleSaved: onWalkDoodleSaved)
        }
        .onAppear {
            Analytics.track(.gamesOpen, screen: "games")
            #if DEBUG
            if !debugOpenedGame, let debugGame = MiniGameKind.debugRequestedLaunchGame() {
                debugOpenedGame = true
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    selectedGame = debugGame
                }
            }
            #endif
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LP.Spacing.s) {
            Text(AppLocalization.text("游戏场"))
                .lpText(LP.Typography.b2Medium)
                .foregroundStyle(LP.Content.secondary)
            Text(AppLocalization.text("陪 Pibo 玩一局"))
                .lpText(LP.Typography.uiH4)
                .foregroundStyle(LP.Content.primary)
            Text("...别把我放进菜单里...快开始...啵")
                .lpText(LP.Typography.c1Regular)
                .foregroundStyle(LP.Content.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func gameSection(_ category: MiniGameCategory, games: [MiniGameKind]) -> some View {
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 154), spacing: LP.Spacing.m)]

        return VStack(alignment: .leading, spacing: LP.Spacing.m) {
            Text(AppLocalization.text(category.title))
                .lpText(LP.Typography.b3Medium)
                .foregroundStyle(LP.Content.tertiary)
                .padding(.horizontal, LP.Spacing.xs)

            LazyVGrid(columns: columns,
                      alignment: .leading,
                      spacing: LP.Spacing.m) {
                ForEach(games) { game in
                    gameCard(game)
                }
            }
        }
    }

    private func gameCard(_ game: MiniGameKind) -> some View {
        Button {
            LPHaptics.tap()
            Analytics.track(.miniGameStart, screen: "games", ["game": .string(game.rawValue)])
            selectedGame = game
        } label: {
            VStack(alignment: .leading, spacing: LP.Spacing.m) {
                HStack(alignment: .top, spacing: LP.Spacing.s) {
                    MiniGameKindBadgeAsset(kind: game)
                        .frame(width: 38, height: 38)
                    Spacer(minLength: 0)
                    Text(AppLocalization.text(game.tag))
                        .lpText(LP.Typography.c2Medium)
                        .foregroundStyle(game.tint)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppLocalization.text(game.title))
                        .lpText(LP.Typography.b3Medium)
                        .foregroundStyle(LP.Content.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
                    Text(AppLocalization.text(game.subtitle))
                        .lpText(LP.Typography.c1Regular)
                        .foregroundStyle(LP.Content.tertiary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(LP.Spacing.l)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                    .fill(LP.Fill.bgContainer)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LP.Radius.s, style: .continuous)
                    .strokeBorder(.white.opacity(0.55), lineWidth: LP.BorderWidth.hair)
            )
            .lpShadow(LP.Shadow.elevation1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.text("\(game.title)：\(game.subtitle)"))
        .accessibilityIdentifier("gameCard.\(game.rawValue)")
    }

    private var closeButton: some View {
        Button {
            LPHaptics.tap()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LP.Content.secondary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(LP.Fill.bgContainer))
                .lpShadow(LP.Shadow.elevation1)
        }
        .buttonStyle(.plain)
        .padding(.trailing, LP.Spacing.xl)
        .padding(.top, LP.Spacing.l)
        .accessibilityLabel(AppLocalization.text("关闭"))
        .accessibilityIdentifier("games.close")
    }
}

struct MiniGameHostView: View {
    let kind: MiniGameKind
    var onWalkDoodleSaved: (WalkDoodleResult) -> Void

    var body: some View {
        switch kind {
        case .walkDoodle:
            WalkDoodleView(onSaved: onWalkDoodleSaved)
        case .huarongRoad:
            HuarongRoadView()
        case .stepLights:
            StepLightsGameView()
        case .bellSquat:
            BellSquatGameView()
        case .memoryMatrix:
            MemoryMatrixGameView()
        case .mistBreath:
            MistBreathGameView()
        case .breathFloat:
            BreathFloatGameView()
        case .dualNBack:
            DualNBackGameView()
        case .mirrorPetals:
            MirrorPetalsGameView()
        case .speedMatch:
            SpeedMatchGameView()
        case .trainThought:
            TrainThoughtGameView()
        case .petDetective:
            PetDetectiveGameView()
        case .flowerMerge:
            FlowerMergeGameView()
        case .potStack:
            PotStackGameView()
        case .rhythmTap:
            RhythmTapGameView()
        case .waterTiming:
            WaterTimingGameView()
        case .piboRunner:
            PiboRunnerGameView()
        case .idleGarden:
            IdleGardenGameView()
        }
    }
}

#Preview {
    GameListView(onWalkDoodleSaved: { _ in })
}
