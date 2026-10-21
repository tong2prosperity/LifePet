import CoreGraphics
import Foundation
import ImageIO
import Observation
import os
import UniformTypeIdentifiers

/// One evening's print. Kept only on this phone; sharing goes through the system sheet.
struct PolaroidShot: Codable, Equatable, Identifiable {
    var day: String
    var path: String
    var caption: String
    var takenAt: Double

    var id: String { "\(day)-\(Int(takenAt))" }
}

/// The daily pixel polaroid (decision 057's surprise layer): one print of the forest per
/// evening. Core decides when it is due; this store only prints, keeps and shares.
///
/// Ported from HarmonyPibo `services/growth/PolaroidStore.ets`. HarmonyOS writes through
/// `ImagePacker`; iOS draws the same paper frame into a bitmap and writes a PNG.
@MainActor
@Observable
final class PolaroidStore {
    static let defaultsKey = "pibo_growth_polaroid/shots.v1"
    /// Two months of evenings; older prints are removed with their files.
    static let keep = 60
    /// Whole-number upscale keeps every forest pixel square in the print.
    static let scale = 6
    static let margin = 36
    static let chin = 120

    private(set) var shots: [PolaroidShot] = []
    private(set) var revision = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let folder: URL

    init(defaults: UserDefaults = .standard, folder: URL? = nil) {
        self.defaults = defaults
        let base = (try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? URL.documentsDirectory
        self.folder = folder ?? base.appending(path: "polaroids", directoryHint: .isDirectory)
        restore(raw: defaults.string(forKey: Self.defaultsKey) ?? "")
    }

    func restore(raw: String) {
        shots = []
        if let data = raw.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([PolaroidShot].self, from: data) {
            shots = parsed.filter { !$0.day.isEmpty && !$0.path.isEmpty }
        }
        revision += 1
    }

    func takenToday(_ now: Date = .now) -> Bool {
        let today = growthDayKey(now)
        return shots.contains { $0.day == today }
    }

    var latest: PolaroidShot? { shots.first }

    /// Prints the snapshot with a paper border, saves it and records it as today's print.
    /// A failed write records nothing, so the moment can be retried later.
    @discardableResult
    func take(_ snapshot: PixelSnapshot, caption: String, now: Date = .now) -> PolaroidShot? {
        guard snapshot.width > 0, snapshot.height > 0 else { return nil }
        let day = growthDayKey(now)
        let stamp = Int(now.timeIntervalSince1970)
        let url = folder.appending(path: "\(day)-\(stamp).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Self.png(snapshot).write(to: url, options: .atomic)
        } catch {
            GrowthLog.growth.error("polaroid print failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        let shot = PolaroidShot(day: day, path: url.path, caption: caption,
                                takenAt: now.timeIntervalSince1970)
        shots = [shot] + shots.filter { $0.day != day }
        prune()
        persist()
        revision += 1
        GrowthLog.growth.info("polaroid taken day=\(day, privacy: .public)")
        return shot
    }

    func reset() {
        for shot in shots { remove(shot.path) }
        shots = []
        persist()
        revision += 1
    }

    // MARK: - Print

    /// Nearest-neighbour upscale onto paper: one scaled row is built per source row, then
    /// copied `scale` times, so the print costs a few hundred row copies.
    static func printRGBA(_ snapshot: PixelSnapshot) -> (width: Int, height: Int, rgba: [UInt8]) {
        let width = snapshot.width * scale + margin * 2
        let height = snapshot.height * scale + margin + chin
        var out = [UInt8](repeating: 0, count: width * height * 4)
        // Polaroid paper, #FFF8EC.
        for index in stride(from: 0, to: out.count, by: 4) {
            out[index] = 0xFF
            out[index + 1] = 0xF8
            out[index + 2] = 0xEC
            out[index + 3] = 0xFF
        }
        for y in 0..<snapshot.height {
            let sourceRow = y * snapshot.width
            for x in 0..<snapshot.width {
                let s = (sourceRow + x) * 4
                // Transparent stage pixels print as paper rather than black.
                let transparent = snapshot.rgba[s + 3] == 0
                let red = transparent ? 0xFF : snapshot.rgba[s]
                let green = transparent ? 0xF8 : snapshot.rgba[s + 1]
                let blue = transparent ? 0xEC : snapshot.rgba[s + 2]
                for copy in 0..<scale {
                    let row = margin + y * scale + copy
                    let base = (row * width + margin + x * scale) * 4
                    for step in 0..<scale {
                        let index = base + step * 4
                        out[index] = red
                        out[index + 1] = green
                        out[index + 2] = blue
                        out[index + 3] = 0xFF
                    }
                }
            }
        }
        return (width, height, out)
    }

    static func png(_ snapshot: PixelSnapshot) -> Data {
        let print = printRGBA(snapshot)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(print.rgba) as CFData),
              let image = CGImage(width: print.width, height: print.height,
                                  bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: print.width * 4, space: colorSpace,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent),
              let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                  data, UTType.png.identifier as CFString, 1, nil)
        else {
            return Data()
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    // MARK: - Storage

    private func prune() {
        guard shots.count > Self.keep else { return }
        for shot in shots[Self.keep...] { remove(shot.path) }
        shots = Array(shots.prefix(Self.keep))
    }

    private func remove(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(shots),
              let raw = String(data: data, encoding: .utf8) else { return }
        defaults.set(raw, forKey: Self.defaultsKey)
    }
}
