import Foundation
import Metal
import simd

struct SurfaceDefinition: Decodable {
    let baseColorFactor: [Float]
    let roughnessFactor: Float
    let metallicFactor: Float
    let alphaCutoff: Float
    let doubleSided: Bool
    let baseColor: String?
    let normal: String?
    let roughness: String?
    let metallic: String?
    let ambientOcclusion: String?
    let opacity: String?
    let uvScale: Float?
}

struct AssetMaterialCatalog: Decodable {
    let version: Int
    let terrainLayers: [String]
    let materials: [String: SurfaceDefinition]
}

struct SurfaceMaterial: @unchecked Sendable {
    let baseColor: MTLTexture?
    let normal: MTLTexture?
    let roughness: MTLTexture?
    let metallic: MTLTexture?
    let ambientOcclusion: MTLTexture?
    let opacity: MTLTexture?
    let baseColorFactor: SIMD4<Float>
    let roughnessFactor: Float
    let metallicFactor: Float
    let alphaCutoff: Float
    let uvScale: Float
    let alphaMasked: Bool
    let doubleSided: Bool

    var uniforms: MaterialUniforms {
        MaterialUniforms(
            baseColorFactor: baseColorFactor,
            surfaceProperties: SIMD4(roughnessFactor, metallicFactor, alphaCutoff, uvScale),
            flags: SIMD4(
                alphaMasked ? 1 : 0,
                doubleSided ? 1 : 0,
                0,
                normal == nil ? 0 : 1
            )
        )
    }

    static let defaultMaterial = SurfaceMaterial(
        baseColor: nil,
        normal: nil,
        roughness: nil,
        metallic: nil,
        ambientOcclusion: nil,
        opacity: nil,
        baseColorFactor: SIMD4(repeating: 1),
        roughnessFactor: 0.82,
        metallicFactor: 0,
        alphaCutoff: 0.48,
        uvScale: 1,
        alphaMasked: false,
        doubleSided: false
    )

    func uniforms(forTerrain: Bool) -> MaterialUniforms {
        var value = uniforms
        if forTerrain {
            value.flags.z = 1
        }
        return value
    }
}

struct MaterialUniforms {
    var baseColorFactor: SIMD4<Float>
    var surfaceProperties: SIMD4<Float>
    var flags: SIMD4<UInt32>
}

struct TerrainMaterialUniforms {
    var forest: MaterialUniforms
    var dirt: MaterialUniforms
    var rock: MaterialUniforms

    init(layers: [SurfaceMaterial]) {
        forest = layers[0].uniforms
        dirt = layers[1].uniforms
        rock = layers[2].uniforms
    }
}
