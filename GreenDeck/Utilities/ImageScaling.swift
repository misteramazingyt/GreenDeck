import CoreImage
import CoreGraphics
import CoreImage.CIFilterBuiltins

/// Helpers for fitting background images into the fixed 9:16 output frame
/// according to the selected `CropMode`.
enum ImageScaling {

    /// Produce a CIImage that exactly covers `target` size using the given crop mode.
    /// The returned image's extent origin is (0,0) with size == target.
    static func fit(_ image: CIImage, to target: CGSize, mode: CropMode) -> CIImage {
        switch mode {
        case .fill:
            return aspectFill(image, to: target)
        case .contain:
            return aspectFit(image, to: target, background: nil)
        case .blurFill:
            let blurred = aspectFill(blur(image, radius: 40), to: target)
            let centered = aspectFit(image, to: target, background: nil)
            return centered.composited(over: blurred)
                .cropped(to: CGRect(origin: .zero, size: target))
        }
    }

    /// Scale to fill (cover) the target, cropping the overflow, centered.
    static func aspectFill(_ image: CIImage, to target: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return blackFrame(target) }
        let scale = max(target.width / extent.width, target.height / extent.height)
        let scaled = image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledExtent = scaled.extent
        let tx = (target.width - scaledExtent.width) / 2 - scaledExtent.origin.x
        let ty = (target.height - scaledExtent.height) / 2 - scaledExtent.origin.y
        return scaled
            .transformed(by: CGAffineTransform(translationX: tx, y: ty))
            .cropped(to: CGRect(origin: .zero, size: target))
    }

    /// Scale to fit (contain) inside the target, centered, over a black frame.
    static func aspectFit(_ image: CIImage, to target: CGSize, background: CIImage?) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return blackFrame(target) }
        let scale = min(target.width / extent.width, target.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledExtent = scaled.extent
        let tx = (target.width - scaledExtent.width) / 2 - scaledExtent.origin.x
        let ty = (target.height - scaledExtent.height) / 2 - scaledExtent.origin.y
        let centered = scaled.transformed(by: CGAffineTransform(translationX: tx, y: ty))
        let base = background ?? blackFrame(target)
        return centered.composited(over: base)
            .cropped(to: CGRect(origin: .zero, size: target))
    }

    static func blur(_ image: CIImage, radius: Double) -> CIImage {
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = image.clampedToExtent()
        filter.radius = Float(radius)
        return (filter.outputImage ?? image).cropped(to: image.extent)
    }

    static func blackFrame(_ size: CGSize) -> CIImage {
        CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
    }

    /// Scale and optionally mirror the camera/person image so its height matches
    /// the target frame, centered horizontally. Returns image cropped to target.
    static func fitPerson(_ image: CIImage, to target: CGSize, mirrored: Bool) -> CIImage {
        var working = image
        if mirrored {
            working = working
                .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
        }
        // Normalize origin back to zero after any mirroring.
        working = working.transformed(
            by: CGAffineTransform(translationX: -working.extent.origin.x,
                                  y: -working.extent.origin.y)
        )
        return aspectFill(working, to: target)
    }
}
