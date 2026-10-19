import Foundation

enum TerrainHeight {
    private static let gradients: [SIMD2<Float>] = (0..<256).map { index in
        let angle = Float(index) / 256 * 2 * .pi
        return SIMD2(cos(angle), sin(angle))
    }

    static func value(x: Float, z: Float, seed: UInt64) -> Float {
        let broad = gradientNoise(x: x / 18, z: z / 16, seed: seed, salt: 0x2A31) * 1.25
        let rolling = gradientNoise(x: x / 6.2, z: z / 6.8, seed: seed, salt: 0x6175) * 0.34
        let hummocks = gradientNoise(x: x / 2.6, z: z / 2.9, seed: seed, salt: 0x9B07) * 0.085
        return broad + rolling + hummocks
    }

    private static func gradientNoise(x: Float, z: Float, seed: UInt64, salt: UInt64) -> Float {
        let latticeX = Int(floor(Double(x)))
        let latticeZ = Int(floor(Double(z)))
        let fractionX = x - Float(latticeX)
        let fractionZ = z - Float(latticeZ)
        let weightX = fade(fractionX)
        let weightZ = fade(fractionZ)
        let top = mix(
            corner(seed: seed, salt: salt, x: latticeX, z: latticeZ, dx: fractionX, dz: fractionZ),
            corner(seed: seed, salt: salt, x: latticeX + 1, z: latticeZ, dx: fractionX - 1, dz: fractionZ),
            weightX
        )
        let bottom = mix(
            corner(seed: seed, salt: salt, x: latticeX, z: latticeZ + 1, dx: fractionX, dz: fractionZ - 1),
            corner(seed: seed, salt: salt, x: latticeX + 1, z: latticeZ + 1, dx: fractionX - 1, dz: fractionZ - 1),
            weightX
        )
        return mix(top, bottom, weightZ) * Float(2).squareRoot()
    }

    private static func corner(seed: UInt64, salt: UInt64, x: Int, z: Int, dx: Float, dz: Float) -> Float {
        let gradient = gradients[Int(hash(seed: seed, salt: salt, x: x, z: z) & 255)]
        return gradient.x * dx + gradient.y * dz
    }

    private static func hash(seed: UInt64, salt: UInt64, x: Int, z: Int) -> UInt64 {
        var value = seed ^ salt
        value = (value ^ UInt64(bitPattern: Int64(x))) &* 0x9E3779B97F4A7C15
        value = (value ^ UInt64(bitPattern: Int64(z))) &* 0xBF58476D1CE4E5B9
        value ^= value >> 30
        value = value &* 0xBF58476D1CE4E5B9
        value ^= value >> 27
        value = value &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    private static func fade(_ value: Float) -> Float {
        value * value * value * (value * (value * 6 - 15) + 10)
    }

    private static func mix(_ first: Float, _ second: Float, _ amount: Float) -> Float {
        first + (second - first) * amount
    }
}
