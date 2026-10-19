import Foundation
import Metal
import MetalKit
import ModelIO
import simd

struct ImportedAssetPart {
    let mesh: MeshID
    let material: String
}

struct ImportedAssetModel {
    let parts: [ImportedAssetPart]
    let minimumY: Float
}

struct PlayerAssetFiles {
    let name: String
    let modelURL: URL
    let materialsURL: URL
}

struct AssetLibrary {
    let meshes: [MeshID: MeshBuffers]
    let models: [String: ImportedAssetModel]
    let surfaceMaterials: [String: SurfaceMaterial]
    let terrainLayers: [SurfaceMaterial]

    static func load(
        device: MTLDevice,
        directory: URL,
        names: Set<String>,
        player: PlayerAssetFiles? = nil
    ) throws -> AssetLibrary {
        try validateAssetDirectory(directory)
        let catalogURL = directory.appendingPathComponent("materials.json", isDirectory: false)
        let catalog = try JSONDecoder().decode(AssetMaterialCatalog.self, from: Data(contentsOf: catalogURL))
        try validate(catalog)
        let textureLoader = MTKTextureLoader(device: device)
        let allocator = MTKMeshBufferAllocator(device: device)
        var meshBuffers: [MeshID: MeshBuffers] = [:]
        var models: [String: ImportedAssetModel] = [:]
        var usedMaterials = Set(catalog.terrainLayers)
        var materialSources = catalog.materials.mapValues { ($0, directory) }

        for name in names.sorted() {
            guard isAssetIdentifier(name) else {
                throw AssetImportError.invalid("asset name is not a catalog identifier: \(name)")
            }
            let url = directory.appendingPathComponent("\(name).obj", isDirectory: false)
            models[name] = try loadModel(
                name: name,
                url: url,
                materialDefinitions: catalog.materials,
                usedMaterials: &usedMaterials,
                meshBuffers: &meshBuffers,
                device: device,
                allocator: allocator
            )
        }

        if let player {
            guard isAssetIdentifier(player.name), models[player.name] == nil else {
                throw AssetImportError.invalid("player asset name collides with a scene asset: \(player.name)")
            }
            let playerDirectory = player.modelURL.deletingLastPathComponent()
            try validateAssetDirectory(playerDirectory)
            guard isRegularFile(player.modelURL), isRegularFile(player.materialsURL) else {
                throw AssetImportError.invalid("player model or material catalog is missing or invalid")
            }
            let playerCatalog = try JSONDecoder().decode(
                AssetMaterialCatalog.self,
                from: Data(contentsOf: player.materialsURL)
            )
            try validate(playerCatalog, includingTerrainLayers: false)
            for (name, definition) in playerCatalog.materials {
                guard materialSources[name] == nil else {
                    throw AssetImportError.invalid("player material name collides with an environment material: \(name)")
                }
                materialSources[name] = (definition, playerDirectory)
            }
            models[player.name] = try loadModel(
                name: player.name,
                url: player.modelURL,
                materialDefinitions: playerCatalog.materials,
                usedMaterials: &usedMaterials,
                meshBuffers: &meshBuffers,
                device: device,
                allocator: allocator
            )
        }

        var surfaceMaterials: [String: SurfaceMaterial] = [:]
        var textureCache: [String: MTLTexture] = [:]
        for name in usedMaterials.sorted() {
            guard let (definition, materialDirectory) = materialSources[name] else {
                throw AssetImportError.invalid("material is missing from materials.json: \(name)")
            }
            surfaceMaterials[name] = try loadSurfaceMaterial(
                definition,
                using: textureLoader,
                directory: materialDirectory,
                cache: &textureCache
            )
        }
        let terrainLayers = catalog.terrainLayers.compactMap { surfaceMaterials[$0] }
        guard terrainLayers.count == 3 else {
            throw AssetImportError.invalid("materials.json must define three loadable terrain layers")
        }
        return AssetLibrary(
            meshes: meshBuffers,
            models: models,
            surfaceMaterials: surfaceMaterials,
            terrainLayers: terrainLayers
        )
    }

