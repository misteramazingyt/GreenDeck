import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo

/// Blends the segmented person over the selected background, fitting everything
/// into the fixed 9:16 output frame. Pure transformation — no capture/IO.
final class Compositor {

    private let blend = CIFilter.blendWithMask()

    /// Composite a single frame.
    /// - Parameters:
    ///   - camera: the raw camera frame as a CIImage (extent == capture resolution).
    ///   - maskBuffer: Vision person mask (may be a different resolution); nil triggers PiP fallback.
    ///   - background: the fitted/raw background CIImage, or nil for black.
    ///   - outputSize: target pixel size (e.g. 1080×1920).
    ///   - cropMode: how the background fills the frame.
    ///   - mirror: whether to mirror the camera horizontally.
    func composite(
        camera: CIImage,
        maskBuffer: CVPixelBuffer?,
        background: CIImage?,
        outputSize: CGSize,
        cropMode: CropMode,
        mirror: Bool,
        personTransform: LayerTransform = .identity,
        backgroundTransform: LayerTransform = .identity
    ) -> CIImage {
        let outputRect = CGRect(origin: .zero, size: outputSize)
        var bgFitted = (background.map { ImageScaling.fit($0, to: outputSize, mode: cropMode) })
            ?? ImageScaling.blackFrame(outputSize)
        bgFitted = applyUser(bgFitted, backgroundTransform, outputSize)

        let sourceExtent = camera.extent
        var personFitted = applyOutputTransform(camera, sourceExtent: sourceExtent,
                                                target: outputSize, mirror: mirror)
        personFitted = applyUser(personFitted, personTransform, outputSize)

        guard let maskBuffer else {
            // Fallback (Mode B): picture-in-picture of the camera over background.
            return pictureInPicture(person: personFitted, background: bgFitted, outputSize: outputSize)
                .cropped(to: outputRect)
        }

        var mask = CIImage(cvPixelBuffer: maskBuffer)
        // Bring the mask into the camera's coordinate space, then apply the
        // identical output transform so person and mask stay aligned.
        let maskExtent = mask.extent
        if maskExtent.width > 0, maskExtent.height > 0 {
            let toCamera = CGAffineTransform(
                scaleX: sourceExtent.width / maskExtent.width,
                y: sourceExtent.height / maskExtent.height
            )
            mask = mask.transformed(by: toCamera)
        }
        var maskFitted = applyOutputTransform(mask, sourceExtent: sourceExtent,
                                              target: outputSize, mirror: mirror)
        maskFitted = applyUser(maskFitted, personTransform, outputSize)

        blend.inputImage = personFitted
        blend.backgroundImage = bgFitted
        blend.maskImage = maskFitted
        let result = blend.outputImage ?? bgFitted
        return result.cropped(to: outputRect)
    }

    /// Apply a user scale/translation about the frame center.
    private func applyUser(_ img: CIImage, _ t: LayerTransform, _ size: CGSize) -> CIImage {
        guard !t.isIdentity else { return img }
        let cx = size.width / 2, cy = size.height / 2
        var m = CGAffineTransform(translationX: cx, y: cy)
        m = m.scaledBy(x: t.scale, y: t.scale)
        m = m.translatedBy(x: -cx, y: -cy)
        m = m.concatenating(CGAffineTransform(translationX: t.offsetX, y: t.offsetY))
        return img.transformed(by: m)
    }

    // MARK: Transforms

    /// Mirror (optional) + aspect-fill an image into the target frame.
    private func applyOutputTransform(
        _ image: CIImage,
        sourceExtent S: CGRect,
        target: CGSize,
        mirror: Bool
    ) -> CIImage {
        guard S.width > 0, S.height > 0 else { return image }
        var img = image
        if mirror {
            // x' = S.width - x  (keeps the image in the positive quadrant)
            img = img.transformed(by: CGAffineTransform(scaleX: -1, y: 1)
                .translatedBy(x: -S.width, y: 0))
        }
        let scale = max(target.width / S.width, target.height / S.height)
        img = img.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let e = img.extent
        let tx = (target.width - e.width) / 2 - e.origin.x
        let ty = (target.height - e.height) / 2 - e.origin.y
        return img.transformed(by: CGAffineTransform(translationX: tx, y: ty))
    }

    private func pictureInPicture(person: CIImage, background: CIImage, outputSize: CGSize) -> CIImage {
        let pipWidth = outputSize.width * 0.42
        let scale = pipWidth / max(person.extent.width, 1)
        let scaled = person.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let margin = outputSize.width * 0.04
        let tx = outputSize.width - scaled.extent.width - margin - scaled.extent.origin.x
        let ty = margin - scaled.extent.origin.y
        let placed = scaled.transformed(by: CGAffineTransform(translationX: tx, y: ty))
        return placed.composited(over: background)
    }
}
