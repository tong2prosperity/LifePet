import PiboCore

extension PixelWorldLook {
    init(scene: PiboCoreDayScene, season: PiboCoreDaySeason = .summer, snow: Bool = false,
         wind: Int = 0, trailFrom: PiboCoreDayScene = .clearing, trailTo: PiboCoreDayScene = .clearing) {
        self.scene = Int(scene.rawValue)
        self.season = Int(season.rawValue)
        self.snow = snow
        self.wind = wind
        self.trailFrom = Int(trailFrom.rawValue)
        self.trailTo = Int(trailTo.rawValue)
    }

}
