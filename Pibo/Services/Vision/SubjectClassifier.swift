import UIKit
import Vision

/// 识图 — best-effort recognition of the photo's main subject using Vision's
/// on-device taxonomy classifier (`VNClassifyImageRequest`, no network, no
/// custom model). Product stance: 识别错了也没有大碍 — the label is flavor for
/// the 拍立得/今日记录 cards, never a gate.
///
/// `nonisolated` like `SubjectCutout` so callers run it off the main actor.
enum SubjectClassifier {

    /// Classify the image and return a display label — 中文 when the taxonomy
    /// identifier is in our mapping, the prettified English identifier
    /// otherwise, `nil` when nothing clears the precision filter.
    nonisolated static func classify(_ image: UIImage) -> String? {
        guard let cg = image.cgImage else { return nil }
        let handler = VNImageRequestHandler(
            cgImage: cg, orientation: SubjectCutout.cgOrientation(image.imageOrientation))
        let request = VNClassifyImageRequest()
        do {
            try handler.perform([request])
            guard let results = request.results else { return nil }
            // Keep observations the model itself rates precise; results arrive
            // sorted by confidence.
            let confident = results.filter { $0.hasMinimumRecall(0.01, forPrecision: 0.9) }
            guard !confident.isEmpty else { return nil }
            // Prefer the most confident label we can show in 中文; otherwise
            // fall back to the top identifier as-is.
            if let mapped = confident.lazy.compactMap({ Self.zhNames[$0.identifier.lowercased()] }).first {
                return mapped
            }
            return prettify(confident[0].identifier)
        } catch {
            return nil
        }
    }

    private nonisolated static func prettify(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: " ")
    }

    /// 中文 display names for common taxonomy identifiers — food-leaning (the
    /// camera is 记录饮食) plus everyday subjects. Unmapped identifiers show in
    /// English, which is fine for the MVP.
    private nonisolated static let zhNames: [String: String] = [
        // 主食 / 餐点
        "food": "食物", "snack": "零食", "dessert": "甜点", "breakfast": "早餐",
        "bread": "面包", "toast": "吐司", "pastry": "酥点", "croissant": "牛角包",
        "sandwich": "三明治", "hamburger": "汉堡", "pizza": "披萨", "hot_dog": "热狗",
        "noodles": "面条", "pasta": "意面", "spaghetti": "意面", "ramen": "拉面",
        "rice": "米饭", "fried_rice": "炒饭", "sushi": "寿司", "dumpling": "饺子",
        "soup": "汤", "salad": "沙拉", "taco": "塔可", "burrito": "卷饼",
        "french_fries": "薯条", "egg": "鸡蛋", "omelette": "煎蛋",
        // 肉 / 海鲜
        "meat": "肉", "steak": "牛排", "chicken": "鸡肉", "beef": "牛肉",
        "pork": "猪肉", "fish": "鱼", "seafood": "海鲜", "shrimp": "虾",
        // 甜品 / 零食
        "cake": "蛋糕", "cupcake": "纸杯蛋糕", "cookie": "曲奇", "biscuit": "饼干",
        "chocolate": "巧克力", "candy": "糖果", "ice_cream": "冰淇淋",
        "doughnut": "甜甜圈", "donut": "甜甜圈", "pancake": "松饼", "waffle": "华夫饼",
        "pie": "派", "pudding": "布丁",
        // 水果 / 蔬菜
        "fruit": "水果", "apple": "苹果", "banana": "香蕉", "orange": "橙子",
        "grape": "葡萄", "strawberry": "草莓", "watermelon": "西瓜", "peach": "桃子",
        "mango": "芒果", "lemon": "柠檬", "cherry": "樱桃", "pineapple": "菠萝",
        "vegetable": "蔬菜", "carrot": "胡萝卜", "tomato": "番茄", "potato": "土豆",
        "corn": "玉米", "broccoli": "西兰花", "cucumber": "黄瓜", "mushroom": "蘑菇",
        // 饮品
        "beverage": "饮品", "drink": "饮品", "coffee": "咖啡", "espresso": "浓缩咖啡",
        "latte": "拿铁", "tea": "茶", "juice": "果汁", "milk": "牛奶",
        "milkshake": "奶昔", "smoothie": "冰沙", "soda": "汽水", "beer": "啤酒",
        "wine": "葡萄酒", "cocktail": "鸡尾酒",
        // 餐具 / 容器
        "cup": "杯子", "mug": "马克杯", "bottle": "瓶子", "bowl": "碗",
        "plate": "盘子", "spoon": "勺子", "fork": "叉子", "chopsticks": "筷子",
        // 生活常见主体
        "flower": "花", "plant": "植物", "tree": "树", "leaf": "叶子",
        "dog": "狗", "cat": "猫", "bird": "鸟", "rabbit": "兔子",
        "person": "人", "people": "人", "hand": "手",
        "cellphone": "手机", "mobile_phone": "手机", "laptop": "笔记本电脑",
        "computer": "电脑", "keyboard": "键盘", "book": "书", "toy": "玩具",
        "shoe": "鞋", "bag": "包", "watch": "手表", "glasses": "眼镜",
    ]
}
