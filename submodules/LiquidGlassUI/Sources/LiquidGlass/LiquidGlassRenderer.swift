import MetalKit
import UIKit

final class LiquidGlassRenderer {
    private struct BGUniforms {
        var resolution: SIMD2<Float>
        var dpr: Float
        var mouseSpring: SIMD2<Float>
        var mergeRate: Float
        var shapeWidth: Float
        var shapeHeight: Float
        var cornerRadius: Float
        var shapeRoundness: Float
        var motionStretch: Float
        var motionSquash: Float
        var motionBias: Float
    }

    private struct BlurUniforms {
        var resolution: SIMD2<Float>
        var blurRadius: UInt32
    }

    private struct MainUniforms {
        var resolution: SIMD2<Float>
        var dpr: Float
        var mouseSpring: SIMD2<Float>
        var mergeRate: Float
        var shapeWidth: Float
        var shapeHeight: Float
        var cornerRadius: Float
        var shapeRoundness: Float
        var motionStretch: Float
        var motionSquash: Float
        var motionBias: Float
        var shadowExpand: Float
        var shadowFactor: Float
        var shadowPosition: SIMD2<Float>
        var tint: SIMD4<Float>
        var glareTint: SIMD4<Float>
        var glareOppositeTint: SIMD4<Float>
        var refThickness: Float
        var refFactor: Float
        var refDispersion: Float
        var zoomOutFactor: Float
        var refFresnelRange: Float
        var refFresnelFactor: Float
        var refFresnelHardness: Float
        var glareRange: Float
        var glareConvergence: Float
        var glareOppositeFactor: Float
        var glareFactor: Float
        var glareHardness: Float
        var glareAngle: Float
        var blurEdge: UInt32
        var step: Int32
    }

    private var renderConfig: LiquidGlassConfig
    private var blurKernelRadius: Int
    private var blurWeights: [Float]
    private var refThickness: Float
    private var refFactor: Float
    private var refDispersion: Float
    private var shapeRoundness: Float

    private let metalContext: MetalContext

    private let bgPipelineState: MTLRenderPipelineState
    private let vBlurPipelineState: MTLRenderPipelineState
    private let hBlurPipelineState: MTLRenderPipelineState
    private let mainPipelineState: MTLRenderPipelineState

    private var bgPassTexture: MTLTexture?
    private var vBlurTexture: MTLTexture?
    private var hBlurTexture: MTLTexture?
    private var lastDrawableSize: CGSize = .zero

    private let samplerState: MTLSamplerState
    private let offscreenPassDescriptor = MTLRenderPassDescriptor()

    private var blurWeightsBuffer: MTLBuffer?
    private var blurWeightsBufferLength: Int = 0

    init(config: LiquidGlassConfig, metalContext: MetalContext) {
        self.metalContext = metalContext
        renderConfig = config
        blurKernelRadius = config.blurRadius
        blurWeights = computeGaussianKernelByRadius(radius: config.blurRadius)
        refThickness = config.refThickness
        refFactor = config.refFactor
        refDispersion = config.refDispersion
        shapeRoundness = config.shapeRoundness

        guard
            let bgPipelineState = Self.makePipeline(fragment: "liquidGlassBgFragment", metalContext: metalContext),
            let vBlurPipelineState = Self.makePipeline(fragment: "liquidGlassVBlurFragment", metalContext: metalContext),
            let hBlurPipelineState = Self.makePipeline(fragment: "liquidGlassHBlurFragment", metalContext: metalContext),
            let mainPipelineState = Self.makePipeline(fragment: "liquidGlassMainFragment", metalContext: metalContext)
        else {
            fatalError("Failed to build liquid glass pipelines")
        }

        self.bgPipelineState = bgPipelineState
        self.vBlurPipelineState = vBlurPipelineState
        self.hBlurPipelineState = hBlurPipelineState
        self.mainPipelineState = mainPipelineState

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.mipFilter = .notMipmapped
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        samplerState = metalContext.device.makeSamplerState(descriptor: samplerDesc)!

        offscreenPassDescriptor.colorAttachments[0].loadAction = .dontCare
        offscreenPassDescriptor.colorAttachments[0].storeAction = .store

        updateBlurWeightsBuffer()
    }

    func updateMaterial(thickness: Float, refraction: Float, dispersion: Float, shapeRoundness: Float) {
        refThickness = thickness
        refFactor = refraction
        refDispersion = dispersion
        self.shapeRoundness = shapeRoundness
    }

    func updateSettings(config: LiquidGlassConfig) {
        renderConfig = config
        refThickness = config.refThickness
        refFactor = config.refFactor
        refDispersion = config.refDispersion
        shapeRoundness = config.shapeRoundness
        blurKernelRadius = config.blurRadius
        blurWeights = computeGaussianKernelByRadius(radius: config.blurRadius)
        updateBlurWeightsBuffer()
        if blurKernelRadius <= 0 {
            vBlurTexture = nil
            hBlurTexture = nil
        }
    }

