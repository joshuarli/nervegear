import AppKit
import GameController
import MetalKit
import simd

final class WorldView: MTKView {
    var orbitCamera: ((Float, Float) -> Void)?
    var zoomCamera: ((Float) -> Void)?
    private var lastPointer = CGPoint.zero
    private var pressedKeys = Set<String>()
    private var didStartControllerDiscovery = false

    override var acceptsFirstResponder: Bool { true }

    var movementInput: SIMD2<Float> {
        var input = SIMD2<Float>(
            (pressedKeys.contains("d") ? 1 : 0) - (pressedKeys.contains("a") ? 1 : 0),
            (pressedKeys.contains("w") ? 1 : 0) - (pressedKeys.contains("s") ? 1 : 0)
        )
        if let pad = GCController.controllers().compactMap(\.extendedGamepad).first {
            input += SIMD2(pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value)
        } else if let pad = GCController.controllers().compactMap(\.microGamepad).first {
            input += SIMD2(pad.dpad.xAxis.value, pad.dpad.yAxis.value)
        }
        return simd_length(input) > 1 ? simd_normalize(input) : input
    }

    var cameraInput: SIMD2<Float> {
        guard let pad = GCController.controllers().compactMap(\.extendedGamepad).first else { return .zero }
        return SIMD2(pad.rightThumbstick.xAxis.value, pad.rightThumbstick.yAxis.value)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !didStartControllerDiscovery else { return }
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        didStartControllerDiscovery = true
    }

    func stopControllerDiscovery() {
        if didStartControllerDiscovery {
            GCController.stopWirelessControllerDiscovery()
            didStartControllerDiscovery = false
        }
    }

    func resetKeyboardInput() {
        pressedKeys.removeAll()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastPointer = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        orbitCamera(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastPointer = convert(event.locationInWindow, from: nil)
    }

    override func rightMouseDragged(with event: NSEvent) {
        orbitCamera(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        zoomCamera?(Float(event.scrollingDeltaY))
    }

    override func keyDown(with event: NSEvent) {
        guard let key = movementKey(from: event) else {
            super.keyDown(with: event)
            return
        }
        pressedKeys.insert(key)
    }

    override func keyUp(with event: NSEvent) {
        guard let key = movementKey(from: event) else {
            super.keyUp(with: event)
            return
        }
        pressedKeys.remove(key)
    }

    private func orbitCamera(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let delta = CGPoint(x: point.x - lastPointer.x, y: point.y - lastPointer.y)
        lastPointer = point
        orbitCamera?(Float(delta.x) * 0.006, Float(delta.y) * 0.004)
    }

    private func movementKey(from event: NSEvent) -> String? {
        guard let key = event.charactersIgnoringModifiers?.lowercased(),
              key.count == 1,
              let character = key.first,
              "wasd".contains(character) else { return nil }
        return key
    }
}

enum CameraMath {
    static func viewProjection(target: SIMD3<Float>, yaw: Float, pitch: Float, distance: Float, aspect: Float) -> simd_float4x4 {
        let horizontal = distance * cos(pitch)
        let eye = target + SIMD3(-sin(yaw) * horizontal, sin(pitch) * distance, cos(yaw) * horizontal)
        let view = lookAt(eye: eye, target: target, up: SIMD3(0, 1, 0))
        let projection = perspective(fieldOfView: 58 * .pi / 180, aspect: aspect, near: 0.05, far: 180)
        return projection * view
    }

    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let forward = simd_normalize(target - eye)
        let right = simd_normalize(simd_cross(forward, up))
        let correctedUp = simd_cross(right, forward)
        return simd_float4x4(columns: (
            SIMD4(right.x, correctedUp.x, -forward.x, 0),
            SIMD4(right.y, correctedUp.y, -forward.y, 0),
            SIMD4(right.z, correctedUp.z, -forward.z, 0),
            SIMD4(-simd_dot(right, eye), -simd_dot(correctedUp, eye), simd_dot(forward, eye), 1)
        ))
    }

    static func perspective(fieldOfView: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let yScale = 1 / tan(fieldOfView * 0.5)
        let xScale = yScale / max(aspect, 0.1)
        let depthScale = far / (near - far)
        return simd_float4x4(columns: (
            SIMD4(xScale, 0, 0, 0),
            SIMD4(0, yScale, 0, 0),
            SIMD4(0, 0, depthScale, -1),
            SIMD4(0, 0, depthScale * near, 0)
        ))
    }

    static func orthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(2 / (right - left), 0, 0, 0),
            SIMD4(0, 2 / (top - bottom), 0, 0),
            SIMD4(0, 0, 1 / (near - far), 0),
            SIMD4(-(right + left) / (right - left), -(top + bottom) / (top - bottom), near / (near - far), 1)
        ))
    }

    static func lightViewProjection(extent: Float) -> simd_float4x4 {
        let target = SIMD3<Float>(0, 0, 0)
        let direction = simd_normalize(SIMD3<Float>(-0.48, 0.82, -0.31))
        let view = lookAt(eye: target + direction * 90, target: target, up: SIMD3(0, 1, 0))
        let projection = orthographic(
            left: -extent,
            right: extent,
            bottom: -extent,
            top: extent,
            near: 0.1,
            far: 220
        )
        return projection * view
    }
}
