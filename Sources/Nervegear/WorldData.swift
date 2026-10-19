import Foundation
import simd

struct Vector3: Codable, Equatable {
    var x: Float
    var y: Float
    var z: Float

    var simd: SIMD3<Float> { SIMD3(x, y, z) }

    init(_ value: SIMD3<Float>) {
        x = value.x
        y = value.y
        z = value.z
    }

    init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
}

struct Transform {
    var position: Vector3
    var scale: Vector3
    var rotationY: Float

    init(position: Vector3, scale: Vector3, rotationY: Float = 0) {
        self.position = position
        self.scale = scale
        self.rotationY = rotationY
    }

    var matrix: simd_float4x4 {
        let translation = simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(position.x, position.y, position.z, 1)
        ))
        let scaling = simd_float4x4(columns: (
            SIMD4(scale.x, 0, 0, 0),
            SIMD4(0, scale.y, 0, 0),
            SIMD4(0, 0, scale.z, 0),
            SIMD4(0, 0, 0, 1)
        ))
        let cosine = cos(rotationY)
        let sine = sin(rotationY)
        let rotation = simd_float4x4(columns: (
            SIMD4(cosine, 0, sine, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(-sine, 0, cosine, 0),
            SIMD4(0, 0, 0, 1)
        ))
        return translation * rotation * scaling
    }
}

enum Primitive: String, Codable, CaseIterable {
    case cube
    case sphere
    case cylinder
    case terrain
}

enum MeshID: Hashable {
    case primitive(Primitive)
    case asset(name: String, part: Int)
}

struct WorldSettings: Codable {
    var extent: Float
    var seed: UInt64
}

struct AssetPlacement: Codable {
    var asset: String
    var x: Float
    var z: Float
    var scale: Float
    var rotation: Float
}

struct VegetationScatter: Codable {
    var asset: String
    var count: Int
    var minimumScale: Float
    var maximumScale: Float
    var pathClearance: Float
}

struct SceneDocument: Codable {
    var version: Int
    var id: String
    var name: String
    var aincrad2Location: String
    var world: WorldSettings
    var playerStart: Vector3
    var objects: [AssetPlacement]
    var vegetation: [VegetationScatter]
}

struct MaterialDefinition: Codable {
    var id: String
    var color: [Float]
}

struct MaterialsDocument: Codable {
    var version: Int
    var materials: [MaterialDefinition]
}

struct RuntimeObject {
    var mesh: MeshID
    var material: String
    var transform: Transform
}

struct PlayerState: Codable {
    var position: Vector3
    var yaw: Float

    static let initial = PlayerState(position: Vector3(x: 0, y: 0, z: 0), yaw: 0)

    var isValid: Bool {
        [position.x, position.y, position.z, yaw].allSatisfy(\.isFinite)
    }
}

struct SessionDocument: Codable {
    var version: Int
    var player: PlayerState
}

enum WorldDataError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let detail): return detail
        }
    }
}

enum WorldData {
    static func decodeScene(at url: URL) throws -> SceneDocument {
        let document = try JSONDecoder().decode(SceneDocument.self, from: Data(contentsOf: url))
        try validate(document)
        return document
    }

    static func decodeMaterials(at url: URL) throws -> MaterialsDocument {
        let document = try JSONDecoder().decode(MaterialsDocument.self, from: Data(contentsOf: url))
        try validate(document)
        return document
    }

