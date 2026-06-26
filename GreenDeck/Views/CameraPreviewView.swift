import SwiftUI
import MetalKit
import CoreImage

/// MTKView that renders composited CIImages from the camera pipeline.
final class MetalPreviewView: MTKView, PreviewSink {
    private var ciContext: CIContext!
    private var commandQueue: MTLCommandQueue!
    private let renderLock = NSLock()
    private var currentImage: CIImage?

    init() {
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: device)
        if let device {
            commandQueue = device.makeCommandQueue()
            ciContext = CIContext(mtlDevice: device)
        }
        framebufferOnly = false
        enableSetNeedsDisplay = false
        isPaused = true              // we drive draw() manually per frame
        colorPixelFormat = .bgra8Unorm
        backgroundColor = .black
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func sendPreview(_ image: CIImage) {
        renderLock.lock(); currentImage = image; renderLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.draw() }
    }

    override func draw(_ rect: CGRect) {
        renderLock.lock(); let image = currentImage; renderLock.unlock()
        guard let image, let ciContext, let commandQueue,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let size = drawableSize
        guard size.width > 0, size.height > 0, image.extent.width > 0 else { return }

        // Aspect-fit the 9:16 composite into the drawable, centered.
        let scale = min(size.width / image.extent.width, size.height / image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let tx = (size.width - scaled.extent.width) / 2 - scaled.extent.origin.x
        let ty = (size.height - scaled.extent.height) / 2 - scaled.extent.origin.y
        let centered = scaled.transformed(by: CGAffineTransform(translationX: tx, y: ty))

        ciContext.render(
            centered,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: CGRect(origin: .zero, size: size),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let camera: CameraService

    func makeUIView(context: Context) -> MetalPreviewView {
        let view = MetalPreviewView()
        camera.previewSink = view
        return view
    }

    func updateUIView(_ uiView: MetalPreviewView, context: Context) {}
}
