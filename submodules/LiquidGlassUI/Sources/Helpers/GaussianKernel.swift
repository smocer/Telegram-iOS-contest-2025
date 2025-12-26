import Foundation

/// Maximum blur radius supported by the shader path (matches GLSL: 200).
let kMaxBlurRadius: Int = 200

/// Replicates the WebGL Gaussian kernel generator: sigma = radius / 3, normalized, indices 0...radius.
func computeGaussianKernelByRadius(radius: Int) -> [Float] {
    let clamped = max(0, min(radius, kMaxBlurRadius))
    if clamped == 0 {
        return [1.0]
    }
    let sigma = Float(clamped) / 3.0
    var kernel: [Float] = []
    kernel.reserveCapacity(clamped + 1)
    var sum: Float = 0
    for i in 0...clamped {
        let fi = Float(i)
        let weight = exp(-0.5 * (fi * fi) / (sigma * sigma))
        kernel.append(weight)
        sum += i == 0 ? weight : weight * 2
    }
    let invSum = 1 / sum
    for idx in kernel.indices {
        kernel[idx] *= invSum
    }
    return kernel
}
