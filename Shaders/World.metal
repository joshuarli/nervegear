#include <metal_stdlib>
using namespace metal;

struct InstanceData {
    float4x4 modelMatrix;
    float4 color;
};

struct FrameUniforms {
    float4x4 viewProjection;
    float4x4 lightViewProjection;
    float4 lightDirection;
    float4 shadowTexelSize;
};

struct VertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 worldNormal;
    float4 color;
    float4 shadowPosition;
    float2 texCoord;
};

struct ShadowVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct MeshVertex {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float4 color [[attribute(2)]];
    float2 texCoord [[attribute(3)]];
};

vertex VertexOut world_vertex(
    MeshVertex input [[stage_in]],
    uint instanceID [[instance_id]],
    constant InstanceData *instances [[buffer(1)]],
    constant FrameUniforms &frame [[buffer(2)]]) {
    InstanceData instance = instances[instanceID];
    float4 worldPosition = instance.modelMatrix * float4(input.position, 1.0);
    float3 modelScale = float3(
        length(instance.modelMatrix[0].xyz),
        length(instance.modelMatrix[1].xyz),
        length(instance.modelMatrix[2].xyz)
    );
    float3x3 normalMatrix = float3x3(
        instance.modelMatrix[0].xyz / (modelScale.x * modelScale.x),
        instance.modelMatrix[1].xyz / (modelScale.y * modelScale.y),
        instance.modelMatrix[2].xyz / (modelScale.z * modelScale.z)
    );
    float3 worldNormal = normalize(normalMatrix * input.normal);
    VertexOut output;
    output.position = frame.viewProjection * worldPosition;
    output.worldPosition = worldPosition.xyz;
    output.worldNormal = worldNormal;
    output.color = instance.color * input.color;
    output.shadowPosition = frame.lightViewProjection * worldPosition;
    output.texCoord = input.texCoord;
    return output;
}

vertex ShadowVertexOut shadow_vertex(
    MeshVertex input [[stage_in]],
    uint instanceID [[instance_id]],
    constant InstanceData *instances [[buffer(1)]],
    constant FrameUniforms &frame [[buffer(2)]]) {
    ShadowVertexOut output;
    output.position = frame.lightViewProjection * instances[instanceID].modelMatrix * float4(input.position, 1.0);
    output.texCoord = input.texCoord;
    return output;
}

fragment float4 world_fragment(
    VertexOut input [[stage_in]],
    depth2d<float> shadowMap [[texture(0)]],
    texture2d<float> albedoTexture [[texture(1)]],
    sampler shadowSampler [[sampler(0)]],
    sampler albedoSampler [[sampler(1)]],
    constant FrameUniforms &frame [[buffer(0)]]) {
    float4 albedo = albedoTexture.sample(albedoSampler, input.texCoord);
    if (albedo.a < 0.5) {
        discard_fragment();
    }
    float3 normal = normalize(input.worldNormal);
    float3 lightDirection = normalize(frame.lightDirection.xyz);
    float diffuse = max(dot(normal, lightDirection), 0.0);
    float shadow = 0.0;
    float3 shadowNDC = input.shadowPosition.xyz / input.shadowPosition.w;
    float2 shadowUV = float2(shadowNDC.x * 0.5 + 0.5, 0.5 - shadowNDC.y * 0.5);
    if (all(shadowUV >= 0.0) && all(shadowUV <= 1.0) && shadowNDC.z >= 0.0 && shadowNDC.z <= 1.0) {
        for (int y = -1; y <= 1; ++y) {
            for (int x = -1; x <= 1; ++x) {
                float2 offset = float2(x, y) * frame.shadowTexelSize.xy;
                float occluderDepth = shadowMap.sample(shadowSampler, shadowUV + offset);
                shadow += shadowNDC.z - 0.0022 > occluderDepth ? 1.0 : 0.0;
            }
        }
        shadow /= 9.0;
    }
    float lighting = 0.28 + diffuse * (1.0 - shadow * 0.78);
    return float4(input.color.rgb * albedo.rgb * lighting, input.color.a * albedo.a);
}

fragment void shadow_fragment(
    ShadowVertexOut input [[stage_in]],
    texture2d<float> albedoTexture [[texture(0)]],
    sampler albedoSampler [[sampler(0)]]) {
    if (albedoTexture.sample(albedoSampler, input.texCoord).a < 0.5) {
        discard_fragment();
    }
}