    func draw(
        in view: MTKView,
        backgroundTexture: MTLTexture,
        shape: LiquidGlassShapeState,
        motion: LiquidGlassMotionSnapshot
    ) {
        guard
            let currentDrawable = view.currentDrawable,
            let commandBuffer = metalContext.commandQueue.makeCommandBuffer(),
            let passDescriptor = view.currentRenderPassDescriptor
        else { return }

        encode(
            in: view,
            commandBuffer: commandBuffer,
            backgroundTexture: backgroundTexture,
            shape: shape,
            motion: motion,
            targetRenderPassDescriptor: passDescriptor
        )
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }

    func encode(
        in view: MTKView,
        commandBuffer: MTLCommandBuffer,
        backgroundTexture: MTLTexture,
        shape: LiquidGlassShapeState,
        motion: LiquidGlassMotionSnapshot,
        targetRenderPassDescriptor: MTLRenderPassDescriptor
    ) {
        let needsBlur = blurKernelRadius > 0
        createPassTexturesIfNeeded(size: view.drawableSize, needsBlur: needsBlur)

        let dpr = Float(view.contentScaleFactor)
        let resolution = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        // Shader space treats `uv.y = 0` as the bottom of the view (see `liquidGlassVertex`),
        // while UIKit `CALayer.position.y` grows downward from the top. Flip Y so the blob
        // center matches UIKit geometry (required when the knob is not vertically centered).
        let flippedY = Float(view.bounds.height) - Float(shape.center.y)
        let mouseSpring = SIMD2<Float>(Float(shape.center.x), flippedY) * SIMD2(dpr, dpr)
        let cornerRadius = min(Float(shape.cornerRadius), min(Float(shape.size.width), Float(shape.size.height)) / 2)
        let boosts = highlightAndGlareBoost(
            stretch: Float(motion.stretch),
            bias: Float(abs(motion.bias)),
            squash: Float(motion.squash)
        )
        let highlightBoost = boosts.highlight
        let glareBoost = boosts.glare

        let stretchScalar = Float(motion.stretch)
        let squashScalar = Float(motion.squash)
        let biasScalar = Float(motion.overshoot)

        guard let bgTarget = bgPassTexture else { return }

        // Pass 1: copy the captured background into a GPU render target so subsequent
        // passes operate in the shader's UV space (uv.y = 0 at the bottom).
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: offscreenPassDescriptor(for: bgTarget)) {
            var uniforms = BGUniforms(
                resolution: resolution,
                dpr: dpr,
                mouseSpring: mouseSpring,
                mergeRate: renderConfig.mergeRate,
                shapeWidth: Float(shape.size.width),
                shapeHeight: Float(shape.size.height),
                cornerRadius: cornerRadius,
                shapeRoundness: shapeRoundness,
                motionStretch: stretchScalar,
                motionSquash: squashScalar,
                motionBias: biasScalar
            )
            encoder.setRenderPipelineState(bgPipelineState)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BGUniforms>.stride, index: 1)
            encoder.setFragmentTexture(backgroundTexture, index: 0)
            encoder.setFragmentSamplerState(samplerState, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }

        let blurredTexture: MTLTexture
        if needsBlur, let vTarget = vBlurTexture, let hTarget = hBlurTexture {
            // Pass 2: vertical blur
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: offscreenPassDescriptor(for: vTarget)) {
                var uniforms = BlurUniforms(
                    resolution: resolution,
                    blurRadius: UInt32(blurKernelRadius)
                )
                encoder.setRenderPipelineState(vBlurPipelineState)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BlurUniforms>.stride, index: 1)
                if let blurWeightsBuffer {
                    encoder.setFragmentBuffer(blurWeightsBuffer, offset: 0, index: 2)
                } else {
                    encoder.setFragmentBytes(blurWeights, length: MemoryLayout<Float>.stride * blurWeights.count, index: 2)
                }
                encoder.setFragmentTexture(bgTarget, index: 0)
                encoder.setFragmentSamplerState(samplerState, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                encoder.endEncoding()
            }

