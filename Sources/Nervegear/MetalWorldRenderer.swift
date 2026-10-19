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
    let surfaceMaterials: [String: SurfaceMaterial]
    let terrainLayers: [SurfaceMaterial]
    let playerModel: ImportedAssetModel?
    let playerAnimation: ImportedPlayerAnimation?
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

private struct ScreenshotReadback: @unchecked Sendable {
    let buffer: MTLBuffer
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let byteCount: Int
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
    private let flatNormalTexture: MTLTexture
    private let depthState: MTLDepthStencilState
    private let shadowSampler: MTLSamplerState
    private let assetSampler: MTLSamplerState
    private let configuration: AppConfiguration
    private let workerQueue = DispatchQueue(label: "nervegear.render-reload", qos: .utility)
    private let pendingLock = NSLock()
    private let screenshotLock = NSLock()
    private var pendingRender: PendingRender?
    private var screenshotRequested = false
    private var active: RuntimeSnapshot
    private var fileWatcher: FileWatcher?
    private var playerState: PlayerState
    private var cameraYaw: Float
    private var cameraPitch: Float = 0.25
    private var cameraDistance: Float = 8.8
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
        screenshotRequested = configuration.screenshotOnLaunch
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
            names: WorldData.assetNames(in: scene),
            player: Self.playerAssetFiles(for: configuration)
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

