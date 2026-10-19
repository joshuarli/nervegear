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
            SIMD4(cosine, 0, -sine, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(sine, 0, cosine, 0),
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
    case grass
    case flower
}

enum MeshID: Hashable {
    case primitive(Primitive)
    case asset(name: String, part: Int)

    var castsShadow: Bool {
        switch self {
        case .primitive(.grass), .primitive(.flower): false
        default: true
        }
    }
}

struct WorldSettings: Codable {
    var extent: Float
    var seed: UInt64
}

struct MeadowSettings: Codable {
    var grassCount: Int
    var flowerCount: Int
}

struct AssetPlacement: Codable {
    var asset: String
    var position: Vector3
    var scale: Float
    var rotation: Float
}

struct SceneDocument: Codable {
    var version: Int
    var id: String
    var name: String
    var aincrad2Location: String
    var world: WorldSettings
    var meadow: MeadowSettings
    var playerStart: Vector3
    var objects: [AssetPlacement]
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
        guard scene.world.extent.isFinite && (32...256).contains(scene.world.extent) else {
            throw WorldDataError.invalid("scene world.extent must be between 32 and 256")
        }
        guard (0...24_000).contains(scene.meadow.grassCount) else {
            throw WorldDataError.invalid("scene meadow.grassCount must be between 0 and 24000")
        }
        guard (0...2_000).contains(scene.meadow.flowerCount) else {
            throw WorldDataError.invalid("scene meadow.flowerCount must be between 0 and 2000")
        }
        let position = scene.playerStart
        guard [position.x, position.y, position.z].allSatisfy(\.isFinite),
              abs(position.x) < scene.world.extent * 0.5 - 2,
              abs(position.z) < scene.world.extent * 0.5 - 2 else {
            throw WorldDataError.invalid("scene playerStart must be finite and inside the world bounds")
        }
        var objectIDs = Set<String>()
        for object in scene.objects {
            let position = object.position
            guard object.asset.range(of: #"^[A-Za-z0-9_]+$"#, options: .regularExpression) != nil,
                  [position.x, position.y, position.z, object.scale, object.rotation].allSatisfy(\.isFinite),
                  (0.05...12).contains(object.scale),
                  abs(position.x) < scene.world.extent * 0.5 - 1,
                  abs(position.z) < scene.world.extent * 0.5 - 1,
                  objectIDs.insert(object.asset).inserted else {
                throw WorldDataError.invalid("scene objects must have unique asset names and finite transforms inside the world bounds")
            }
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
    }

    static func makeObjects(
        scene: SceneDocument,
        materials: MaterialsDocument,
        assets: AssetLibrary
    ) throws -> [RuntimeObject] {
        let materialIDs = Set(materials.materials.map(\.id))
        let required = ["ground", "grass", "grass-light", "flower-white", "flower-gold", "flower-pink"]
        guard let missing = required.first(where: { !materialIDs.contains($0) }) else {
            var objects = try makeMeadow(scene: scene)
            for placement in scene.objects {
                guard let model = assets.models[placement.asset] else {
                    throw WorldDataError.invalid("scene object references missing asset \(placement.asset)")
                }
                var position = placement.position
                position.y = terrainHeight(x: position.x, z: position.z, world: scene.world) - model.minimumY * placement.scale
                let transform = Transform(
                    position: position,
                    scale: Vector3(x: placement.scale, y: placement.scale, z: placement.scale),
                    rotationY: placement.rotation
                )
                for mesh in model.meshes {
                    objects.append(RuntimeObject(mesh: mesh, material: "asset", transform: transform))
                }
            }
            return objects
        }
        throw WorldDataError.invalid("materials must define \(missing)")
    }

    static func terrainHeight(x: Float, z: Float, world: WorldSettings) -> Float {
        0.48 * sin(x * 0.075) * cos(z * 0.068)
            + 0.24 * sin((x + z) * 0.13)
            + 0.10 * sin(x * 0.21 - z * 0.16)
    }

    private static func makeMeadow(scene: SceneDocument) throws -> [RuntimeObject] {
        var objects = [RuntimeObject(
            mesh: .primitive(.terrain),
            material: "ground",
            transform: Transform(position: Vector3(x: 0, y: 0, z: 0), scale: Vector3(x: 1, y: 1, z: 1))
        )]
        var random = SplitMix64(seed: scene.world.seed)
        let halfExtent = scene.world.extent * 0.47
        var grassPlaced = 0
        var attempts = 0
        while grassPlaced < scene.meadow.grassCount && attempts < scene.meadow.grassCount * 8 + 1 {
            attempts += 1
            let x = random.range(-halfExtent, halfExtent)
            let z = random.range(-halfExtent, halfExtent)
            if simd_distance(SIMD2(x, z), SIMD2(scene.playerStart.x, scene.playerStart.z)) < 1.4 { continue }
            grassPlaced += 1
            let lightGrass = random.next().isMultiple(of: 5)
            objects.append(RuntimeObject(
                mesh: .primitive(.grass),
                material: lightGrass ? "grass-light" : "grass",
                transform: Transform(
                    position: Vector3(x: x, y: terrainHeight(x: x, z: z, world: scene.world), z: z),
                    scale: Vector3(x: random.range(0.7, 1.35), y: random.range(0.55, 1.15), z: random.range(0.7, 1.35))
                )
            ))
        }
        guard grassPlaced == scene.meadow.grassCount else {
            throw WorldDataError.invalid("could not place all meadow grass instances")
        }

        let flowerMaterials = ["flower-white", "flower-gold", "flower-pink"]
        var flowersPlaced = 0
        attempts = 0
        while flowersPlaced < scene.meadow.flowerCount && attempts < scene.meadow.flowerCount * 8 + 1 {
            attempts += 1
            let x = random.range(-halfExtent, halfExtent)
            let z = random.range(-halfExtent, halfExtent)
            if simd_distance(SIMD2(x, z), SIMD2(scene.playerStart.x, scene.playerStart.z)) < 1.8 { continue }
            flowersPlaced += 1
            objects.append(RuntimeObject(
                mesh: .primitive(.flower),
                material: flowerMaterials[Int(random.next() % UInt64(flowerMaterials.count))],
                transform: Transform(
                    position: Vector3(x: x, y: terrainHeight(x: x, z: z, world: scene.world), z: z),
                    scale: Vector3(x: random.range(0.34, 0.52), y: random.range(0.5, 0.82), z: random.range(0.34, 0.52))
                )
            ))
        }
        guard flowersPlaced == scene.meadow.flowerCount else {
            throw WorldDataError.invalid("could not place all meadow flowers")
        }
        return objects
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