            // Pass 3: horizontal blur
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: offscreenPassDescriptor(for: hTarget)) {
                var uniforms = BlurUniforms(
                    resolution: resolution,
                    blurRadius: UInt32(blurKernelRadius)
                )
                encoder.setRenderPipelineState(hBlurPipelineState)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BlurUniforms>.stride, index: 1)
                if let blurWeightsBuffer {
                    encoder.setFragmentBuffer(blurWeightsBuffer, offset: 0, index: 2)
                } else {
                    encoder.setFragmentBytes(blurWeights, length: MemoryLayout<Float>.stride * blurWeights.count, index: 2)
                }
                encoder.setFragmentTexture(vTarget, index: 0)
                encoder.setFragmentSamplerState(samplerState, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                encoder.endEncoding()
            }

            blurredTexture = hTarget
        } else {
            blurredTexture = bgTarget
        }

        // Pass 4: main composite
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: targetRenderPassDescriptor) {
            var uniforms = MainUniforms(
                resolution: resolution,
                dpr: dpr,
                mouseSpring: mouseSpring,
                mergeRate: renderConfig.mergeRate,
                shapeWidth: Float(shape.size.width),
                shapeHeight: Float(shape.size.height),
                cornerRadius: cornerRadius,
                shapeRoundness: shapeRoundness,
                motionStretch: stretchScalar,
                motionSquash: squashScalar,
                motionBias: biasScalar,
                shadowExpand: renderConfig.shadowExpand,
                shadowFactor: renderConfig.shadowFactor / 100,
                shadowPosition: SIMD2<Float>(-renderConfig.shadowPosition.x, -renderConfig.shadowPosition.y),
                tint: SIMD4<Float>(renderConfig.tint.r, renderConfig.tint.g, renderConfig.tint.b, renderConfig.tint.a),
                glareTint: SIMD4<Float>(renderConfig.glareTint.r, renderConfig.glareTint.g, renderConfig.glareTint.b, renderConfig.glareTint.a),
                glareOppositeTint: SIMD4<Float>(renderConfig.glareOppositeTint.r, renderConfig.glareOppositeTint.g, renderConfig.glareOppositeTint.b, renderConfig.glareOppositeTint.a),
                refThickness: refThickness,
                refFactor: refFactor,
                refDispersion: refDispersion,
                zoomOutFactor: renderConfig.zoomOutFactor,
                refFresnelRange: renderConfig.refFresnelRange,
                refFresnelFactor: renderConfig.refFresnelFactor * highlightBoost / 100.0,
                refFresnelHardness: renderConfig.refFresnelHardness / 100.0,
                glareRange: renderConfig.glareRange,
                glareConvergence: renderConfig.glareConvergence / 100.0,
                glareOppositeFactor: renderConfig.glareOppositeFactor / 100.0,
                glareFactor: renderConfig.glareFactor * glareBoost / 100.0,
                glareHardness: renderConfig.glareHardness / 100.0,
                glareAngle: renderConfig.glareAngle * Float.pi / 180.0,
                blurEdge: renderConfig.blurEdge ? 1 : 0,
                step: Int32(renderConfig.step)
            )
            encoder.setRenderPipelineState(mainPipelineState)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MainUniforms>.stride, index: 1)
            encoder.setFragmentTexture(blurredTexture, index: 0)
            encoder.setFragmentTexture(bgTarget, index: 1)
            encoder.setFragmentSamplerState(samplerState, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }
    }

    // MARK: - Private

    private func highlightAndGlareBoost(stretch: Float, bias: Float, squash: Float) -> (highlight: Float, glare: Float) {
        let combined = max(0, stretch) + abs(bias) * 0.5 + squash * 0.4
        let directionBoost = 1 + min(0.4, abs(bias) * 0.8)
        let highlight = (1 + min(0.9, combined * 1.2)) * directionBoost
        let glare = (1 + min(0.6, combined * 0.8)) * directionBoost
        return (highlight, glare)
    }

    private static func makePipeline(fragment name: String, metalContext: MetalContext) -> MTLRenderPipelineState? {
        let desc = MTLRenderPipelineDescriptor()
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.colorAttachments[0].isBlendingEnabled = false
        desc.vertexFunction = metalContext.library.makeFunction(name: "liquidGlassVertex")
        desc.fragmentFunction = metalContext.library.makeFunction(name: name)
        do {
            return try metalContext.device.makeRenderPipelineState(descriptor: desc)
        } catch {
            return nil
        }
    }

    private func offscreenPassDescriptor(for texture: MTLTexture) -> MTLRenderPassDescriptor {
        offscreenPassDescriptor.colorAttachments[0].texture = texture
        return offscreenPassDescriptor
    }

    private func updateBlurWeightsBuffer() {
        let requiredLength = blurWeights.count * MemoryLayout<Float>.stride
        if blurWeightsBuffer == nil || blurWeightsBufferLength < requiredLength {
            blurWeightsBufferLength = requiredLength
            blurWeightsBuffer = metalContext.device.makeBuffer(length: requiredLength, options: .storageModeShared)
        }

        guard let blurWeightsBuffer else { return }
        blurWeights.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            memcpy(blurWeightsBuffer.contents(), baseAddress, requiredLength)
        }
    }

    private func createPassTexturesIfNeeded(size: CGSize) {
        createPassTexturesIfNeeded(size: size, needsBlur: blurKernelRadius > 0)
    }

    private func createPassTexturesIfNeeded(size: CGSize, needsBlur: Bool) {
        guard size != .zero else { return }

        let sizeChanged = size != lastDrawableSize
        if sizeChanged {
            lastDrawableSize = size
        }

        if sizeChanged || bgPassTexture == nil {
            bgPassTexture = makePassTexture(size: size)
        }

        if needsBlur {
            if sizeChanged || vBlurTexture == nil || hBlurTexture == nil {
                vBlurTexture = makePassTexture(size: size)
                hBlurTexture = makePassTexture(size: size)
            }
        } else {
            vBlurTexture = nil
            hBlurTexture = nil
        }
    }

    private func makePassTexture(size: CGSize) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(round(size.width)),
            height: Int(round(size.height)),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        return metalContext.device.makeTexture(descriptor: descriptor)
    }
}
