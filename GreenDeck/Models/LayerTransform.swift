import CoreGraphics

/// A user-applied scale + translation for a composite layer (the person or the
/// background), expressed in output/composite pixels. Origin is the frame
/// center; +y is up (Core Image space).
struct LayerTransform: Hashable {
    var scale: CGFloat = 1
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0

    var isIdentity: Bool { scale == 1 && offsetX == 0 && offsetY == 0 }

    static let identity = LayerTransform()
}
