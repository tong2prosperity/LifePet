import SwiftUI
import UIKit

@MainActor
enum TodayPiboShareService {
    static func export(
        snapshot: TodayPiboShareSnapshot,
        scene: PiboFlatWorldScene,
        characterImage: UIImage?
    ) throws -> URL {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        for url in (try? FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)) ?? []
        where url.lastPathComponent.hasPrefix("pibo-today-") && url.pathExtension == "png" {
            try? FileManager.default.removeItem(at: url)
        }
        let renderer = ImageRenderer(content: TodayPiboShareCard(
            snapshot: snapshot,
            scene: scene,
            characterImage: characterImage
        ))
        renderer.scale = 3.375
        renderer.isOpaque = true
        guard let rendered = renderer.uiImage else { throw ExportError.renderFailed }
        // ImageRenderer rounds the 426.667 pt logical height differently under
        // concurrent simulator test load (occasionally 1441 px). Normalize the
        // final raster in a scale-1 context so the public export contract is
        // deterministic on every device and display scale.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let outputSize = CGSize(width: 1_080, height: 1_440)
        let output = UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
            rendered.draw(in: CGRect(origin: .zero, size: outputSize))
        }
        guard let data = output.pngData() else { throw ExportError.renderFailed }
        let url = cache.appending(path: "pibo-today-\(Int(Date().timeIntervalSince1970)).png")
        try data.write(to: url, options: .atomic)
        return url
    }

    enum ExportError: Error { case renderFailed }
}

struct PiboSystemShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