        let normalDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        normalDescriptor.usage = .shaderRead
        normalDescriptor.storageMode = .shared
        guard let flatNormalTexture = device.makeTexture(descriptor: normalDescriptor) else {
            throw RendererError.gpu("Metal could not allocate the default normal texture")
        }
        let normalPixel: [UInt8] = [128, 128, 255, 255]
        normalPixel.withUnsafeBytes { bytes in
            flatNormalTexture.replace(
                region: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: 4
            )
        }
        self.flatNormalTexture = flatNormalTexture

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
            assets: assets,
            primitivePlayer: configuration.primitivePlayer,
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
        var watchedURLs = [
            configuration.shaderURL,
            configuration.sceneURL,
            configuration.materialsURL,
            configuration.assetsURL.appendingPathComponent("materials.json", isDirectory: false)
        ]
        var optionalURLs: [URL] = []
        if !configuration.primitivePlayer {
            watchedURLs.append(contentsOf: [
                configuration.playerModelURL,
                configuration.playerMaterialsURL
            ] + configuration.playerTextureURLs)
            if let animation = assets.playerAnimation {
                watchedURLs.append(configuration.playerAnimationManifestURL)
                watchedURLs.append(contentsOf: animation.sourceURLs)
            } else {
                let animationDirectory = configuration.playerAnimationManifestURL.deletingLastPathComponent()
                optionalURLs.append(configuration.playerAnimationManifestURL)
                optionalURLs.append(contentsOf: (0..<24).map { index in
                    animationDirectory.appendingPathComponent(String(format: "walk_%03d.obj", index), isDirectory: false)
                })
            }
        }
        fileWatcher = try FileWatcher(
            urls: watchedURLs,
            optionalURLs: optionalURLs,
            onChange: { [weak self] in self?.reloadFiles() }
        )
        fileWatcher?.start()
    }

    func orbitCamera(horizontal: Float, vertical: Float) {
        cameraYaw -= horizontal
        cameraPitch = min(max(cameraPitch + vertical, 0.12), 0.68)
    }

    func zoomCamera(delta: Float) {
        cameraDistance = min(max(cameraDistance * exp(-delta * 0.0015), 6.4), 14)
    }

    @MainActor
    func requestScreenshot() {
        view.framebufferOnly = false
        screenshotLock.lock()
        screenshotRequested = true
        screenshotLock.unlock()
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
        let cameraPosition = CameraMath.eyePosition(
            target: followTarget,
            yaw: cameraYaw,
            pitch: cameraPitch,
            distance: cameraDistance
        )
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
            cameraPosition: SIMD4(cameraPosition.x, cameraPosition.y, cameraPosition.z, 1),
            shadowTexelSize: SIMD4(1 / Float(shadowTexture.width), 1 / Float(shadowTexture.height), 2.2, 0),
            trailCurve: TrailPath.curve
        )
        let playerAnimationFrame = isWalking ? active.playerAnimation?.frame(at: walkPhase) : nil
        let playerParts = PlayerAvatar.parts(
            player: playerState,
            gaitPhase: walkPhase,
            isWalking: isWalking,
            model: active.playerModel,
            animationFrame: playerAnimationFrame
        )

        let shadowPass = MTLRenderPassDescriptor()
        shadowPass.depthAttachment.texture = shadowTexture
        shadowPass.depthAttachment.loadAction = .clear
        shadowPass.depthAttachment.storeAction = .store
        shadowPass.depthAttachment.clearDepth = 1
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: shadowPass) {
            encoder.setRenderPipelineState(active.pipelines.shadow)
            encoder.setDepthStencilState(depthState)
            encoder.setCullMode(.none)
            for batch in active.batches {
                guard let mesh = active.meshes[batch.key.mesh] else { continue }
                let material = active.surfaceMaterials[batch.key.material] ?? .defaultMaterial
                var materialUniforms = material.uniforms
                encoder.setVertexBuffer(mesh.vertices, offset: mesh.vertexOffset, index: 0)
                encoder.setVertexBuffer(batch.instances, offset: 0, index: 1)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 2)
                encoder.setFragmentBytes(&materialUniforms, length: MemoryLayout<MaterialUniforms>.stride, index: 0)
                encoder.setFragmentTexture(material.baseColor ?? whiteTexture, index: 0)
                encoder.setFragmentTexture(material.opacity ?? whiteTexture, index: 1)
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
            drawPlayer(playerParts, with: encoder, uniforms: &uniforms, shadowPass: true)
            encoder.endEncoding()
        }

        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.58, green: 0.76, blue: 0.88, alpha: 1)
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
            encoder.setRenderPipelineState(active.pipelines.world)
            encoder.setDepthStencilState(depthState)
            encoder.setCullMode(.none)
            encoder.setFragmentTexture(shadowTexture, index: 0)
            encoder.setFragmentSamplerState(shadowSampler, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 0)
            var terrainUniforms = TerrainMaterialUniforms(layers: active.terrainLayers)
            encoder.setFragmentBytes(&terrainUniforms, length: MemoryLayout<TerrainMaterialUniforms>.stride, index: 2)
            for (layerIndex, material) in active.terrainLayers.enumerated() {
                let textureIndex = 7 + layerIndex * 3
                encoder.setFragmentTexture(material.baseColor ?? whiteTexture, index: textureIndex)
                encoder.setFragmentTexture(material.normal ?? flatNormalTexture, index: textureIndex + 1)
                encoder.setFragmentTexture(material.roughness ?? whiteTexture, index: textureIndex + 2)
            }
            for batch in active.batches {
                guard let mesh = active.meshes[batch.key.mesh] else { continue }
                let material = active.surfaceMaterials[batch.key.material] ?? .defaultMaterial
                let isTerrain = batch.key.mesh == .primitive(.terrain)
                var materialUniforms = material.uniforms(forTerrain: isTerrain)
                encoder.setVertexBuffer(mesh.vertices, offset: mesh.vertexOffset, index: 0)
                encoder.setVertexBuffer(batch.instances, offset: 0, index: 1)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 2)
                encoder.setFragmentBytes(&materialUniforms, length: MemoryLayout<MaterialUniforms>.stride, index: 1)
                encoder.setFragmentTexture(material.baseColor ?? whiteTexture, index: 1)
                encoder.setFragmentTexture(material.normal ?? flatNormalTexture, index: 2)
                encoder.setFragmentTexture(material.roughness ?? whiteTexture, index: 3)
                encoder.setFragmentTexture(material.metallic ?? whiteTexture, index: 4)
                encoder.setFragmentTexture(material.ambientOcclusion ?? whiteTexture, index: 5)
                encoder.setFragmentTexture(material.opacity ?? whiteTexture, index: 6)
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
            drawPlayer(playerParts, with: encoder, uniforms: &uniforms, shadowPass: false)
            encoder.endEncoding()
        }

        if consumeScreenshotRequest() {
            MainActor.assumeIsolated {
                captureScreenshot(from: drawable.texture, commandBuffer: commandBuffer)
            }
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

    private func consumeScreenshotRequest() -> Bool {
        screenshotLock.lock()
        defer { screenshotLock.unlock() }
        let requested = screenshotRequested
        screenshotRequested = false
        return requested
    }

    @MainActor
    private func captureScreenshot(from texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = (width * 4 + 255) & ~255
        let byteCount = bytesPerRow * height
        guard let buffer = device.makeBuffer(length: byteCount, options: .storageModeShared),
              let encoder = commandBuffer.makeBlitCommandEncoder() else {
            Self.report("Could not allocate a screenshot readback buffer")
            view.framebufferOnly = true
            return
        }
        encoder.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: buffer,
            destinationOffset: 0,
            destinationBytesPerRow: bytesPerRow,
            destinationBytesPerImage: byteCount
        )
        encoder.endEncoding()
        view.framebufferOnly = true
        let readback = ScreenshotReadback(
            buffer: buffer,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            byteCount: byteCount
        )
        commandBuffer.addCompletedHandler { [weak self, readback] completedBuffer in
            guard let self else { return }
            guard completedBuffer.status == .completed else {
                Self.report("Screenshot GPU copy failed: \(completedBuffer.error?.localizedDescription ?? "unknown error")")
                return
            }
            let pixels = Data(bytes: readback.buffer.contents(), count: readback.byteCount)
            let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
            )
            guard let provider = CGDataProvider(data: pixels as CFData),
                  let image = CGImage(
                    width: readback.width,
                    height: readback.height,
                    bitsPerComponent: 8,
                    bitsPerPixel: 32,
                    bytesPerRow: readback.bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: bitmapInfo,
                    provider: provider,
                    decode: nil,
                    shouldInterpolate: false,
                    intent: .defaultIntent
                  ),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                Self.report("Could not encode the screenshot as PNG")
                return
            }
            do {
                try FileManager.default.createDirectory(
                    at: configuration.screenshotURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try png.write(to: configuration.screenshotURL, options: .atomic)
                Self.report("Screenshot saved to \(configuration.screenshotURL.path)")
            } catch {
                Self.report("Could not save screenshot: \(error.localizedDescription)")
            }
        }
    }

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
        shadowPass: Bool
    ) {
        for part in parts {
            guard let mesh = active.meshes[part.mesh] else { continue }
            let material = part.material.flatMap { active.surfaceMaterials[$0] } ?? .defaultMaterial
            var instance = part.instance
            var materialUniforms = material.uniforms
            encoder.setVertexBuffer(mesh.vertices, offset: mesh.vertexOffset, index: 0)
            encoder.setVertexBytes(&instance, length: MemoryLayout<InstanceData>.stride, index: 1)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 2)
            if shadowPass {
                encoder.setFragmentBytes(&materialUniforms, length: MemoryLayout<MaterialUniforms>.stride, index: 0)
                encoder.setFragmentTexture(material.baseColor ?? whiteTexture, index: 0)
                encoder.setFragmentTexture(material.opacity ?? whiteTexture, index: 1)
                encoder.setFragmentSamplerState(assetSampler, index: 0)
            } else {
                encoder.setFragmentBytes(&materialUniforms, length: MemoryLayout<MaterialUniforms>.stride, index: 1)
                encoder.setFragmentTexture(material.baseColor ?? whiteTexture, index: 1)
                encoder.setFragmentTexture(material.normal ?? flatNormalTexture, index: 2)
                encoder.setFragmentTexture(material.roughness ?? whiteTexture, index: 3)
                encoder.setFragmentTexture(material.metallic ?? whiteTexture, index: 4)
                encoder.setFragmentTexture(material.ambientOcclusion ?? whiteTexture, index: 5)
                encoder.setFragmentTexture(material.opacity ?? whiteTexture, index: 6)
                encoder.setFragmentSamplerState(assetSampler, index: 1)
            }
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
                    assets: prepared.assets,
                    primitivePlayer: self.configuration.primitivePlayer,
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
            names: WorldData.assetNames(in: scene),
            player: Self.playerAssetFiles(for: configuration)
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
        assets: AssetLibrary,
        primitivePlayer: Bool,
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

        for batch in batches where batch.key.mesh != .primitive(.terrain) {
            guard assets.surfaceMaterials[batch.key.material] != nil else {
                throw AssetImportError.invalid("draw batch references missing surface material \(batch.key.material)")
            }
        }

        let playerModel: ImportedAssetModel?
        if primitivePlayer {
            playerModel = nil
        } else {
            guard let model = assets.models["Asuna"] else {
                throw AssetImportError.invalid("player asset Asuna was not loaded")
            }
            for part in model.parts {
                guard meshes[part.mesh] != nil, assets.surfaceMaterials[part.material] != nil else {
                    throw AssetImportError.invalid("player asset Asuna has an invalid mesh or material reference")
                }
            }
            playerModel = model
        }

        return RuntimeSnapshot(
            scene: scene,
            pipelines: pipelines,
            meshes: meshes,
            batches: batches,
            surfaceMaterials: assets.surfaceMaterials,
            terrainLayers: assets.terrainLayers,
            playerModel: playerModel,
            playerAnimation: primitivePlayer ? nil : assets.playerAnimation
        )
    }

    private static func playerAssetFiles(for configuration: AppConfiguration) -> PlayerAssetFiles? {
        guard !configuration.primitivePlayer else { return nil }
        return PlayerAssetFiles(
            name: "Asuna",
            modelURL: configuration.playerModelURL,
            materialsURL: configuration.playerMaterialsURL,
            animationManifestURL: configuration.playerAnimationManifestURL
        )
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
