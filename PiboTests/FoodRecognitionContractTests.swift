import Foundation
import Testing
@testable import Pibo

@MainActor
struct FoodRecognitionContractTests {
    @Test func decodesCurrentServerGateObservationAndEstimateSchema() throws {
        let data = Data(#"""
        {
          "is_food": true,
          "food_presence_confidence": 0.97,
          "dish_name": "番茄炒蛋",
          "total_calories": 320,
          "confidence": 0.84,
          "items": [{
            "name": "番茄炒蛋",
            "quantity": "1盘（约260 g）",
            "estimated_grams": 260,
            "calories": 320
          }],
          "protein_g": 18,
          "carb_g": 20,
          "fat_g": 16,
          "assumptions": ["按一盘家常份量估算"],
          "note": "烹调油用量无法从照片确认。",
          "pibo_observation": "红色和黄色放在了一起。"
        }
        """#.utf8)

        let analysis = try JSONCoding.decoder.decode(FoodAnalysis.self, from: data)
        #expect(analysis.isFood == true)
        #expect(analysis.foodPresenceConfidence == 0.97)
        #expect(analysis.items.first?.estimatedGrams == 260)
        #expect(analysis.piboObservation == "红色和黄色放在了一起。")
    }

    @Test func legacyHistoryAnalysisStillDecodesWithoutGateFields() throws {
        let data = Data(#"""
        {
          "dishName": "旧餐食",
          "totalCalories": 400,
          "items": []
        }
        """#.utf8)

        let analysis = try JSONDecoder().decode(FoodAnalysis.self, from: data)
        #expect(analysis.isFood == nil)
        #expect(analysis.piboObservation == nil)
        #expect(analysis.totalCalories == 400)
    }
}
