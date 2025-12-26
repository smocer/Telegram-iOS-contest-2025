import Foundation
import Metal

private final class LiquidGlassBundleMarker: NSObject {
}

enum LiquidGlassMetalBundle {
    static func load() -> Bundle {
        let mainBundle = Bundle(for: LiquidGlassBundleMarker.self)
        guard let path = mainBundle.path(forResource: "LiquidGlassMetalSourcesBundle", ofType: "bundle") else {
            preconditionFailure("LiquidGlassMetalSourcesBundle.bundle not found")
        }
        guard let bundle = Bundle(path: path) else {
            preconditionFailure("Failed to load LiquidGlassMetalSourcesBundle.bundle")
        }
        return bundle
    }
}

public enum LiquidGlassSharedContext {
    public static let metalContext: MetalContext = {
        let device = MTLCreateSystemDefaultDevice()!
        let library = try! device.makeDefaultLibrary(bundle: LiquidGlassMetalBundle.load())
        return MetalContext(device: device, library: library)
    }()
}

