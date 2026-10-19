import AppKit
import Darwin
import Metal
import MetalKit
import QuartzCore
import simd

struct PipelineSet: @unchecked Sendable {
    let world: MTLRenderPipelineState
    let shadow: MTLRenderPipelineState
}

struct DrawKey: Hashable {
    let mesh: MeshID
    let material: String
}

struct DrawBatch {
    let key: DrawKey
    let instances: MTLBuffer
    let count: Int
}

struct RuntimeSnapshot: @unchecked Sendable {
    let scene: SceneDocument
    let pipelines: PipelineSet
    let meshes: [MeshID: MeshBuffers]
    let batches: [DrawBatch]
}

struct PreparedReload: @unchecked Sendable {
    let scene: SceneDocument
    let materials: MaterialsDocument
    let pipelines: PipelineSet
    let meshes: [MeshID: MeshBuffers]
    let assets: AssetLibrary
}

struct PendingRender: @unchecked Sendable {
    let snapshot: RuntimeSnapshot
}

enum RendererError: LocalizedError {
    case gpu(String)

    var errorDescription: String? {
        switch self {
        case .gpu(let detail): return detail
        }
    }
}

final class WorldRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    private let view: MTKView
    private let colorPixelFormat: MTLPixelFormat
    private let depthPixelFormat: MTLPixelFormat
    private let sampleCount: Int
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let shadowTexture: MTLTexture
    private let whiteTexture: MTLTexture
    private let depthState: MTLDepthStencilState
    private let shadowSampler: MTLSamplerState
    private let assetSampler: MTLSamplerState
    private let configuration: AppConfiguration
    private let workerQueue = DispatchQueue(label: "nervegear.render-reload", qos: .utility)
    private let pendingLock = NSLock()
    private var pendingRender: PendingRender?
    private var active: RuntimeSnapshot
    private var fileWatcher: FileWatcher?
    private var playerState: PlayerState
    private var cameraYaw: Float
    private var cameraPitch: Float = 0.25
    private var cameraDistance: Float = 4.4
    private var followTarget: SIMD3<Float>
    private var walkPhase: Float = 0
    private var isWalking = false
    private var lastFrameTime = CACurrentMediaTime()
    private var didPublishReady = false

    @MainActor
    init(view: MTKView, device: MTLDevice, configuration: AppConfiguration) throws {
        self.view = view
        colorPixelFormat = view.colorPixelFormat
        depthPixelFormat = view.depthStencilPixelFormat
        sampleCount = view.sampleCount
        self.device = device
        self.configuration = configuration
        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.gpu("Metal could not create a command queue")
        }
        self.commandQueue = commandQueue

        let scene = try WorldData.decodeScene(at: configuration.sceneURL)
        let materials = try WorldData.decodeMaterials(at: configuration.materialsURL)
        let session = try WorldData.decodeSession(at: configuration.sessionURL)
        let pipelines = try Self.makePipelines(
            source: String(contentsOf: configuration.shaderURL, encoding: .utf8),
            device: device,
            colorPixelFormat: view.colorPixelFormat,
            depthPixelFormat: view.depthStencilPixelFormat,
            sampleCount: view.sampleCount
        )
        let primitiveMeshes = try GeometryFactory.makeMeshes(device: device, world: scene.world)
        let assets = try AssetLibrary.load(
            device: device,
            directory: configuration.assetsURL,
            names: Set(scene.objects.map(\.asset))
        )
        var meshes = primitiveMeshes
        for (id, mesh) in assets.meshes {
            guard meshes.updateValue(mesh, forKey: id) == nil else {
                throw AssetImportError.invalid("asset mesh identifier collides with a built-in mesh")
            }
        }

        let shadowDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: 2048,
            height: 2048,
            mipmapped: false
        )
        shadowDescriptor.usage = [.renderTarget, .shaderRead]
        shadowDescriptor.storageMode = .private
        guard let shadowTexture = device.makeTexture(descriptor: shadowDescriptor) else {
            throw RendererError.gpu("Metal could not allocate the directional shadow map")
        }
        self.shadowTexture = shadowTexture

        let whiteDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        whiteDescriptor.usage = .shaderRead
        whiteDescriptor.storageMode = .shared
        guard let whiteTexture = device.makeTexture(descriptor: whiteDescriptor) else {
            throw RendererError.gpu("Metal could not allocate the default material texture")
        }
        let whitePixel: [UInt8] = [255, 255, 255, 255]
        whitePixel.withUnsafeBytes { bytes in
            whiteTexture.replace(
                region: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: 4
            )
        }
        self.whiteTexture = whiteTexture

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw RendererError.gpu("Metal could not create a depth state")
        }
        self.depthState = depthState

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .nearest
        samplerDescriptor.magFilter = .nearest
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let shadowSampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw RendererError.gpu("Metal could not create the shadow sampler")
        }
        self.shadowSampler = shadowSampler
        let assetSamplerDescriptor = MTLSamplerDescriptor()
        assetSamplerDescriptor.minFilter = .linear
        assetSamplerDescriptor.magFilter = .linear
        assetSamplerDescriptor.mipFilter = .linear
        assetSamplerDescriptor.sAddressMode = .repeat
        assetSamplerDescriptor.tAddressMode = .repeat
        guard let assetSampler = device.makeSamplerState(descriptor: assetSamplerDescriptor) else {
            throw RendererError.gpu("Metal could not create the asset sampler")
        }
        self.assetSampler = assetSampler

        let objects = try WorldData.makeObjects(scene: scene, materials: materials, assets: assets)
        active = try Self.makeSnapshot(
            scene: scene,
            materials: materials,
            pipelines: pipelines,
            objects: objects,
            meshes: meshes,
            device: device
        )
        playerState = session?.player ?? PlayerState(position: scene.playerStart, yaw: 0)
        playerState.position.x = min(max(playerState.position.x, -scene.world.extent * 0.5 + 1), scene.world.extent * 0.5 - 1)
        playerState.position.z = min(max(playerState.position.z, -scene.world.extent * 0.5 + 1), scene.world.extent * 0.5 - 1)
        playerState.position.y = WorldData.terrainHeight(x: playerState.position.x, z: playerState.position.z, world: scene.world)
        cameraYaw = playerState.yaw
        followTarget = playerState.position.simd + SIMD3(0, 1.1, 0)

        super.init()
        view.delegate = self
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        fileWatcher = try FileWatcher(
            urls: [configuration.shaderURL, configuration.sceneURL, configuration.materialsURL],
            onChange: { [weak self] in self?.reloadFiles() }
        )
        fileWatcher?.start()
    }

    func orbitCamera(horizontal: Float, vertical: Float) {
        cameraYaw -= horizontal
        cameraPitch = min(max(cameraPitch + vertical, 0.12), 0.68)
    }

    func zoomCamera(delta: Float) {
        cameraDistance = min(max(cameraDistance * exp(-delta * 0.0015), 3.2), 7)
    }

    func saveSession() throws {
        let session = SessionDocument(
            version: 2,
            player: playerState
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        try FileManager.default.createDirectory(
            at: configuration.sessionURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: configuration.sessionURL, options: .atomic)
    }

    func draw(in view: MTKView) {
        commitPendingAtFrameBoundary()
        let now = CACurrentMediaTime()
        let frameDelta = min(max(now - lastFrameTime, 0), 0.25)
        lastFrameTime = now
        let inputs: (movement: SIMD2<Float>, camera: SIMD2<Float>) = MainActor.assumeIsolated {
            guard let worldView = view as? WorldView else {
                return (SIMD2<Float>.zero, SIMD2<Float>.zero)
            }
            return (worldView.movementInput, worldView.cameraInput)
        }
        let movementInput = inputs.movement
        let cameraInput = inputs.camera
        updatePlayer(deltaTime: Float(frameDelta), movementInput: movementInput, cameraInput: cameraInput)

        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let aspect = Float(max(view.drawableSize.width, 1) / max(view.drawableSize.height, 1))
        let lightDirection = simd_normalize(SIMD3<Float>(-0.48, 0.82, -0.31))
        var uniforms = FrameUniforms(
            viewProjection: CameraMath.viewProjection(
                target: followTarget,
                yaw: cameraYaw,
                pitch: cameraPitch,
                distance: cameraDistance,
                aspect: aspect
            ),
            lightViewProjection: CameraMath.lightViewProjection(extent: active.scene.world.extent * 0.8),
            lightDirection: SIMD4(lightDirection.x, lightDirection.y, lightDirection.z, 0),
            shadowTexelSize: SIMD4(1 / Float(shadowTexture.width), 1 / Float(shadowTexture.height), 0, 0)
        )
        let playerParts = PlayerAvatar.parts(player: playerState, gaitPhase: walkPhase, isWalking: isWalking)

        let shadowPass = MTLRenderPassDescriptor()
        shadowPass.depthAttachment.texture = shadowTexture
        shadowPass.depthAttachment.loadAction = .clear
        shadowPass.depthAttachment.storeAction = .store
        shadowPass.depthAttachment.clearDepth = 1
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: shadowPass) {
            encoder.setRenderPipelineState(active.pipelines.shadow)
            encoder.setDepthStencilState(depthState)
            for batch in active.batches where batch.key.mesh.castsShadow {
                guard let mesh = active.meshes[batch.key.mesh] else { continue }
                encoder.setVertexBuffer(mesh.vertices, offset: mesh.vertexOffset, index: 0)
                encoder.setVertexBuffer(batch.instances, offset: 0, index: 1)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 2)
                encoder.setFragmentTexture(mesh.texture ?? whiteTexture, index: 0)
                encoder.setFragmentSamplerState(assetSampler, index: 0)
                encoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: mesh.indexCount,
                    indexType: mesh.indexType,
                    indexBuffer: mesh.indices,
                    indexBufferOffset: mesh.indexOffset,
                    instanceCount: batch.count
                )
            }
            drawPlayer(playerParts, with: encoder, uniforms: &uniforms, textureIndex: 0)
            encoder.endEncoding()
        }

        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.58, green: 0.76, blue: 0.88, alpha: 1)
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
            encoder.setRenderPipelineState(active.pipelines.world)
            encoder.setDepthStencilState(depthState)
            encoder.setFragmentTexture(shadowTexture, index: 0)
            encoder.setFragmentSamplerState(shadowSampler, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 0)
            for batch in active.batches {
                guard let mesh = active.meshes[batch.key.mesh] else { continue }
                encoder.setVertexBuffer(mesh.vertices, offset: mesh.vertexOffset, index: 0)
                encoder.setVertexBuffer(batch.instances, offset: 0, index: 1)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 2)
                encoder.setFragmentTexture(mesh.texture ?? whiteTexture, index: 1)
                encoder.setFragmentSamplerState(assetSampler, index: 1)
                encoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: mesh.indexCount,
                    indexType: mesh.indexType,
                    indexBuffer: mesh.indices,
                    indexBufferOffset: mesh.indexOffset,
                    instanceCount: batch.count
                )
            }
            drawPlayer(playerParts, with: encoder, uniforms: &uniforms, textureIndex: 1)
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()

        if !didPublishReady {
            didPublishReady = true
            if let readyURL = configuration.readyURL {
                do {
                    try FileManager.default.createDirectory(
                        at: readyURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try Data("ready\n".utf8).write(to: readyURL, options: .atomic)
                } catch {
                    Self.report("Could not publish ready file at \(readyURL.path): \(error.localizedDescription)")
                }
            }
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private func updatePlayer(deltaTime: Float, movementInput input: SIMD2<Float>, cameraInput: SIMD2<Float>) {
        orbitCamera(horizontal: cameraInput.x * deltaTime * 2.2, vertical: cameraInput.y * deltaTime * 1.5)

        let forward = SIMD3(sin(cameraYaw), 0, -cos(cameraYaw))
        let right = SIMD3(cos(cameraYaw), 0, sin(cameraYaw))
        let movement = right * input.x + forward * input.y
        let movementLength = simd_length(movement)
        isWalking = movementLength > 0.01
        if isWalking {
            let direction = movement / movementLength
            let bounds = active.scene.world.extent * 0.5 - 1
            playerState.position.x = min(max(playerState.position.x + direction.x * 4.2 * deltaTime, -bounds), bounds)
            playerState.position.z = min(max(playerState.position.z + direction.z * 4.2 * deltaTime, -bounds), bounds)
            let desiredYaw = atan2(direction.x, -direction.z)
            let yawDelta = atan2(sin(desiredYaw - playerState.yaw), cos(desiredYaw - playerState.yaw))
            playerState.yaw += yawDelta * min(deltaTime * 12, 1)
            walkPhase += deltaTime * 10
        }

        playerState.position.y = WorldData.terrainHeight(
            x: playerState.position.x,
            z: playerState.position.z,
            world: active.scene.world
        )
        let target = playerState.position.simd + SIMD3(0, 1.12, 0)
        followTarget += (target - followTarget) * min(deltaTime * 9, 1)
    }

    private func drawPlayer(
        _ parts: [PlayerDrawPart],
        with encoder: MTLRenderCommandEncoder,
        uniforms: inout FrameUniforms,
        textureIndex: Int
    ) {
        for part in parts {
            guard let mesh = active.meshes[.primitive(part.primitive)] else { continue }
            var instance = part.instance
            encoder.setVertexBuffer(mesh.vertices, offset: mesh.vertexOffset, index: 0)
            encoder.setVertexBytes(&instance, length: MemoryLayout<InstanceData>.stride, index: 1)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 2)
            encoder.setFragmentTexture(whiteTexture, index: textureIndex)
            encoder.setFragmentSamplerState(assetSampler, index: textureIndex)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: mesh.indexCount,
                indexType: mesh.indexType,
                indexBuffer: mesh.indices,
                indexBufferOffset: mesh.indexOffset,
                instanceCount: 1
            )
        }
    }

    private static func report(_ message: String) {
        fputs("Nervegear: \(message)\n", stderr)
    }

    private func reloadFiles() {
        workerQueue.async { [weak self] in
            guard let self else { return }
            do {
                let prepared = try self.prepareFiles()
                let objects = try WorldData.makeObjects(
                    scene: prepared.scene,
                    materials: prepared.materials,
                    assets: prepared.assets
                )
                let snapshot = try Self.makeSnapshot(
                    scene: prepared.scene,
                    materials: prepared.materials,
                    pipelines: prepared.pipelines,
                    objects: objects,
                    meshes: prepared.meshes,
                    device: self.device
                )
                self.pendingLock.lock()
                self.pendingRender = PendingRender(snapshot: snapshot)
                self.pendingLock.unlock()
            } catch {
                Self.report("Reload failed; the active renderer is unchanged: \(error.localizedDescription)")
            }
        }
    }

    private func prepareFiles() throws -> PreparedReload {
        let scene = try WorldData.decodeScene(at: configuration.sceneURL)
        let materials = try WorldData.decodeMaterials(at: configuration.materialsURL)
        let source = try String(contentsOf: configuration.shaderURL, encoding: .utf8)
        let pipelines = try Self.makePipelines(
            source: source,
            device: device,
            colorPixelFormat: colorPixelFormat,
            depthPixelFormat: depthPixelFormat,
            sampleCount: sampleCount
        )
        let primitiveMeshes = try GeometryFactory.makeMeshes(device: device, world: scene.world)
        let assets = try AssetLibrary.load(
            device: device,
            directory: configuration.assetsURL,
            names: Set(scene.objects.map(\.asset))
        )
        var meshes = primitiveMeshes
        for (id, mesh) in assets.meshes {
            guard meshes.updateValue(mesh, forKey: id) == nil else {
                throw AssetImportError.invalid("asset mesh identifier collides with a built-in mesh")
            }
        }
        return PreparedReload(scene: scene, materials: materials, pipelines: pipelines, meshes: meshes, assets: assets)
    }

    private func commitPendingAtFrameBoundary() {
        pendingLock.lock()
        let pending = pendingRender
        pendingRender = nil
        pendingLock.unlock()
        guard let pending else { return }
        active = pending.snapshot
        let bounds = active.scene.world.extent * 0.5 - 1
        playerState.position.x = min(max(playerState.position.x, -bounds), bounds)
        playerState.position.z = min(max(playerState.position.z, -bounds), bounds)
        playerState.position.y = WorldData.terrainHeight(x: playerState.position.x, z: playerState.position.z, world: active.scene.world)
        followTarget = playerState.position.simd + SIMD3(0, 1.12, 0)
    }

    private static func makeSnapshot(
        scene: SceneDocument,
        materials: MaterialsDocument,
        pipelines: PipelineSet,
        objects: [RuntimeObject],
        meshes: [MeshID: MeshBuffers],
        device: MTLDevice
    ) throws -> RuntimeSnapshot {
        var grouped: [DrawKey: [InstanceData]] = [:]
        let materialColors = Dictionary(uniqueKeysWithValues: materials.materials.map { material in
            (material.id, SIMD4(material.color[0], material.color[1], material.color[2], material.color[3]))
        })

        for object in objects {
            let color: SIMD4<Float>
            switch object.mesh {
            case .asset:
                color = SIMD4(repeating: 1)
            case .primitive(let primitive):
                guard let materialColor = materialColors[object.material] else {
                    throw WorldDataError.invalid("\(primitive.rawValue) references missing material \(object.material)")
                }
                color = materialColor
            }
            let key = DrawKey(mesh: object.mesh, material: object.material)
            grouped[key, default: []].append(InstanceData(modelMatrix: object.transform.matrix, color: color))
        }

        var batches: [DrawBatch] = []
        for (key, instances) in grouped {
            guard meshes[key.mesh] != nil else {
                throw RendererError.gpu("No geometry was built for \(key.mesh)")
            }
            guard let buffer = instances.withUnsafeBufferPointer({ pointer -> MTLBuffer? in
                guard let baseAddress = pointer.baseAddress else { return nil }
                return device.makeBuffer(
                    bytes: baseAddress,
                    length: pointer.count * MemoryLayout<InstanceData>.stride,
                    options: .storageModeShared
                )
            }) else {
                throw RendererError.gpu("Metal could not allocate instances for \(key.material)")
            }
            batches.append(DrawBatch(key: key, instances: buffer, count: instances.count))
        }

        return RuntimeSnapshot(scene: scene, pipelines: pipelines, meshes: meshes, batches: batches)
    }

    private static func makePipelines(
        source: String,
        device: MTLDevice,
        colorPixelFormat: MTLPixelFormat,
        depthPixelFormat: MTLPixelFormat,
        sampleCount: Int
    ) throws -> PipelineSet {
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: source, options: nil)
        } catch {
            throw RendererError.gpu("Metal shader compilation failed: \(error.localizedDescription)")
        }
        guard let worldVertex = library.makeFunction(name: "world_vertex"),
              let worldFragment = library.makeFunction(name: "world_fragment"),
              let shadowVertex = library.makeFunction(name: "shadow_vertex"),
              let shadowFragment = library.makeFunction(name: "shadow_fragment") else {
            throw RendererError.gpu("Shader must define world_vertex, world_fragment, shadow_vertex, and shadow_fragment")
        }

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = MemoryLayout<MeshVertex>.offset(of: \.position) ?? 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = MemoryLayout<MeshVertex>.offset(of: \.normal) ?? 16
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[2].format = .float4
        vertexDescriptor.attributes[2].offset = MemoryLayout<MeshVertex>.offset(of: \.color) ?? 32
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.attributes[3].format = .float2
        vertexDescriptor.attributes[3].offset = MemoryLayout<MeshVertex>.offset(of: \.texCoord) ?? 48
        vertexDescriptor.attributes[3].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<MeshVertex>.stride
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        let worldDescriptor = MTLRenderPipelineDescriptor()
        worldDescriptor.label = "Nervegear world"
        worldDescriptor.vertexFunction = worldVertex
        worldDescriptor.fragmentFunction = worldFragment
        worldDescriptor.vertexDescriptor = vertexDescriptor
        worldDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        worldDescriptor.depthAttachmentPixelFormat = depthPixelFormat
        worldDescriptor.rasterSampleCount = sampleCount

        let shadowDescriptor = MTLRenderPipelineDescriptor()
        shadowDescriptor.label = "Nervegear directional shadows"
        shadowDescriptor.vertexFunction = shadowVertex
        shadowDescriptor.fragmentFunction = shadowFragment
        shadowDescriptor.vertexDescriptor = vertexDescriptor
        shadowDescriptor.depthAttachmentPixelFormat = .depth32Float
        shadowDescriptor.rasterSampleCount = 1

        do {
            return PipelineSet(
                world: try device.makeRenderPipelineState(descriptor: worldDescriptor),
                shadow: try device.makeRenderPipelineState(descriptor: shadowDescriptor)
            )
        } catch {
            throw RendererError.gpu("Metal pipeline validation failed: \(error.localizedDescription)")
        }
    }
}
