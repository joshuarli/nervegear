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

    init(
        vertices: MTLBuffer,
        indices: MTLBuffer,
        indexCount: Int,
        indexType: MTLIndexType = .uint32,
        vertexOffset: Int = 0,
        indexOffset: Int = 0
    ) {
        self.vertices = vertices
        self.indices = indices
        self.indexCount = indexCount
        self.indexType = indexType
        self.vertexOffset = vertexOffset
        self.indexOffset = indexOffset
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
    var cameraPosition: SIMD4<Float>
    var shadowTexelSize: SIMD4<Float>
}

enum GeometryFactory {
    static func makeMeshes(device: MTLDevice, world: WorldSettings) throws -> [MeshID: MeshBuffers] {
        var meshes: [MeshID: MeshBuffers] = [:]
        meshes[.primitive(.cube)] = try upload(device: device, mesh: makeCube())
        meshes[.primitive(.sphere)] = try upload(device: device, mesh: makeSphere(rings: 12, segments: 18))
        meshes[.primitive(.cylinder)] = try upload(device: device, mesh: makeCylinder(segments: 16))
        meshes[.primitive(.terrain)] = try upload(device: device, mesh: makeTerrain(world: world))
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
                vertices.append(MeshVertex(
                    position: SIMD3(x, y, z),
                    normal: normal,
                    color: SIMD4(repeating: 1),
                    texCoord: SIMD2(x, z)
                ))
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

}
