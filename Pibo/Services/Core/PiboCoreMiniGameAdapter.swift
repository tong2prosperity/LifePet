import PiboCore

enum PiboCoreMiniGameAdapter {
    static func stars(score: Int, kind: MiniGameKind) -> Int {
        PiboCoreMiniGameScoring.stars(score: score, kind: coreKind(kind))
    }

    static func petals(score: Int, kind: MiniGameKind) -> Int {
        PiboCoreMiniGameScoring.petals(score: score, kind: coreKind(kind))
    }

    private static func coreKind(_ kind: MiniGameKind) -> PiboCoreMiniGameKind {
        switch kind {
        case .walkDoodle: .walkDoodle
        case .huarongRoad: .huarongRoad
        case .stepLights: .stepLights
        case .bellSquat: .bellSquat
        case .memoryMatrix: .memoryMatrix
        case .mistBreath: .mistBreath
        case .breathFloat: .breathFloat
        case .dualNBack: .dualNBack
        case .mirrorPetals: .mirrorPetals
        case .speedMatch: .speedMatch
        case .trainThought: .trainThought
        case .petDetective: .petDetective
        case .flowerMerge: .flowerMerge
        case .potStack: .potStack
        case .rhythmTap: .rhythmTap
        case .waterTiming: .waterTiming
        case .piboRunner: .piboRunner
        case .idleGarden: .idleGarden
        }
    }
}
