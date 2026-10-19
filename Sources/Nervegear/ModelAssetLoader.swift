import Foundation
import Metal
import MetalKit
import ModelIO
import simd

struct ImportedAssetModel {
    let meshes: [MeshID]
    let minimumY: Float
}

struct AssetLibrary {
    let meshes: [MeshID: MeshBuffers]
    let models: [String: ImportedAssetModel]

    static func load(device: MTLDevice, directory: URL, names: Set<String>) throws -> AssetLibrary {
        try validateAssetDirectory(directory)
        let textureLoader = MTKTextureLoader(device: device)
        let allocator = MTKMeshBufferAllocator(device: device)
        var meshBuffers: [MeshID: MeshBuffers] = [:]
        var models: [String: ImportedAssetModel] = [:]
        var textures: [String: MTLTexture] = [:]

        for name in names.sorted() {
            guard name.range(of: #"^[A-Za-z0-9_]+$"#, options: .regularExpression) != nil else {
                throw AssetImportError.invalid("asset name is not a catalog identifier: \(name)")
            }
            let url = directory.appendingPathComponent("\(name).obj", isDirectory: false)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw AssetImportError.invalid("asset file is missing: \(url.lastPathComponent)")
            }

            let asset = MDLAsset(url: url, vertexDescriptor: vertexDescriptor(), bufferAllocator: allocator)
            let (sourceMeshes, metalMeshes) = try MTKMesh.newMeshes(asset: asset, device: device)
            guard !metalMeshes.isEmpty, metalMeshes.count == sourceMeshes.count else {
                throw AssetImportError.invalid("Model I/O did not produce meshes for \(name)")
            }

            var partIDs: [MeshID] = []
            var minimumY = Float.greatestFiniteMagnitude
            for (meshIndex, sourceMesh) in sourceMeshes.enumerated() {
                minimumY = min(minimumY, sourceMesh.boundingBox.minBounds.y)
                let vertices = try readVertices(from: sourceMesh)
                guard let vertexBuffer = GeometryFactory.uploadVertices(device: device, vertices: vertices) else {
                    throw RendererError.gpu("Metal could not allocate vertices for \(name)")
                }

                let metalMesh = metalMeshes[meshIndex]
                guard let sourceSubmeshes = sourceMesh.submeshes as? [MDLSubmesh],
                      metalMesh.submeshes.count == sourceSubmeshes.count else {
                    throw AssetImportError.invalid("Model I/O returned mismatched submeshes for \(name)")
                }

                for (submeshIndex, submesh) in metalMesh.submeshes.enumerated() {
                    let id = MeshID.asset(name: name, part: partIDs.count)
                    let texture = try loadTexture(
                        from: sourceSubmeshes[submeshIndex].material,
                        using: textureLoader,
                        cache: &textures
                    )
                    meshBuffers[id] = MeshBuffers(
                        vertices: vertexBuffer,
                        indices: submesh.indexBuffer.buffer,
                        indexCount: submesh.indexCount,
                        indexType: submesh.indexType,
                        vertexOffset: 0,
                        indexOffset: submesh.indexBuffer.offset,
                        texture: texture
                    )
                    partIDs.append(id)
                }
            }
            guard minimumY.isFinite, !partIDs.isEmpty else {
                throw AssetImportError.invalid("asset has no drawable geometry: \(name)")
            }
            models[name] = ImportedAssetModel(meshes: partIDs, minimumY: minimumY)
        }
        return AssetLibrary(meshes: meshBuffers, models: models)
    }

    private static func validateAssetDirectory(_ directory: URL) throws {
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw AssetImportError.invalid("asset catalog must be a real directory: \(directory.path)")
        }
        guard let entries = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw AssetImportError.invalid("could not enumerate asset catalog: \(directory.path)")
        }
        for case let url as URL in entries {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw AssetImportError.invalid("asset catalog cannot contain symbolic links: \(url.lastPathComponent)")
            }
        }
    }

    private static func vertexDescriptor() -> MDLVertexDescriptor {
        let descriptor = MDLVertexDescriptor()
        descriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: MemoryLayout<MeshVertex>.offset(of: \.position) ?? 0,
            bufferIndex: 0
        )
        descriptor.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal,
            format: .float3,
            offset: MemoryLayout<MeshVertex>.offset(of: \.normal) ?? 16,
            bufferIndex: 0
        )
        descriptor.attributes[2] = MDLVertexAttribute(
            name: MDLVertexAttributeColor,
            format: .float4,
            offset: MemoryLayout<MeshVertex>.offset(of: \.color) ?? 32,
            bufferIndex: 0
        )
        descriptor.attributes[3] = MDLVertexAttribute(
            name: MDLVertexAttributeTextureCoordinate,
            format: .float2,
            offset: MemoryLayout<MeshVertex>.offset(of: \.texCoord) ?? 48,
            bufferIndex: 0
        )
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<MeshVertex>.stride)
        return descriptor
    }

    private static func readVertices(from mesh: MDLMesh) throws -> [MeshVertex] {
        guard let positions = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3),
              let normals = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal, as: .float3),
              let texCoords = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeTextureCoordinate, as: .float2) else {
            throw AssetImportError.invalid("asset mesh is missing positions, normals, or texture coordinates: \(mesh.name)")
        }

        return (0..<mesh.vertexCount).map { index in
            let position = positions.dataStart.advanced(by: index * positions.stride).loadUnaligned(as: SIMD3<Float>.self)
            let normal = normals.dataStart.advanced(by: index * normals.stride).loadUnaligned(as: SIMD3<Float>.self)
            let texCoord = texCoords.dataStart.advanced(by: index * texCoords.stride).loadUnaligned(as: SIMD2<Float>.self)
            return MeshVertex(position: position, normal: normal, color: SIMD4(repeating: 1), texCoord: texCoord)
        }
    }

    private static func loadTexture(
        from material: MDLMaterial?,
        using loader: MTKTextureLoader,
        cache: inout [String: MTLTexture]
    ) throws -> MTLTexture? {
        guard let modelTexture = material?.property(with: .baseColor)?.textureSamplerValue?.texture else { return nil }
        let cacheKey = (modelTexture as? MDLURLTexture)?.url.standardizedFileURL.absoluteString ?? modelTexture.name
        if let cached = cache[cacheKey] { return cached }
        let texture = try loader.newTexture(texture: modelTexture, options: nil)
        cache[cacheKey] = texture
        return texture
    }
}

enum AssetImportError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let detail): detail
        }
    }
}
