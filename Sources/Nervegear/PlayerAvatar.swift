import simd

struct PlayerDrawPart {
    var primitive: Primitive
    var instance: InstanceData
}

enum PlayerAvatar {
    static func parts(player: PlayerState, gaitPhase: Float, isWalking: Bool) -> [PlayerDrawPart] {
        let stride = isWalking ? sin(gaitPhase) * 0.52 : 0
        let bob = isWalking ? abs(sin(gaitPhase * 2)) * 0.035 : 0
        return [
            part(.sphere, position: SIMD3(0, 1.02 + bob, 0), scale: SIMD3(0.44, 0.63, 0.30), color: SIMD4(0.22, 0.43, 0.48, 1), player: player),
            part(.sphere, position: SIMD3(0, 1.70 + bob, 0), scale: SIMD3(0.28, 0.30, 0.28), color: SIMD4(0.78, 0.58, 0.42, 1), player: player),
            part(.sphere, position: SIMD3(0, 1.84 + bob, 0.07), scale: SIMD3(0.29, 0.16, 0.30), color: SIMD4(0.24, 0.16, 0.12, 1), player: player),
            part(.cylinder, position: SIMD3(-0.32, 1.02 + bob, 0), scale: SIMD3(0.13, 0.66, 0.13), color: SIMD4(0.78, 0.58, 0.42, 1), rotationX: -stride, player: player),
            part(.cylinder, position: SIMD3(0.32, 1.02 + bob, 0), scale: SIMD3(0.13, 0.66, 0.13), color: SIMD4(0.78, 0.58, 0.42, 1), rotationX: stride, player: player),
            part(.cylinder, position: SIMD3(-0.14, 0.43, 0), scale: SIMD3(0.16, 0.76, 0.16), color: SIMD4(0.22, 0.25, 0.30, 1), rotationX: stride, player: player),
            part(.cylinder, position: SIMD3(0.14, 0.43, 0), scale: SIMD3(0.16, 0.76, 0.16), color: SIMD4(0.22, 0.25, 0.30, 1), rotationX: -stride, player: player),
            part(.cube, position: SIMD3(-0.14, 0.10, -0.04), scale: SIMD3(0.20, 0.18, 0.34), color: SIMD4(0.24, 0.16, 0.12, 1), rotationX: stride * 0.3, player: player),
            part(.cube, position: SIMD3(0.14, 0.10, -0.04), scale: SIMD3(0.20, 0.18, 0.34), color: SIMD4(0.24, 0.16, 0.12, 1), rotationX: -stride * 0.3, player: player)
        ]
    }

    private static func part(
        _ primitive: Primitive,
        position: SIMD3<Float>,
        scale: SIMD3<Float>,
        color: SIMD4<Float>,
        rotationX: Float = 0,
        player: PlayerState
    ) -> PlayerDrawPart {
        let model = translation(player.position.simd)
            * rotationY(player.yaw)
            * translation(position)
            * rotationXMatrix(rotationX)
            * scaling(scale)
        return PlayerDrawPart(primitive: primitive, instance: InstanceData(modelMatrix: model, color: color))
    }

    private static func translation(_ value: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(value.x, value.y, value.z, 1)
        ))
    }

    private static func scaling(_ value: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(value.x, 0, 0, 0),
            SIMD4(0, value.y, 0, 0),
            SIMD4(0, 0, value.z, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }

    private static func rotationXMatrix(_ angle: Float) -> simd_float4x4 {
        let cosine = cos(angle)
        let sine = sin(angle)
        return simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0),
            SIMD4(0, cosine, sine, 0),
            SIMD4(0, -sine, cosine, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }

    private static func rotationY(_ angle: Float) -> simd_float4x4 {
        let cosine = cos(angle)
        let sine = sin(angle)
        return simd_float4x4(columns: (
            SIMD4(cosine, 0, sine, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(-sine, 0, cosine, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }
}
