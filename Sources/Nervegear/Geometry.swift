import Metal
import simd

struct MeshVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var color: SIMD4<Float>
    var texCoord: SIMD2<Float>

    init(position: SIMD3<Float>, normal: SIMD3<Float>, color: SIMD4<Float>, texCoord: SIMD2<Float> = .zero) {
        self.position = position
        self.normal = normal
        self.color = color
        self.texCoord = texCoord
    }
}

struct MeshBuffers {
    let vertices: MTLBuffer
    let indices: MTLBuffer
    let indexCount: Int
    let indexType: MTLIndexType
    let vertexOffset: Int
    let indexOffset: Int
    let texture: MTLTexture?

    init(
        vertices: MTLBuffer,
        indices: MTLBuffer,
        indexCount: Int,
        indexType: MTLIndexType = .uint32,
        vertexOffset: Int = 0,
        indexOffset: Int = 0,
        texture: MTLTexture? = nil
    ) {
        self.vertices = vertices
        self.indices = indices
        self.indexCount = indexCount
        self.indexType = indexType
        self.vertexOffset = vertexOffset
        self.indexOffset = indexOffset
        self.texture = texture
    }
}

struct InstanceData {
    var modelMatrix: simd_float4x4
    var color: SIMD4<Float>
}

struct FrameUniforms {
    var viewProjection: simd_float4x4
    var lightViewProjection: simd_float4x4
    var lightDirection: SIMD4<Float>
    var shadowTexelSize: SIMD4<Float>
}

enum GeometryFactory {
    static func makeMeshes(device: MTLDevice, world: WorldSettings) throws -> [MeshID: MeshBuffers] {
        var meshes: [MeshID: MeshBuffers] = [:]
        meshes[.primitive(.cube)] = try upload(device: device, mesh: makeCube())
        meshes[.primitive(.sphere)] = try upload(device: device, mesh: makeSphere(rings: 12, segments: 18))
        meshes[.primitive(.cylinder)] = try upload(device: device, mesh: makeCylinder(segments: 16))
        meshes[.primitive(.terrain)] = try upload(device: device, mesh: makeTerrain(world: world))
        meshes[.primitive(.grass)] = try upload(device: device, mesh: makeGrass())
        meshes[.primitive(.flower)] = try upload(device: device, mesh: makeFlower())
        return meshes
    }

    static func upload(device: MTLDevice, mesh: (vertices: [MeshVertex], indices: [UInt32])) throws -> MeshBuffers {
        guard let vertexBuffer = uploadVertices(device: device, vertices: mesh.vertices), let indexBuffer = device.makeBuffer(
            bytes: mesh.indices,
            length: mesh.indices.count * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else {
            throw RendererError.gpu("Metal could not allocate geometry buffers")
        }
        return MeshBuffers(vertices: vertexBuffer, indices: indexBuffer, indexCount: mesh.indices.count)
    }

    static func uploadVertices(device: MTLDevice, vertices: [MeshVertex]) -> MTLBuffer? {
        guard !vertices.isEmpty else { return nil }
        return device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<MeshVertex>.stride,
            options: .storageModeShared
        )
    }

    private static func makeCube() -> (vertices: [MeshVertex], indices: [UInt32]) {
        let faces: [(SIMD3<Float>, [SIMD3<Float>])] = [
            (SIMD3(0, 0, 1), [SIMD3(-0.5, -0.5, 0.5), SIMD3(0.5, -0.5, 0.5), SIMD3(0.5, 0.5, 0.5), SIMD3(-0.5, 0.5, 0.5)]),
            (SIMD3(0, 0, -1), [SIMD3(0.5, -0.5, -0.5), SIMD3(-0.5, -0.5, -0.5), SIMD3(-0.5, 0.5, -0.5), SIMD3(0.5, 0.5, -0.5)]),
            (SIMD3(1, 0, 0), [SIMD3(0.5, -0.5, 0.5), SIMD3(0.5, -0.5, -0.5), SIMD3(0.5, 0.5, -0.5), SIMD3(0.5, 0.5, 0.5)]),
            (SIMD3(-1, 0, 0), [SIMD3(-0.5, -0.5, -0.5), SIMD3(-0.5, -0.5, 0.5), SIMD3(-0.5, 0.5, 0.5), SIMD3(-0.5, 0.5, -0.5)]),
            (SIMD3(0, 1, 0), [SIMD3(-0.5, 0.5, 0.5), SIMD3(0.5, 0.5, 0.5), SIMD3(0.5, 0.5, -0.5), SIMD3(-0.5, 0.5, -0.5)]),
            (SIMD3(0, -1, 0), [SIMD3(-0.5, -0.5, -0.5), SIMD3(0.5, -0.5, -0.5), SIMD3(0.5, -0.5, 0.5), SIMD3(-0.5, -0.5, 0.5)])
        ]
        var vertices: [MeshVertex] = []
        var indices: [UInt32] = []
        for (normal, corners) in faces {
            let start = UInt32(vertices.count)
            vertices.append(contentsOf: corners.map { MeshVertex(position: $0, normal: normal, color: SIMD4(repeating: 1)) })
            indices.append(contentsOf: [start, start + 1, start + 2, start, start + 2, start + 3])
        }
        return (vertices, indices)
    }

