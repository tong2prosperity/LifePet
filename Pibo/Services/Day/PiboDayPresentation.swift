import Foundation

// Display names for decision 058's semantic ids. Core returns ids only; names, and the
// order they appear in, live with the platform.
//
// Ported from HarmonyPibo `services/day/PiboDayPresentation.ets`.

private let FIND_NAMES: [String] = [
    "松果", "羽毛", "怪石头", "红叶", "橡果", "四叶草", "蒲公英", "蜗牛壳", "小树枝", "小蘑菇",
    "鹅卵石", "河贝壳", "蝉蜕", "冰凌", "雪团", "野莓", "花瓣", "鸟蛋壳", "银杏叶", "一瓶山顶的风",
    "云朵石", "一把松针", "麦穗", "玻璃石",
]
private let DESTINATION_NAMES: [String] = ["草坡", "松林", "河边", "山顶"]
private let SCENE_NAMES: [String] = ["林间空地", "小溪边", "山坡"]
private let SCENE_NOTES: [String] = [
    "吊床、风车和所有装饰都在这里。",
    "有能跳的石头、倒下的木头和不太理人的鱼。",
    "风很大，花很多，晚上星星最近。",
]

func piboFindName(_ item: Int) -> String {
    AppLocalization.text(FIND_NAMES.indices.contains(item) ? FIND_NAMES[item] : "")
}

func piboDestinationName(_ destination: Int) -> String {
    AppLocalization.text(DESTINATION_NAMES.indices.contains(destination) ? DESTINATION_NAMES[destination] : "")
}

func piboSceneName(_ scene: Int) -> String {
    AppLocalization.text(SCENE_NAMES.indices.contains(scene) ? SCENE_NAMES[scene] : "")
}

func piboSceneNote(_ scene: Int) -> String {
    AppLocalization.text(SCENE_NOTES.indices.contains(scene) ? SCENE_NOTES[scene] : "")
}

// Decision 060: the small fact line under a life echo's words. Qualitative only: what you
// did, never how much, and never a judgement.
private let ECHO_FACTS: [String] = [
    "", "你今天去跑步了", "你今天骑车了", "你今天去游泳了", "你今天练了瑜伽", "你今天做了高强度训练",
    "你今天出门走了一段", "你刚运动完", "你今天走了很多路", "你昨晚睡得不错", "昨晚的觉短了一点",
    "已经很晚了", "你刚吃过饭", "到饭点了", "你今天做了正念",
]

func piboEchoFact(_ echo: Int) -> String {
    AppLocalization.text(ECHO_FACTS.indices.contains(echo) ? ECHO_FACTS[echo] : "")
}
