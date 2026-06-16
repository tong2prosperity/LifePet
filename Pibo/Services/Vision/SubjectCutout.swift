import UIKit
import Vision
import CoreImage
import CoreVideo
import os

/// 抠图 — background removal for captured food photos. Uses Vision's
/// foreground-instance mask (`VNGenerateForegroundInstanceMaskRequest`, iOS 17+)
/// to lift the subject onto transparency, matching the 今日记录 card where the
/// cut-out food floats over the paper texture.
///
/// All work is `nonisolated` so callers can run it off the main actor
/// (`Task.detached`) — Vision + CoreImage are thread-safe here and a full-res
/// mask pass is too heavy for the main thread.
enum SubjectCutout {

    /// Lift the dominant subject onto a transparent background. Returns the
    /// original image unchanged when no subject is found or Vision fails — the
    /// flow never blocks on a perfect cut.
    nonisolated static func cutout(_ image: UIImage) -> UIImage {
        let start = ContinuousClock().now
        guard let cg = image.cgImage else {
            LPLog.cutout.error("抠图 abort — image has no cgImage; returning original")
            return image
        }
        LPLog.cutout.debug("抠图 start \(cg.width, privacy: .public)×\(cg.height, privacy: .public)")
        let handler = VNImageRequestHandler(cgImage: cg, orientation: cgOrientation(image.imageOrientation))
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([request])
            guard let result = request.results?.first else {
                // Common, not a failure — a photo with no clear subject just
                // keeps its full frame (the sticker degrades to a framed photo).
                LPLog.cutout.info("抠图 no foreground subject — returning original (\(LPLog.elapsedMs(since: start), format: .fixed(precision: 1), privacy: .public)ms)")
                return image
            }
            let masked = try result.generateMaskedImage(
                ofInstances: result.allInstances,
                from: handler,
                croppedToInstancesExtent: true)
            let ci = CIImage(cvPixelBuffer: masked)
            let ctx = CIContext()
            guard let out = ctx.createCGImage(ci, from: ci.extent) else {
                LPLog.cutout.error("抠图 CIContext.createCGImage failed — returning original")
                return image
            }
            LPLog.cutout.debug("抠图 ok instances=\(result.allInstances.count, privacy: .public) extent=\(Int(ci.extent.width), privacy: .public)×\(Int(ci.extent.height), privacy: .public) (\(LPLog.elapsedMs(since: start), format: .fixed(precision: 1), privacy: .public)ms)")
            return UIImage(cgImage: out)
        } catch {
            LPLog.cutout.error("抠图 mask request failed: \(error.localizedDescription, privacy: .public) — returning original")
            return image
        }
    }

    /// Cut out the subject and encode to PNG (alpha preserved), downscaling the
    /// longer edge to `maxDimension` so the stored blob stays small.
    nonisolated static func cutoutPNG(_ image: UIImage, maxDimension: CGFloat = 1024) -> Data? {
        let lifted = cutout(image)
        let scaled = downscale(lifted, maxDimension: maxDimension)
        return scaled.pngData()
    }

    /// The full 今日记录 treatment: cutout → downscale → 镶嵌白色贴纸边框 → PNG.
    /// Border width scales with the final image so every record reads the same.
    nonisolated static func stickerPNG(_ image: UIImage, maxDimension: CGFloat = 1024) -> Data? {
        let start = ContinuousClock().now
        LPLog.cutout.debug("贴纸生成 start in=\(Int(image.size.width), privacy: .public)×\(Int(image.size.height), privacy: .public)@\(Double(image.scale), format: .fixed(precision: 1), privacy: .public)x maxDim=\(Int(maxDimension), privacy: .public)")
        let lifted = cutout(image)
        let scaled = downscale(lifted, maxDimension: maxDimension)
        let border = max(8, min(scaled.size.width, scaled.size.height) * 0.035)
        let sticker = stickerize(scaled, border: border)
        guard let png = sticker.pngData() else {
            LPLog.cutout.error("贴纸生成 pngData() returned nil — nothing to persist")
            return nil
        }
        LPLog.cutout.info("贴纸生成 ok border=\(Int(border), privacy: .public)pt out=\(Int(sticker.size.width), privacy: .public)×\(Int(sticker.size.height), privacy: .public) png=\(png.count / 1024, privacy: .public)KB (\(LPLog.elapsedMs(since: start), format: .fixed(precision: 1), privacy: .public)ms total)")
        return png
    }

    /// 镶嵌边框 — draw a white sticker outline hugging the subject's silhouette
    /// (the cutout's alpha stamped at 24 offsets around a circle of radius
    /// `border`, subject composited on top), rimmed by a hairline grey die-cut
    /// edge so the white border still reads on the card's white polaroid. When
    /// the cutout failed upstream and the image is a full rectangle, this
    /// degrades to a clean framed photo.
    nonisolated static func stickerize(_ image: UIImage, border: CGFloat) -> UIImage {
        guard border > 0, image.size.width > 0, image.size.height > 0 else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false

        let white = silhouette(of: image, color: .white, format: format)
        let rim = max(1.5, border * 0.15)
        let grey = silhouette(of: image, color: UIColor(white: 0.78, alpha: 1), format: format)

        let inset = border + rim
        let padded = CGSize(width: image.size.width + inset * 2,
                            height: image.size.height + inset * 2)
        return UIGraphicsImageRenderer(size: padded, format: format).image { _ in
            for step in 0..<24 {
                let a = CGFloat(step) / 24 * .pi * 2
                grey.draw(at: CGPoint(x: inset + cos(a) * (border + rim),
                                      y: inset + sin(a) * (border + rim)))
            }
            for step in 0..<24 {
                let a = CGFloat(step) / 24 * .pi * 2
                white.draw(at: CGPoint(x: inset + cos(a) * border,
                                       y: inset + sin(a) * border))
            }
            image.draw(at: CGPoint(x: inset, y: inset))
        }
    }

    /// The image's alpha stamped in a flat color.
    private nonisolated static func silhouette(of image: UIImage, color: UIColor,
                                               format: UIGraphicsImageRendererFormat) -> UIImage {
        let rect = CGRect(origin: .zero, size: image.size)
        return UIGraphicsImageRenderer(size: image.size, format: format).image { ctx in
            color.setFill()
            ctx.fill(rect)
            image.draw(in: rect, blendMode: .destinationIn, alpha: 1)
        }
    }

    // MARK: - Helpers

    private nonisolated static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1                 // target is already in pixels
        format.opaque = false            // keep transparency
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    }

    /// Shared with `SubjectClassifier` — both hand UIKit orientations to Vision.
    nonisolated static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up:            return .up
        case .down:          return .down
        case .left:          return .left
        case .right:         return .right
        case .upMirrored:    return .upMirrored
        case .downMirrored:  return .downMirrored
        case .leftMirrored:  return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }
}
