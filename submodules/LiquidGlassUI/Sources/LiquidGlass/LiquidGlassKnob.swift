//
//  LiquidGlassKnob.swift
//  liquid-ui-effect-test
//
//  Created by Egor Butyrin on 12/12/2025.
//

import MetalKit
import UIKit

final class LiquidGlassKnob: MTKView {
    override var isHidden: Bool {
        didSet {
            isPaused = isHidden
        }
    }

    weak var backgroundView: UIView? {
        didSet {
            if backgroundView != nil {
                backgroundTexture = nil
            }
        }
    }

    var backgroundTexture: MTLTexture? {
        didSet {
            if backgroundTexture != nil {
                backgroundView = nil
            }
        }
    }

    private let renderer: LiquidGlassRenderer
    private let shapeDriver: LiquidGlassShapeDriver
    lazy var engine = LiquidGlassKnobEngine(liquidView: self, shapeDriver: shapeDriver)
    private let viewCapture: ViewCapture
    private let metalContext: MetalContext

    init(config: LiquidGlassConfig, metalContext: MetalContext) {
        self.metalContext = metalContext
        renderer = LiquidGlassRenderer(config: config, metalContext: metalContext)
        viewCapture = ViewCapture(device: metalContext.device, renderingMethod: .layerRender, maxScale: 2)

        let driverLayer = CALayer()
        driverLayer.opacity = 0
        let initialState = LiquidGlassShapeState(
            center: .zero,
            size: CGSize(width: CGFloat(config.shapeWidth), height: CGFloat(config.shapeHeight)),
            cornerRadius: CGFloat(config.cornerRadius)
        )
        shapeDriver = LiquidGlassShapeDriver(layer: driverLayer, initialState: initialState)

        super.init(frame: .zero, device: metalContext.device)

        isOpaque = false
        isPaused = false
        enableSetNeedsDisplay = true
        preferredFramesPerSecond = 60
        framebufferOnly = true
        backgroundColor = .clear
        clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)

        layer.addSublayer(driverLayer)

        isHidden = true
        layer.opacity = 0
    }

	    required init(coder: NSCoder) {
	        fatalError("init(coder:) has not been implemented")
	    }

    /// Passthrough touches.
    override func point(inside _: CGPoint, with _: UIEvent?) -> Bool {
        false
    }

    override func draw(_ _: CGRect) {
        guard
            let currentDrawable,
            let passDescriptor = currentRenderPassDescriptor,
            let commandBuffer = metalContext.commandQueue.makeCommandBuffer()
        else { return }

        let bgTexture: MTLTexture
        if let backgroundTexture {
            bgTexture = backgroundTexture
        } else if
            let backgroundView,
            let capturedTexture = viewCapture.textureFrom(view: backgroundView, roi: backgroundView.bounds, commandBuffer: commandBuffer)
        {
            bgTexture = capturedTexture
        } else {
            return
        }

        let shape = shapeDriver.presentationState
        let motion = engine.motionSnapshot(currentCenter: shape.center)
        renderer.encode(
            in: self,
            commandBuffer: commandBuffer,
            backgroundTexture: bgTexture,
            shape: shape,
            motion: motion,
            targetRenderPassDescriptor: passDescriptor
        )
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }

    func snapToSelection(center: CGPoint) {
        engine.snapToSelection(center: center)
    }

    func updateMaterial(thickness: Float, refraction: Float, dispersion: Float, cornerRadius: Float, shapeRoundness: Float) {
        renderer.updateMaterial(thickness: thickness, refraction: refraction, dispersion: dispersion, shapeRoundness: shapeRoundness)

        let current = shapeDriver.presentationState
        shapeDriver.snap(
            to: LiquidGlassShapeState(
                center: current.center,
                size: current.size,
                cornerRadius: CGFloat(cornerRadius)
            )
        )
        setNeedsDisplay()
    }

    func updateSettings(config: LiquidGlassConfig) {
        renderer.updateSettings(config: config)
        engine.setShapeSize(
            CGSize(width: CGFloat(config.shapeWidth), height: CGFloat(config.shapeHeight)),
            cornerRadius: CGFloat(config.cornerRadius)
        )
        setNeedsDisplay()
    }
}

extension LiquidGlassKnob: LiquidGlassKnobAnimatingView {}
