import MetalKit
import UIKit

final class LiquidChatGlassMetalView: MTKView {
    weak var captureView: UIView? {
        didSet {
            if captureView == nil {
                lastCapturedBackgroundTexture = nil
            }
            backgroundCaptureNeedsUpdate = true
            pendingBackgroundRecaptureAttempts = 6
            setNeedsDisplay()
        }
    }

    var roiProvider: (() -> CGRect)?
    var shapesProvider: (() -> (LiquidChatGlassShapeState, LiquidChatGlassShapeState, LiquidChatGlassShapeState))?

    private let viewCapture: ViewCapture
    private let renderer: LiquidChatGlassRenderer
    private let metalContext: MetalContext
    private var lastCapturedBackgroundTexture: MTLTexture?
    private var backgroundCaptureNeedsUpdate: Bool = true
    private var pendingBackgroundRecaptureAttempts: Int = 0
    private var lastLayoutSize: CGSize = .zero

    init(config: LiquidGlassConfig, metalContext: MetalContext) {
        self.metalContext = metalContext
        viewCapture = ViewCapture(device: metalContext.device, renderingMethod: .layerRender, maxScale: 2)
        renderer = LiquidChatGlassRenderer(config: config, metalContext: metalContext)
        super.init(frame: .zero, device: metalContext.device)

        isOpaque = false
        enableSetNeedsDisplay = true
        isPaused = true
        preferredFramesPerSecond = 60
        framebufferOnly = true
        backgroundColor = .clear
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }

        backgroundCaptureNeedsUpdate = true
        pendingBackgroundRecaptureAttempts = max(pendingBackgroundRecaptureAttempts, 2)
        requestRedraw()

        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.backgroundCaptureNeedsUpdate = true
            self.pendingBackgroundRecaptureAttempts = max(self.pendingBackgroundRecaptureAttempts, 2)
            self.requestRedraw()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastLayoutSize else { return }
        lastLayoutSize = bounds.size
        backgroundCaptureNeedsUpdate = true
        requestRedraw()
    }

    func updateSettings(config: LiquidGlassConfig) {
        renderer.updateSettings(config: config)
        requestRedraw()
    }

    func invalidateBackgroundCapture() {
        backgroundCaptureNeedsUpdate = true
        requestRedraw()
    }

    // MARK: - Private

    private func requestRedraw() {
        guard window != nil else { return }
        setNeedsDisplay()
    }

    override func draw(_ _: CGRect) {
        guard
            let currentDrawable,
            let passDescriptor = currentRenderPassDescriptor,
            let commandBuffer = metalContext.commandQueue.makeCommandBuffer(),
            drawableSize != .zero,
            let captureView,
            let shapes = shapesProvider?()
        else { return }

        let roi = roiProvider?() ?? .zero
        if roi == .zero {
            if pendingBackgroundRecaptureAttempts > 0 {
                pendingBackgroundRecaptureAttempts -= 1
                requestRedraw()
            }
            return
        }

        let captureLayer = captureView.layer.presentation() ?? captureView.layer
        let captureIsAnimatingOpacity = captureLayer.opacity < 0.999

        let shouldRecaptureBackground = lastCapturedBackgroundTexture == nil
            || backgroundCaptureNeedsUpdate
            || captureIsAnimatingOpacity
            || pendingBackgroundRecaptureAttempts > 0

        if shouldRecaptureBackground {
            if let captured = viewCapture.textureFrom(view: captureView, roi: roi, commandBuffer: commandBuffer) {
                lastCapturedBackgroundTexture = captured
                if pendingBackgroundRecaptureAttempts > 0 {
                    pendingBackgroundRecaptureAttempts -= 1
                }
                if !captureIsAnimatingOpacity, pendingBackgroundRecaptureAttempts == 0 {
                    backgroundCaptureNeedsUpdate = false
                }
            } else if pendingBackgroundRecaptureAttempts > 0 {
                pendingBackgroundRecaptureAttempts -= 1
            }
        }

        guard let bgTexture = lastCapturedBackgroundTexture else {
            if captureIsAnimatingOpacity || pendingBackgroundRecaptureAttempts > 0 {
                backgroundCaptureNeedsUpdate = true
                requestRedraw()
            }
            return
        }

        renderer.encode(
            in: self,
            commandBuffer: commandBuffer,
            backgroundTexture: bgTexture,
            shape0: shapes.0,
            shape1: shapes.1,
            shape2: shapes.2,
            targetRenderPassDescriptor: passDescriptor
        )

        commandBuffer.present(currentDrawable)
        commandBuffer.commit()

        if captureIsAnimatingOpacity || pendingBackgroundRecaptureAttempts > 0 {
            backgroundCaptureNeedsUpdate = true
            requestRedraw()
        }
    }
}