    private static func makeSphere(rings: Int, segments: Int) -> (vertices: [MeshVertex], indices: [UInt32]) {
        var vertices: [MeshVertex] = []
        var indices: [UInt32] = []
        for ring in 0...rings {
            let phi = Float(ring) * .pi / Float(rings)
            for segment in 0...segments {
                let theta = Float(segment) * 2 * .pi / Float(segments)
                let normal = SIMD3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
                vertices.append(MeshVertex(position: normal * 0.5, normal: normal, color: SIMD4(repeating: 1)))
            }
        }
        let row = segments + 1
        for ring in 0..<rings {
            for segment in 0..<segments {
                let a = UInt32(ring * row + segment)
                let b = UInt32(a + UInt32(row))
                indices.append(contentsOf: [a, b, a + 1, a + 1, b, b + 1])
            }
        }
        return (vertices, indices)
    }

    private static func makeCylinder(segments: Int) -> (vertices: [MeshVertex], indices: [UInt32]) {
        var vertices: [MeshVertex] = []
        var indices: [UInt32] = []
        for segment in 0...segments {
            let angle = Float(segment) * 2 * .pi / Float(segments)
            let normal = SIMD3(cos(angle), 0, sin(angle))
            vertices.append(MeshVertex(position: SIMD3(0.5 * cos(angle), -0.5, 0.5 * sin(angle)), normal: normal, color: SIMD4(repeating: 1)))
            vertices.append(MeshVertex(position: SIMD3(0.5 * cos(angle), 0.5, 0.5 * sin(angle)), normal: normal, color: SIMD4(repeating: 1)))
        }
        for segment in 0..<segments {
            let lower = UInt32(segment * 2)
            let upper = lower + 1
            let nextLower = lower + 2
            let nextUpper = lower + 3
            indices.append(contentsOf: [lower, nextLower, upper, upper, nextLower, nextUpper])
        }
        let bottomCenter = UInt32(vertices.count)
        vertices.append(MeshVertex(position: SIMD3(0, -0.5, 0), normal: SIMD3(0, -1, 0), color: SIMD4(repeating: 1)))
        let topCenter = UInt32(vertices.count)
        vertices.append(MeshVertex(position: SIMD3(0, 0.5, 0), normal: SIMD3(0, 1, 0), color: SIMD4(repeating: 1)))
        for segment in 0..<segments {
            let current = UInt32(segment * 2)
            let next = current + 2
            indices.append(contentsOf: [bottomCenter, next, current])
            indices.append(contentsOf: [topCenter, current + 1, next + 1])
        }
        return (vertices, indices)
    }

    private static func makeTerrain(world: WorldSettings) -> (vertices: [MeshVertex], indices: [UInt32]) {
        let resolution = 112
        let half = world.extent * 0.5
        var vertices: [MeshVertex] = []
        var indices: [UInt32] = []
        for row in 0...resolution {
            let z = -half + Float(row) / Float(resolution) * world.extent
            for column in 0...resolution {
                let x = -half + Float(column) / Float(resolution) * world.extent
                let y = WorldData.terrainHeight(x: x, z: z, world: world)
                let dx = WorldData.terrainHeight(x: x + 0.12, z: z, world: world) - WorldData.terrainHeight(x: x - 0.12, z: z, world: world)
                let dz = WorldData.terrainHeight(x: x, z: z + 0.12, world: world) - WorldData.terrainHeight(x: x, z: z - 0.12, world: world)
                let normal = simd_normalize(SIMD3(-dx, 0.24, -dz))
                let meadow = 0.92 + 0.06 * sin(x * 0.17 + z * 0.11) * cos(z * 0.19)
                let color = SIMD4<Float>(
                    meadow * 0.94,
                    meadow,
                    meadow * 0.88,
                    1
                )
                vertices.append(MeshVertex(position: SIMD3(x, y, z), normal: normal, color: color))
            }
        }
        let rowWidth = resolution + 1
        for row in 0..<resolution {
            for column in 0..<resolution {
                let a = UInt32(row * rowWidth + column)
                let b = a + UInt32(rowWidth)
                indices.append(contentsOf: [a, a + 1, b, a + 1, b + 1, b])
            }
        }
        return (vertices, indices)
    }

