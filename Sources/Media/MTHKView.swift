import MetalKit
import AVFoundation

public protocol MTHKViewDrawDelegate: class {
    func shouldDraw(_ image: CIImage) -> Bool
}

@available(iOS 9.0, *)
open class MTHKView: MTKView {
    public var videoGravity: AVLayerVideoGravity = .resizeAspect

    var position: AVCaptureDevice.Position = .back
    var orientation: AVCaptureVideoOrientation = .portrait
    
    private var displayImage: CIImage?
    private weak var currentStream: NetStream? {
        didSet {
            oldValue?.mixer.videoIO.drawable = nil
        }
    }
    private let colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()

    public weak var drawDelegate: MTHKViewDrawDelegate?
    
    public init(frame: CGRect) {
        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())
        configure()
    }

    required public init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.device = MTLCreateSystemDefaultDevice()
        configure()
    }

    open override func awakeFromNib() {
        configure()
    }
    
    private func configure() {
        delegate = self
        isPaused = true
        enableSetNeedsDisplay = true
        framebufferOnly = false
    }

    open func attachStream(_ stream: NetStream?) {
        if let stream: NetStream = stream {
            stream.mixer.videoIO.context = CIContext(mtlDevice: device!)
            stream.lockQueue.async {
                self.position = stream.mixer.videoIO.position
                stream.mixer.videoIO.drawable = self
                stream.mixer.startRunning()
            }
        }
        currentStream = stream
    }
    
    private func clear() {
        #if !targetEnvironment(simulator)
        guard
            let drawable = currentDrawable,
            let rpd = currentRenderPassDescriptor,
            let commandBuffer: MTLCommandBuffer = device?.makeCommandQueue()?.makeCommandBuffer() else {
                return
        }
        
        rpd.colorAttachments[0].texture = drawable.texture
        rpd.colorAttachments[0].clearColor = clearColor
        rpd.colorAttachments[0].loadAction = .clear
        commandBuffer.makeRenderCommandEncoder(descriptor: rpd)?.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        #endif
    }
}

@available(iOS 9.0, *)
extension MTHKView: MTKViewDelegate {
    // MARK: MTKViewDelegate
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }

    public func draw(in view: MTKView) {
        #if !targetEnvironment(simulator)
        guard
            let drawable: CAMetalDrawable = currentDrawable,
            let image: CIImage = displayImage,
            let commandBuffer: MTLCommandBuffer = device?.makeCommandQueue()?.makeCommandBuffer(),
            let rpd = currentRenderPassDescriptor,
            let context: CIContext = currentStream?.mixer.videoIO.context else {
            return
        }
        
        if let draw = drawDelegate?.shouldDraw(image), !draw {
            return
        }
        
        var scaleX: CGFloat = 0
        var scaleY: CGFloat = 0
        var translationX: CGFloat = 0
        var translationY: CGFloat = 0
        switch videoGravity {
        case .resize:
            scaleX = drawableSize.width / image.extent.width
            scaleY = drawableSize.height / image.extent.height
        case .resizeAspect:
            let scale: CGFloat = min(drawableSize.width / image.extent.width, drawableSize.height / image.extent.height)
            scaleX = scale
            scaleY = scale
            translationX = (drawableSize.width - image.extent.width * scale) / scaleX / 2
            translationY = (drawableSize.height - image.extent.height * scale) / scaleY / 2
        case .resizeAspectFill:
            let scale: CGFloat = max(drawableSize.width / image.extent.width, drawableSize.height / image.extent.height)
            scaleX = scale
            scaleY = scale
            translationX = (drawableSize.width - image.extent.width * scale) / scaleX / 2
            translationY = (drawableSize.height - image.extent.height * scale) / scaleY / 2
        default:
            break
        }
        
        rpd.colorAttachments[0].texture = drawable.texture
        rpd.colorAttachments[0].clearColor = clearColor
        rpd.colorAttachments[0].loadAction = .clear
        commandBuffer.makeRenderCommandEncoder(descriptor: rpd)?.endEncoding()
        
        let bounds: CGRect = CGRect(origin: .zero, size: drawableSize)
        let scaledImage: CIImage = image
            .transformed(by: CGAffineTransform(translationX: translationX, y: translationY))
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        context.render(scaledImage, to: drawable.texture, commandBuffer: commandBuffer, bounds: bounds, colorSpace: colorSpace)
        commandBuffer.present(drawable)
        commandBuffer.commit()
        #endif
    }
}

@available(iOS 9.0, *)
extension MTHKView: NetStreamDrawable {
    // MARK: NetStreamDrawable
    func draw(image: CIImage) {
        DispatchQueue.main.async {
            self.displayImage = image
            #if os(iOS)
            self.setNeedsDisplay()
            #else
            self.needsDisplay = true
            #endif
        }
    }
}
