import Metal

public struct MetalContext {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let library: MTLLibrary

    public init(device: MTLDevice = MTLCreateSystemDefaultDevice()!) {
        self.device = device
        commandQueue = device.makeCommandQueue()!
        library = device.makeDefaultLibrary()!
    }

    public init(device: MTLDevice = MTLCreateSystemDefaultDevice()!, library: MTLLibrary, commandQueue: MTLCommandQueue? = nil) {
        self.device = device
        self.library = library
        if let commandQueue {
            self.commandQueue = commandQueue
        } else {
            self.commandQueue = device.makeCommandQueue()!
        }
    }
}