    private static func makeGrass() -> (vertices: [MeshVertex], indices: [UInt32]) {
        var vertices: [MeshVertex] = []
        var indices: [UInt32] = []
        let directions: [SIMD2<Float>] = [
            SIMD2(1, 0),
            SIMD2(-0.5, 0.866),
            SIMD2(-0.5, -0.866),
            SIMD2(0.72, 0.69),
            SIMD2(-0.89, 0.45)
        ]
        for (blade, direction) in directions.enumerated() {
            let side = SIMD2(-direction.y, direction.x) * 0.075
            let lean = SIMD3(direction.x * 0.13, 0, direction.y * 0.13)
            let height = 0.72 + Float(blade % 3) * 0.10
            let normal = simd_normalize(SIMD3(-direction.x, 0.25, -direction.y))
            let baseLeft = SIMD3(-side.x, 0, -side.y)
            let baseRight = SIMD3(side.x, 0, side.y)
            let tip = lean + SIMD3(0, height, 0)
            let color = SIMD4<Float>(0.86 + Float(blade % 2) * 0.08, 0.94, 0.82, 1)
            let start = UInt32(vertices.count)
            vertices.append(contentsOf: [
                MeshVertex(position: baseLeft, normal: normal, color: color),
                MeshVertex(position: baseRight, normal: normal, color: color),
                MeshVertex(position: SIMD3(side.x * 0.34, height * 0.56, side.y * 0.34) + lean * 0.42, normal: normal, color: color),
                MeshVertex(position: tip, normal: normal, color: color)
            ])
            indices.append(contentsOf: [start, start + 1, start + 2, start + 2, start + 1, start + 3])
        }
        return (vertices, indices)
    }

    private static func makeFlower() -> (vertices: [MeshVertex], indices: [UInt32]) {
        var vertices: [MeshVertex] = []
        var indices: [UInt32] = []
        let stemStart = UInt32(vertices.count)
        let stemColor = SIMD4<Float>(0.54, 0.78, 0.42, 1)
        vertices.append(contentsOf: [
            MeshVertex(position: SIMD3(-0.025, 0, 0), normal: SIMD3(0, 0, 1), color: stemColor),
            MeshVertex(position: SIMD3(0.025, 0, 0), normal: SIMD3(0, 0, 1), color: stemColor),
            MeshVertex(position: SIMD3(-0.016, 0.82, 0), normal: SIMD3(0, 0, 1), color: stemColor),
            MeshVertex(position: SIMD3(0.016, 0.82, 0), normal: SIMD3(0, 0, 1), color: stemColor)
        ])
        indices.append(contentsOf: [stemStart, stemStart + 1, stemStart + 2, stemStart + 1, stemStart + 3, stemStart + 2])

        for petal in 0..<5 {
            let angle = Float(petal) * 2 * .pi / 5
            let direction = SIMD2(cos(angle), sin(angle))
            let side = SIMD2(-direction.y, direction.x) * 0.065
            let center = SIMD3<Float>(0, 0.84, 0)
            let outer = SIMD3(direction.x * 0.25, 0.82, direction.y * 0.25)
            let start = UInt32(vertices.count)
            let petalColor = SIMD4<Float>(repeating: 1)
            vertices.append(contentsOf: [
                MeshVertex(position: center, normal: SIMD3(0, 1, 0), color: petalColor),
                MeshVertex(position: SIMD3(side.x, 0.86, side.y), normal: SIMD3(0, 1, 0), color: petalColor),
                MeshVertex(position: outer + SIMD3(side.x * 0.44, 0, side.y * 0.44), normal: SIMD3(0, 1, 0), color: petalColor),
                MeshVertex(position: outer - SIMD3(side.x * 0.44, 0, side.y * 0.44), normal: SIMD3(0, 1, 0), color: petalColor)
            ])
            indices.append(contentsOf: [start, start + 1, start + 2, start, start + 2, start + 3])
        }
        return (vertices, indices)
    }
}
