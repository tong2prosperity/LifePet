import UIKit
import Vision
import CoreImage
import CoreVideo

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
        guard let cg = image.cgImage else { return image }
        let handler = VNImageRequestHandler(cgImage: cg, orientation: cgOrientation(image.imageOrientation))
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([request])
            guard let result = request.results?.first else { return image }
            let masked = try result.generateMaskedImage(
                ofInstances: result.allInstances,
                from: handler,
                croppedToInstancesExtent: true)
            let ci = CIImage(cvPixelBuffer: masked)
            let ctx = CIContext()
            guard let out = ctx.createCGImage(ci, from: ci.extent) else { return image }
            return UIImage(cgImage: out)
        } catch {
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

    private nonisolated static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
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
