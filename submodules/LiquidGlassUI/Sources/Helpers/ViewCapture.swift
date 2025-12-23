//
//  ViewCapture.swift
//  liquid-ui-effect-test
//
//  Created by Egor Butyrin on 12/12/2025.
//

import Metal
import UIKit

final class ViewCapture {
    enum RenderingMethod {
        case drawHierarchy
        case layerRender
    }

    private struct TextureSlot {
        let texture: MTLTexture
        var inFlightCommandBuffer: MTLCommandBuffer?
    }

    private let device: MTLDevice
    private let maxInFlightTextures: Int

    private var slots: [TextureSlot] = []
    private var nextSlotIndex: Int = 0

    private var cachedPixelWidth: Int = 0
    private var cachedPixelHeight: Int = 0
    private var cachedScale: CGFloat = 0

    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

    private var bytesPerRow: Int = 0
    private var pixelBuffer: UnsafeMutableRawPointer?
    private var pixelBufferLength: Int = 0
    private var bitmapContext: CGContext?

    private let renderingMethod: RenderingMethod
    private let maxScale: CGFloat?

    init(
        device: MTLDevice,
        maxInFlightTextures: Int = 3,
        renderingMethod: RenderingMethod = .drawHierarchy,
        maxScale: CGFloat? = nil
    ) {
        self.device = device
        self.maxInFlightTextures = max(2, maxInFlightTextures)
        self.renderingMethod = renderingMethod
        if let maxScale, maxScale.isFinite, maxScale > 0 {
            self.maxScale = max(1, maxScale)
        } else {
            self.maxScale = nil
        }
    }

    deinit {
        pixelBuffer?.deallocate()
    }

    func textureFrom(view: UIView, roi: CGRect, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        assert(Thread.isMainThread, "ViewCapture.textureFrom must be called on the main thread.")
        guard roi.width > 0.001, roi.height > 0.001 else { return nil }

        let scale = resolvedScale(for: view)
        let pixelWidth = Int(round(roi.width * scale))
        let pixelHeight = Int(round(roi.height * scale))
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        prepareResourcesIfNeeded(pixelWidth: pixelWidth, pixelHeight: pixelHeight, scale: scale)
        guard bitmapContext != nil, let pixelBuffer else { return nil }

        var didDraw = false
        autoreleasepool {
            didDraw = render(view: view, roi: roi, scale: scale, pixelWidth: pixelWidth, pixelHeight: pixelHeight, method: renderingMethod)
        }
        guard didDraw else { return nil }

        let texture = acquireTextureSlot(pixelWidth: pixelWidth, pixelHeight: pixelHeight, commandBuffer: commandBuffer)
        guard let texture else { return nil }

        texture.replace(
            region: MTLRegionMake2D(0, 0, pixelWidth, pixelHeight),
            mipmapLevel: 0,
            withBytes: pixelBuffer,
            bytesPerRow: bytesPerRow
        )
        return texture
    }

    // MARK: - Private

    private func render(
        view: UIView,
        roi: CGRect,
        scale: CGFloat,
        pixelWidth: Int,
        pixelHeight: Int,
        method: RenderingMethod
    ) -> Bool {
        guard let bitmapContext else { return false }

        bitmapContext.saveGState()
        defer { bitmapContext.restoreGState() }

        let pixelRect = CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))
        bitmapContext.clear(pixelRect)

        if let backgroundColor = view.backgroundColor?.resolvedColor(with: view.traitCollection), backgroundColor.cgColor.alpha > 0 {
            bitmapContext.setFillColor(backgroundColor.cgColor)
            bitmapContext.fill(pixelRect)
        }

        bitmapContext.translateBy(x: 0, y: CGFloat(pixelHeight))
        bitmapContext.scaleBy(x: scale, y: -scale)
        bitmapContext.translateBy(x: -roi.origin.x, y: -roi.origin.y)

        switch method {
        case .drawHierarchy:
            UIGraphicsPushContext(bitmapContext)
            let success = view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
            UIGraphicsPopContext()
            return success
        case .layerRender:
            (view.layer.presentation() ?? view.layer).render(in: bitmapContext)
            return true
        }
    }

    private func resolvedScale(for view: UIView) -> CGFloat {
        let baseScale: CGFloat
        if let windowScale = view.window?.screen.scale, windowScale.isFinite {
            baseScale = windowScale
        } else {
            baseScale = view.contentScaleFactor
        }
        var scale = max(1, baseScale)
        if let maxScale {
            scale = min(scale, maxScale)
        }
        return scale
    }

    private func prepareResourcesIfNeeded(pixelWidth: Int, pixelHeight: Int, scale: CGFloat) {
        if pixelWidth == cachedPixelWidth, pixelHeight == cachedPixelHeight, abs(scale - cachedScale) < 0.0001, bitmapContext != nil {
            return
        }

        cachedPixelWidth = pixelWidth
        cachedPixelHeight = pixelHeight
        cachedScale = scale

        resetContext(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        resetTexturePool(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    private func resetContext(pixelWidth: Int, pixelHeight: Int) {
        let minimumBytesPerRow = pixelWidth * 4
        let alignedBytesPerRow = ((minimumBytesPerRow + 63) / 64) * 64
        bytesPerRow = alignedBytesPerRow

        let neededLength = bytesPerRow * pixelHeight
        if pixelBufferLength < neededLength {
            pixelBuffer?.deallocate()
            pixelBuffer = UnsafeMutableRawPointer.allocate(byteCount: neededLength, alignment: 64)
            pixelBufferLength = neededLength
        }

        bitmapContext = CGContext(
            data: pixelBuffer,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )
    }

    private func resetTexturePool(pixelWidth: Int, pixelHeight: Int) {
        slots = []
        nextSlotIndex = 0
        guard pixelWidth > 0, pixelHeight > 0 else { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: pixelWidth,
            height: pixelHeight,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        desc.cpuCacheMode = .writeCombined

        var newSlots: [TextureSlot] = []
        newSlots.reserveCapacity(maxInFlightTextures)
        for _ in 0..<maxInFlightTextures {
            guard let texture = device.makeTexture(descriptor: desc) else { break }
            newSlots.append(TextureSlot(texture: texture, inFlightCommandBuffer: nil))
        }

        slots = newSlots
    }

    private func acquireTextureSlot(pixelWidth: Int, pixelHeight: Int, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        if !slots.isEmpty {
            for _ in 0..<slots.count {
                let index = nextSlotIndex % slots.count
                nextSlotIndex = (index + 1) % slots.count

                if let inFlight = slots[index].inFlightCommandBuffer {
                    switch inFlight.status {
                    case .completed, .error:
                        slots[index].inFlightCommandBuffer = nil
                    default:
                        break
                    }
                }

                if slots[index].inFlightCommandBuffer == nil {
                    slots[index].inFlightCommandBuffer = commandBuffer
                    return slots[index].texture
                }
            }
        }

        // Fallback: GPU is still using every pooled texture. Allocate a one-off texture to avoid stalling.
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: pixelWidth,
            height: pixelHeight,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        desc.cpuCacheMode = .writeCombined
        return device.makeTexture(descriptor: desc)
    }
}
