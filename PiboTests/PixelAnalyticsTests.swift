import Testing
@testable import Pibo

struct PixelAnalyticsTests {
    @Test func onlyDeclaredScalarPropertiesLeaveTheFacade() throws {
        let properties = try #require(Analytics.sanitizedProperties(.mealStickerTap, [
            "slot_index": 2, "is_fresh": true, "calories": 800, "photo_path": "/private/photo.png"
        ]))
        #expect(properties.count == 2)
        #expect(properties["calories"] == nil)
        #expect(Analytics.sanitizedProperties(.findDisplayToggle, ["item": "我的照片", "action": "display"])?.count == 1)
        #expect(Analytics.sanitizedProperties(.decorPurchased, ["cost": .double(.nan)])?.isEmpty == true)
        #expect(Analytics.sanitizedProperties(.pat, ["context": "tiredAwake"])?.isEmpty == true)
    }

    @Test func retiredActivitiesCannotReenterAnalytics() {
        for event in [Analytics.Event.walkDoodleStart, .walkDoodleSaved, .miniGameStart, .miniGameFinish, .gamesOpen, .membershipOpen, .purchase] {
            #expect(Analytics.sanitizedProperties(event, nil) == nil)
        }
    }
}