    static func decodeSession(at url: URL) throws -> SessionDocument? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let session = try JSONDecoder().decode(SessionDocument.self, from: Data(contentsOf: url))
        guard session.version == 2 else { throw WorldDataError.invalid("session version \(session.version) is unsupported") }
        guard session.player.isValid else { throw WorldDataError.invalid("session player contains invalid values") }
        return session
    }

    static func validate(_ scene: SceneDocument) throws {
        guard scene.version == 1 else { throw WorldDataError.invalid("scene version \(scene.version) is unsupported") }
        guard !scene.id.isEmpty, !scene.name.isEmpty, !scene.aincrad2Location.isEmpty else {
            throw WorldDataError.invalid("scene identity, name, and Aincrad2 location must not be empty")
        }
        guard scene.world.extent.isFinite && (8...256).contains(scene.world.extent) else {
            throw WorldDataError.invalid("scene world.extent must be between 8 and 256")
        }
        let position = scene.playerStart
        guard [position.x, position.y, position.z].allSatisfy(\.isFinite),
              abs(position.x) < scene.world.extent * 0.5 - 2,
              abs(position.z) < scene.world.extent * 0.5 - 2 else {
            throw WorldDataError.invalid("scene playerStart must be finite and inside the world bounds")
        }
        var objectIDs = Set<String>()
        for object in scene.objects {
            guard isAssetIdentifier(object.asset),
                  [object.x, object.z, object.scale, object.rotation].allSatisfy(\.isFinite),
                  (0.05...12).contains(object.scale),
                  abs(object.x) < scene.world.extent * 0.5 - 1,
                  abs(object.z) < scene.world.extent * 0.5 - 1,
                  objectIDs.insert(object.asset).inserted else {
                throw WorldDataError.invalid("scene objects must have unique asset names and finite transforms inside the world bounds")
            }
        }
        var scatterAssets = Set<String>()
        var totalInstances = 0
        for scatter in scene.vegetation {
            guard isAssetIdentifier(scatter.asset),
                  (0...5000).contains(scatter.count),
                  scatter.minimumScale.isFinite && scatter.maximumScale.isFinite,
                  (0.1...8).contains(scatter.minimumScale),
                  (scatter.minimumScale...8).contains(scatter.maximumScale),
                  scatter.pathClearance.isFinite && (0...scene.world.extent * 0.25).contains(scatter.pathClearance),
                  scatterAssets.insert(scatter.asset).inserted else {
                throw WorldDataError.invalid("scene vegetation entries need unique asset names and finite, bounded scatter settings")
            }
            totalInstances += scatter.count
        }
        guard totalInstances <= 5000 else {
            throw WorldDataError.invalid("scene vegetation may contain at most 5000 instances")
        }
    }

    static func validate(_ materials: MaterialsDocument) throws {
        guard materials.version == 1 else { throw WorldDataError.invalid("materials version \(materials.version) is unsupported") }
        guard !materials.materials.isEmpty else { throw WorldDataError.invalid("materials file must define at least one material") }
        var identifiers = Set<String>()
        for material in materials.materials {
            guard !material.id.isEmpty && identifiers.insert(material.id).inserted else {
                throw WorldDataError.invalid("materials has an empty or duplicate id: \(material.id)")
            }
            guard material.color.count == 4 && material.color.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                throw WorldDataError.invalid("material \(material.id) color must contain four finite values from 0 to 1")
            }
        }
        guard identifiers.contains("ground") else {
            throw WorldDataError.invalid("materials must define ground")
        }
    }

    static func assetNames(in scene: SceneDocument) -> Set<String> {
        Set(scene.objects.map(\.asset) + scene.vegetation.map(\.asset))
    }

    static func makeObjects(
        scene: SceneDocument,
        materials: MaterialsDocument,
        assets: AssetLibrary
    ) throws -> [RuntimeObject] {
        guard materials.materials.contains(where: { $0.id == "ground" }) else {
            throw WorldDataError.invalid("materials must define ground")
        }
        var objects = [RuntimeObject](arrayLiteral: RuntimeObject(
            mesh: .primitive(.terrain),
            material: "ground",
            transform: Transform(position: Vector3(x: 0, y: 0, z: 0), scale: Vector3(x: 1, y: 1, z: 1))
        ))
        var random = SplitMix64(seed: scene.world.seed)
        for placement in scene.objects {
            guard let model = assets.models[placement.asset] else {
                throw WorldDataError.invalid("scene object references missing asset \(placement.asset)")
            }
            let transform = assetTransform(
                x: placement.x,
                z: placement.z,
                scale: placement.scale,
                rotation: placement.rotation,
                model: model,
                world: scene.world
            )
            append(model: model, transform: transform, to: &objects)
        }
        for scatter in scene.vegetation {
            guard let model = assets.models[scatter.asset] else {
                throw WorldDataError.invalid("scene vegetation references missing asset \(scatter.asset)")
            }
            var placed = 0
            var attempts = 0
            while placed < scatter.count && attempts < scatter.count * 80 + 1 {
                attempts += 1
                let limit = scene.world.extent * 0.5 - 1
                let x = random.range(-limit, limit)
                let z = random.range(-limit, limit)
                let scale = random.range(scatter.minimumScale, scatter.maximumScale)
                guard abs(x) >= scatter.pathClearance,
                      simd_distance(SIMD2(x, z), SIMD2(scene.playerStart.x, scene.playerStart.z)) >= 1.5,
                      !scene.objects.contains(where: { simd_distance(SIMD2(x, z), SIMD2($0.x, $0.z)) < 1.6 * $0.scale + 0.8 }),
                      scatter.asset == "Wild_Grass" || !objects.contains(where: {
                          guard case .asset(let name, _) = $0.mesh, name == scatter.asset else { return false }
                          let offset = SIMD2(x - $0.transform.position.x, z - $0.transform.position.z)
                          return simd_length(offset) < 0.8 * scale
                      }) else {
                    continue
                }
                let transform = assetTransform(
                    x: x,
                    z: z,
                    scale: scale,
                    rotation: random.range(0, 2 * .pi),
                    model: model,
                    world: scene.world
                )
                append(model: model, transform: transform, to: &objects)
                placed += 1
            }
            guard placed == scatter.count else {
                throw WorldDataError.invalid("could not place all \(scatter.asset) instances")
            }
        }
        return objects
    }

    static func terrainHeight(x: Float, z: Float, world: WorldSettings) -> Float {
        0.48 * sin(x * 0.075) * cos(z * 0.068)
            + 0.24 * sin((x + z) * 0.13)
            + 0.10 * sin(x * 0.21 - z * 0.16)
    }

    private static func assetTransform(
        x: Float,
        z: Float,
        scale: Float,
        rotation: Float,
        model: ImportedAssetModel,
        world: WorldSettings
    ) -> Transform {
        Transform(
            position: Vector3(x: x, y: terrainHeight(x: x, z: z, world: world) - model.minimumY * scale, z: z),
            scale: Vector3(x: scale, y: scale, z: scale),
            rotationY: rotation
        )
    }

    private static func append(model: ImportedAssetModel, transform: Transform, to objects: inout [RuntimeObject]) {
        for part in model.parts {
            objects.append(RuntimeObject(mesh: part.mesh, material: part.material, transform: transform))
        }
    }

    private static func isAssetIdentifier(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_]+$"#, options: .regularExpression) != nil
    }
}

struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func unit() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }

    mutating func range(_ minimum: Float, _ maximum: Float) -> Float {
        minimum + (maximum - minimum) * unit()
    }
}