    private static func loadModel(
        name: String,
        url: URL,
        materialDefinitions: [String: SurfaceDefinition],
        usedMaterials: inout Set<String>,
        meshBuffers: inout [MeshID: MeshBuffers],
        device: MTLDevice,
        allocator: MTKMeshBufferAllocator
    ) throws -> ImportedAssetModel {
        guard isRegularFile(url) else {
            throw AssetImportError.invalid("asset file is missing or invalid: \(url.lastPathComponent)")
        }
        let asset = MDLAsset(url: url, vertexDescriptor: vertexDescriptor(), bufferAllocator: allocator)
        let (sourceMeshes, metalMeshes) = try MTKMesh.newMeshes(asset: asset, device: device)
        guard !metalMeshes.isEmpty, metalMeshes.count == sourceMeshes.count else {
            throw AssetImportError.invalid("Model I/O did not produce meshes for \(name)")
        }

        var parts: [ImportedAssetPart] = []
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
                guard let materialName = sourceSubmeshes[submeshIndex].material?.name,
                      materialDefinitions[materialName] != nil else {
                    throw AssetImportError.invalid("asset \(name) has a submesh without a material in its material catalog")
                }
                let id = MeshID.asset(name: name, part: parts.count)
                meshBuffers[id] = MeshBuffers(
                    vertices: vertexBuffer,
                    indices: submesh.indexBuffer.buffer,
                    indexCount: submesh.indexCount,
                    indexType: submesh.indexType,
                    vertexOffset: 0,
                    indexOffset: submesh.indexBuffer.offset
                )
                parts.append(ImportedAssetPart(mesh: id, material: materialName))
                usedMaterials.insert(materialName)
            }
        }
        guard minimumY.isFinite, !parts.isEmpty else {
            throw AssetImportError.invalid("asset has no drawable geometry: \(name)")
        }
        return ImportedAssetModel(parts: parts, minimumY: minimumY)
    }

    private static func validate(_ catalog: AssetMaterialCatalog, includingTerrainLayers: Bool = true) throws {
        guard catalog.version == 1 else {
            throw AssetImportError.invalid("asset material catalog version \(catalog.version) is unsupported")
        }
        if includingTerrainLayers {
            guard catalog.terrainLayers.count == 3,
                  Set(catalog.terrainLayers).count == catalog.terrainLayers.count,
                  catalog.terrainLayers.allSatisfy({ catalog.materials[$0] != nil }) else {
                throw AssetImportError.invalid("asset material catalog must define three unique terrain layers")
            }
        } else if !catalog.terrainLayers.isEmpty {
            throw AssetImportError.invalid("player materials must not define terrain layers")
        }
        for (name, material) in catalog.materials {
            guard isAssetIdentifier(name),
                  material.baseColorFactor.count == 4,
                  material.baseColorFactor.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                  material.roughnessFactor.isFinite && (0...1).contains(material.roughnessFactor),
                  material.metallicFactor.isFinite && (0...1).contains(material.metallicFactor),
                  material.alphaCutoff.isFinite && (0...1).contains(material.alphaCutoff),
                  material.uvScale.map({ $0.isFinite && (0.001...8).contains($0) }) ?? true else {
                throw AssetImportError.invalid("material definition is invalid: \(name)")
            }
        }
    }

    private static func loadSurfaceMaterial(
        _ definition: SurfaceDefinition,
        using loader: MTKTextureLoader,
        directory: URL,
        cache: inout [String: MTLTexture]
    ) throws -> SurfaceMaterial {
        func load(_ path: String?, srgb: Bool) throws -> MTLTexture? {
            guard let path else { return nil }
            let url = try textureURL(path, directory: directory)
            let cacheKey = "\(url.path)|\(srgb)"
            if let texture = cache[cacheKey] { return texture }
            let texture = try loader.newTexture(
                URL: url,
                options: [
                    .SRGB: NSNumber(value: srgb),
                    .generateMipmaps: NSNumber(value: true)
                ]
            )
            cache[cacheKey] = texture
            return texture
        }

        return SurfaceMaterial(
            baseColor: try load(definition.baseColor, srgb: true),
            normal: try load(definition.normal, srgb: false),
            roughness: try load(definition.roughness, srgb: false),
            metallic: try load(definition.metallic, srgb: false),
            ambientOcclusion: try load(definition.ambientOcclusion, srgb: false),
            opacity: try load(definition.opacity, srgb: false),
            baseColorFactor: SIMD4(
                definition.baseColorFactor[0],
                definition.baseColorFactor[1],
                definition.baseColorFactor[2],
                definition.baseColorFactor[3]
            ),
            roughnessFactor: definition.roughnessFactor,
            metallicFactor: definition.metallicFactor,
            alphaCutoff: definition.alphaCutoff,
            uvScale: definition.uvScale ?? 1,
            alphaMasked: definition.opacity != nil,
            doubleSided: definition.doubleSided
        )
    }

    private static func textureURL(_ path: String, directory: URL) throws -> URL {
        guard !path.hasPrefix("/"), !path.contains("\\"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw AssetImportError.invalid("texture path must be relative to the asset catalog: \(path)")
        }
        let url = path.split(separator: "/").reduce(directory) { result, component in
            result.appendingPathComponent(String(component), isDirectory: false)
        }
        guard isRegularFile(url) else {
            throw AssetImportError.invalid("texture file is missing or invalid: \(path)")
        }
        return url
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private static func isAssetIdentifier(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_]+$"#, options: .regularExpression) != nil
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
}

enum AssetImportError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let detail): detail
        }
    }
}
