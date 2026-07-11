import SwiftUI

enum MiniGameCategory: String, CaseIterable, Identifiable {
    case movement
    case breath
    case cognition
    case puzzle
    case arcade

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movement: return "动一动"
        case .breath: return "呼吸"
        case .cognition: return "脑内小题"
        case .puzzle: return "解谜"
        case .arcade: return "消遣"
        }
    }
}

enum MiniGameKind: String, CaseIterable, Identifiable {
    case walkDoodle
    case huarongRoad
    case stepLights
    case bellSquat
    case memoryMatrix
    case mistBreath
    case breathFloat
    case dualNBack
    case mirrorPetals
    case speedMatch
    case trainThought
    case petDetective
    case flowerMerge
    case potStack
    case rhythmTap
    case waterTiming
    case piboRunner
    case idleGarden

    var id: String { rawValue }

    static let sections: [(category: MiniGameCategory, games: [MiniGameKind])] = [
        (.movement, [.walkDoodle, .stepLights, .bellSquat, .mirrorPetals]),
        (.breath, [.breathFloat]),
        (.cognition, [.memoryMatrix, .speedMatch, .trainThought, .petDetective]),
        (.puzzle, [.huarongRoad]),
        (.arcade, [.flowerMerge, .potStack, .rhythmTap, .piboRunner])
    ]

    /// Product-removed experiments. Keeping their cases temporarily lets old
    /// best-score/default keys decode safely, but they are absent from the
    /// catalog and cannot be launched through the debug shortcut.
    var isAvailable: Bool {
        switch self {
        case .mistBreath, .dualNBack, .waterTiming, .idleGarden:
            return false
        default:
            return true
        }
    }

    var title: String {
        switch self {
        case .walkDoodle: return "地图涂鸦"
        case .huarongRoad: return "华容道"
        case .stepLights: return "原地踏步点灯"
        case .bellSquat: return "摇花铃"
        case .memoryMatrix: return "记忆矩阵"
        case .mistBreath: return "吹散迷雾"
        case .breathFloat: return "Pibo 漂浮"
        case .dualNBack: return "双线闪回"
        case .mirrorPetals: return "镜前接花瓣"
        case .speedMatch: return "闪回对照"
        case .trainThought: return "思绪列车"
        case .petDetective: return "Pet Detective"
        case .flowerMerge: return "合成花朵"
        case .potStack: return "叠花盆"
        case .rhythmTap: return "节奏点击"
        case .waterTiming: return "浇水计时"
        case .piboRunner: return "宠物跑酷"
        case .idleGarden: return "放置花田"
        }
    }

    var subtitle: String {
        switch self {
        case .walkDoodle: return "出门走一幅画"
        case .huarongRoad: return "拖动彩色方块，把 Pibo 送到出口"
        case .stepLights: return "左右脚交替，踩亮萤火"
        case .bellSquat: return "下蹲起身，让花铃响起来"
        case .memoryMatrix: return "记住亮起的位置，再点回来"
        case .mistBreath: return "长按呼气，把雾慢慢吹开"
        case .breathFloat: return "跟呼吸节拍穿过光环"
        case .dualNBack: return "同时追踪位置和符号是否重复"
        case .mirrorPetals: return "移动镜中影子接花瓣"
        case .speedMatch: return "判断符号与颜色是否和上一张完全一致"
        case .trainThought: return "把同色小列车送进站"
        case .petDetective: return "绕开石头，找最短路线"
        case .flowerMerge: return "落花合并，越长越大"
        case .potStack: return "看准时机，把花盆叠高"
        case .rhythmTap: return "跟乱码节拍点亮花"
        case .waterTiming: return "露珠经过花心时点下"
        case .piboRunner: return "跳过石块，带花往前跑"
        case .idleGarden: return "回来收花，没有惩罚"
        }
    }

    var tag: String {
        switch self {
        case .walkDoodle: return "运动能量"
        case .huarongRoad: return "解谜"
        case .mistBreath, .breathFloat: return "即时放松"
        case .stepLights, .bellSquat, .mirrorPetals: return "微运动"
        case .memoryMatrix, .dualNBack, .speedMatch, .trainThought, .petDetective: return "练这个挑战"
        case .flowerMerge, .potStack, .rhythmTap, .waterTiming, .piboRunner: return "短局"
        case .idleGarden: return "零惩罚"
        }
    }

    var tint: Color {
        switch self {
        case .walkDoodle, .idleGarden:
            return LP.Fill.foundationAccent
        case .huarongRoad, .memoryMatrix, .dualNBack:
            return LP.Colorful.purple500
        case .stepLights, .bellSquat, .piboRunner:
            return LP.Colorful.orange500
        case .mistBreath, .breathFloat, .mirrorPetals, .waterTiming:
            return LP.Colorful.cyan500
        case .speedMatch, .rhythmTap:
            return LP.Colorful.red500
        case .trainThought, .petDetective:
            return LP.Colorful.blue500
        case .flowerMerge, .potStack:
            return LP.Colorful.lime500
        }
    }
}

#if DEBUG
extension MiniGameKind {
    static func debugRequestedLaunchGame(arguments: [String] = ProcessInfo.processInfo.arguments) -> MiniGameKind? {
        for argument in arguments where argument.hasPrefix("-PiboOpenMiniGame=") {
            let rawValue = String(argument.dropFirst("-PiboOpenMiniGame=".count))
            if let game = MiniGameKind(rawValue: rawValue), game.isAvailable { return game }
        }

        guard let index = arguments.firstIndex(of: "-PiboOpenMiniGame"),
              arguments.indices.contains(index + 1)
        else { return nil }

        guard let game = MiniGameKind(rawValue: arguments[index + 1]), game.isAvailable else { return nil }
        return game
    }
}
#endif
