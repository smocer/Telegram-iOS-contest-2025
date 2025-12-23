import MetalKit
import UIKit

struct LiquidChatGlassShapeState: Equatable {
    var center: CGPoint
    var size: CGSize
    var cornerRadius: CGFloat
    var isEnabled: Bool
    var direction: CGVector

    init(center: CGPoint, size: CGSize, cornerRadius: CGFloat, isEnabled: Bool, direction: CGVector = CGVector(dx: 1, dy: 0)) {
        self.center = center
        self.size = size
        self.cornerRadius = cornerRadius
        self.isEnabled = isEnabled
        self.direction = direction
    }
}

final class LiquidChatGlassRenderer {
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
        var mergeRate: Float
        var shapeRoundness: Float
        var padding0: Float

        var shape0Center: SIMD2<Float>
        var shape0Size: SIMD2<Float>
        var shape0CornerRadius: Float
        var shape0Enabled: UInt32

        var shape1Center: SIMD2<Float>
        var shape1Size: SIMD2<Float>
        var shape1CornerRadius: Float
        var shape1Enabled: UInt32

        var shape2Center: SIMD2<Float>
        var shape2Size: SIMD2<Float>
        var shape2CornerRadius: Float
        var shape2Enabled: UInt32

        var shape0Direction: SIMD2<Float>
        var shape1Direction: SIMD2<Float>
        var shape2Direction: SIMD2<Float>

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
        var padding1: UInt32
    }

    private var renderConfig: LiquidGlassConfig
    private var blurKernelRadius: Int
    private var blurWeights: [Float]

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

        guard
            let bgPipelineState = Self.makePipeline(fragment: "liquidGlassBgFragment", metalContext: metalContext),
            let vBlurPipelineState = Self.makePipeline(fragment: "liquidGlassVBlurFragment", metalContext: metalContext),
            let hBlurPipelineState = Self.makePipeline(fragment: "liquidGlassHBlurFragment", metalContext: metalContext),
            let mainPipelineState = Self.makePipeline(fragment: "liquidChatGlassMainUnifiedFragment", metalContext: metalContext)
        else {
            fatalError("Failed to build liquid chat glass pipelines")
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

    func updateSettings(config: LiquidGlassConfig) {
        renderConfig = config
        blurKernelRadius = config.blurRadius
        blurWeights = computeGaussianKernelByRadius(radius: config.blurRadius)
        updateBlurWeightsBuffer()
        if blurKernelRadius <= 0 {
            vBlurTexture = nil
            hBlurTexture = nil
        }
    }

    func encode(
        in view: MTKView,
        commandBuffer: MTLCommandBuffer,
        backgroundTexture: MTLTexture,
        shape0: LiquidChatGlassShapeState,
        shape1: LiquidChatGlassShapeState,
        shape2: LiquidChatGlassShapeState,
        targetRenderPassDescriptor: MTLRenderPassDescriptor
    ) {
        let needsBlur = blurKernelRadius > 0
        createPassTexturesIfNeeded(size: view.drawableSize, needsBlur: needsBlur)

        let dpr = Float(view.contentScaleFactor)
        let resolution = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))

        guard let bgTarget = bgPassTexture else { return }

        // Pass 1: copy the captured background into a GPU render target so subsequent
        // passes operate in the shader's UV space (uv.y = 0 at the bottom).
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: offscreenPassDescriptor(for: bgTarget)) {
            var uniforms = BGUniforms(
                resolution: resolution,
                dpr: dpr,
                mouseSpring: .zero,
                mergeRate: renderConfig.mergeRate,
                shapeWidth: 0,
                shapeHeight: 0,
                cornerRadius: 0,
                shapeRoundness: renderConfig.shapeRoundness,
                motionStretch: 0,
                motionSquash: 0,
                motionBias: 0
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
                var uniforms = BlurUniforms(resolution: resolution, blurRadius: UInt32(blurKernelRadius))
                encoder.setRenderPipelineState(vBlurPipelineState)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BlurUniforms>.stride, index: 1)
                if let blurWeightsBuffer {
                    encoder.setFragmentBuffer(blurWeightsBuffer, offset: 0, index: 2)
                } else {
                    encoder.setFragmentBytes(blurWeights, length: blurWeights.count * MemoryLayout<Float>.stride, index: 2)
                }
                encoder.setFragmentTexture(bgTarget, index: 0)
                encoder.setFragmentSamplerState(samplerState, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                encoder.endEncoding()
            }

            // Pass 3: horizontal blur
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: offscreenPassDescriptor(for: hTarget)) {
                var uniforms = BlurUniforms(resolution: resolution, blurRadius: UInt32(blurKernelRadius))
                encoder.setRenderPipelineState(hBlurPipelineState)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BlurUniforms>.stride, index: 1)
                if let blurWeightsBuffer {
                    encoder.setFragmentBuffer(blurWeightsBuffer, offset: 0, index: 2)
                } else {
                    encoder.setFragmentBytes(blurWeights, length: blurWeights.count * MemoryLayout<Float>.stride, index: 2)
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

        // Pass 4: glass refraction
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: targetRenderPassDescriptor) {
            let uniformShape0 = uniformShape(for: shape0, in: view, dpr: dpr)
            let uniformShape1 = uniformShape(for: shape1, in: view, dpr: dpr)
            let uniformShape2 = uniformShape(for: shape2, in: view, dpr: dpr)
            let tint = SIMD4<Float>(renderConfig.tint.r, renderConfig.tint.g, renderConfig.tint.b, renderConfig.tint.a)
            let glareTint = SIMD4<Float>(renderConfig.glareTint.r, renderConfig.glareTint.g, renderConfig.glareTint.b, renderConfig.glareTint.a)
            let glareOppositeTint = SIMD4<Float>(
                renderConfig.glareOppositeTint.r,
                renderConfig.glareOppositeTint.g,
                renderConfig.glareOppositeTint.b,
                renderConfig.glareOppositeTint.a
            )

            var uniforms = MainUniforms(
                resolution: resolution,
                dpr: dpr,
                mergeRate: renderConfig.mergeRate,
                shapeRoundness: renderConfig.shapeRoundness,
                padding0: 0,
                shape0Center: uniformShape0.center,
                shape0Size: uniformShape0.size,
                shape0CornerRadius: uniformShape0.cornerRadius,
                shape0Enabled: uniformShape0.enabled,
                shape1Center: uniformShape1.center,
                shape1Size: uniformShape1.size,
                shape1CornerRadius: uniformShape1.cornerRadius,
                shape1Enabled: uniformShape1.enabled,
                shape2Center: uniformShape2.center,
                shape2Size: uniformShape2.size,
                shape2CornerRadius: uniformShape2.cornerRadius,
                shape2Enabled: uniformShape2.enabled,
                shape0Direction: uniformShape0.direction,
                shape1Direction: uniformShape1.direction,
                shape2Direction: uniformShape2.direction,
                shadowExpand: renderConfig.shadowExpand,
                shadowFactor: renderConfig.shadowFactor / 100.0,
                shadowPosition: SIMD2<Float>(-renderConfig.shadowPosition.x, -renderConfig.shadowPosition.y),
                tint: tint,
                glareTint: glareTint,
                glareOppositeTint: glareOppositeTint,
                refThickness: renderConfig.refThickness,
                refFactor: renderConfig.refFactor,
                refDispersion: renderConfig.refDispersion,
                zoomOutFactor: renderConfig.zoomOutFactor,
                refFresnelRange: renderConfig.refFresnelRange,
                refFresnelFactor: renderConfig.refFresnelFactor / 100.0,
                refFresnelHardness: renderConfig.refFresnelHardness / 100.0,
                glareRange: renderConfig.glareRange,
                glareConvergence: renderConfig.glareConvergence / 100.0,
                glareOppositeFactor: renderConfig.glareOppositeFactor / 100.0,
                glareFactor: renderConfig.glareFactor / 100.0,
                glareHardness: renderConfig.glareHardness / 100.0,
                glareAngle: renderConfig.glareAngle * Float.pi / 180.0,
                blurEdge: renderConfig.blurEdge ? 1 : 0,
                step: Int32(renderConfig.step),
                padding1: 0
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

    private func createPassTexturesIfNeeded(size: CGSize) {
        createPassTexturesIfNeeded(size: size, needsBlur: blurKernelRadius > 0)
    }

    private func createPassTexturesIfNeeded(size: CGSize, needsBlur: Bool) {
        guard size != .zero else { return }

        let sizeChanged = size != lastDrawableSize
        if sizeChanged {
            lastDrawableSize = size
        }

        let width = Int(round(size.width))
        let height = Int(round(size.height))

        if sizeChanged || bgPassTexture == nil {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            bgPassTexture = metalContext.device.makeTexture(descriptor: descriptor)
        }

        if needsBlur {
            if sizeChanged || vBlurTexture == nil || hBlurTexture == nil {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm,
                    width: width,
                    height: height,
                    mipmapped: false
                )
                descriptor.usage = [.renderTarget, .shaderRead]
                descriptor.storageMode = .private
                vBlurTexture = metalContext.device.makeTexture(descriptor: descriptor)
                hBlurTexture = metalContext.device.makeTexture(descriptor: descriptor)
            }
        } else {
            vBlurTexture = nil
            hBlurTexture = nil
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

    private func uniformShape(
        for shape: LiquidChatGlassShapeState,
        in view: MTKView,
        dpr: Float
    ) -> (center: SIMD2<Float>, size: SIMD2<Float>, cornerRadius: Float, enabled: UInt32, direction: SIMD2<Float>) {
        let clampedSize = CGSize(width: max(0.0, shape.size.width), height: max(0.0, shape.size.height))
        let minSide = max(0.001, min(clampedSize.width, clampedSize.height))
        let cornerRadius = min(shape.cornerRadius, minSide / 2)

        let flippedY = Float(view.bounds.height) - Float(shape.center.y)
        let centerPixels = SIMD2<Float>(Float(shape.center.x), flippedY) * SIMD2<Float>(dpr, dpr)
        let sizePoints = SIMD2<Float>(Float(clampedSize.width), Float(clampedSize.height))

        var direction = SIMD2<Float>(Float(shape.direction.dx), Float(-shape.direction.dy))
        let dirLength = simd_length(direction)
        if dirLength < 0.0001 {
            direction = SIMD2<Float>(1, 0)
        } else {
            direction /= dirLength
        }

        return (
            center: centerPixels,
            size: sizePoints,
            cornerRadius: Float(cornerRadius),
            enabled: shape.isEnabled ? 1 : 0,
            direction: direction
        )
    }

    private static func makePipeline(fragment: String, metalContext: MetalContext) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = false

        descriptor.vertexFunction = metalContext.library.makeFunction(name: "liquidGlassVertex")
        descriptor.fragmentFunction = metalContext.library.makeFunction(name: fragment)
        do {
            return try metalContext.device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            assertionFailure("Failed to build liquid chat glass pipeline=\(fragment) error=\(error)")
            return nil
        }
    }
}
