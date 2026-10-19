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
    float4 cameraPosition;
    float4 shadowTexelSize;
    float4 trailCurve;
};

struct MaterialUniforms {
    float4 baseColorFactor;
    float4 surfaceProperties;
    uint4 flags;
};

struct TerrainMaterialUniforms {
    MaterialUniforms forest;
    MaterialUniforms dirt;
    MaterialUniforms rock;
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
    VertexOut output;
    output.position = frame.viewProjection * worldPosition;
    output.worldPosition = worldPosition.xyz;
    output.worldNormal = normalize(normalMatrix * input.normal);
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

float3 applyNormalMap(float3 normal, float3 worldPosition, float2 uv, float3 tangentNormal) {
    float3 positionX = dfdx(worldPosition);
    float3 positionY = dfdy(worldPosition);
    float2 uvX = dfdx(uv);
    float2 uvY = dfdy(uv);
    float3 tangent = normalize(positionX * uvY.y - positionY * uvX.y);
    float3 bitangent = normalize(-positionX * uvY.x + positionY * uvX.x);
    bitangent *= sign(dot(cross(tangent, bitangent), normal));
    return normalize(tangent * tangentNormal.x + bitangent * tangentNormal.y + normal * tangentNormal.z);
}

float distributionGGX(float normalHalf, float roughness) {
    float alpha = roughness * roughness;
    float alphaSquared = alpha * alpha;
    float denominator = normalHalf * normalHalf * (alphaSquared - 1.0) + 1.0;
    return alphaSquared / max(M_PI_F * denominator * denominator, 0.0001);
}

float geometrySchlickGGX(float normalView, float roughness) {
    float value = roughness + 1.0;
    float k = value * value / 8.0;
    return normalView / max(normalView * (1.0 - k) + k, 0.0001);
}

float3 fresnelSchlick(float viewHalf, float3 baseReflectance) {
    return baseReflectance + (1.0 - baseReflectance) * pow(clamp(1.0 - viewHalf, 0.0, 1.0), 5.0);
}

float shadowAmount(
    VertexOut input,
    float3 normal,
    float3 lightDirection,
    depth2d<float> shadowMap,
    sampler shadowSampler,
    constant FrameUniforms &frame) {
    float3 shadowNDC = input.shadowPosition.xyz / input.shadowPosition.w;
    float2 shadowUV = float2(shadowNDC.x * 0.5 + 0.5, 0.5 - shadowNDC.y * 0.5);
    if (!all(shadowUV >= 0.0) || !all(shadowUV <= 1.0) || shadowNDC.z < 0.0 || shadowNDC.z > 1.0) {
        return 0.0;
    }
    float bias = max(0.00025, 0.0009 * (1.0 - max(dot(normal, lightDirection), 0.0)));
    float amount = 0.0;
    for (int y = -2; y <= 2; ++y) {
        for (int x = -2; x <= 2; ++x) {
            float2 offset = float2(x, y) * frame.shadowTexelSize.xy * frame.shadowTexelSize.z;
            float occluderDepth = shadowMap.sample(shadowSampler, shadowUV + offset);
            amount += shadowNDC.z - bias > occluderDepth ? 1.0 : 0.0;
        }
    }
    return amount / 25.0;
}

float3 pbrLighting(
    float3 albedo,
    float roughness,
    float metallic,
    float ambientOcclusion,
    float3 normal,
    float3 worldPosition,
    float3 cameraPosition,
    float3 lightDirection,
    float shadow) {
    float3 viewDirection = normalize(cameraPosition - worldPosition);
    float3 halfDirection = normalize(viewDirection + lightDirection);
    float normalLight = max(dot(normal, lightDirection), 0.0);
    float normalView = max(dot(normal, viewDirection), 0.001);
    float normalHalf = max(dot(normal, halfDirection), 0.0);
    float viewHalf = max(dot(viewDirection, halfDirection), 0.0);
    float3 reflectance = mix(float3(0.04), albedo, metallic);
    float3 fresnel = fresnelSchlick(viewHalf, reflectance);
    float distribution = distributionGGX(normalHalf, roughness);
    float geometry = geometrySchlickGGX(normalView, roughness) * geometrySchlickGGX(normalLight, roughness);
    float3 specular = distribution * geometry * fresnel / max(4.0 * normalView * normalLight, 0.001);
    float3 diffuseWeight = (1.0 - fresnel) * (1.0 - metallic);
    float3 direct = (diffuseWeight * albedo / M_PI_F + specular) * normalLight * (1.0 - shadow * 0.76);
    float3 ambient = albedo * (0.16 + 0.08 * max(normal.y, 0.0)) * ambientOcclusion;
    float3 color = ambient + direct;
    return color / (color + 1.0);
}

float3 terrainNormal(
    float3 baseNormal,
    float3 worldPosition,
    float2 uv,
    float3 forestNormal,
    float3 dirtNormal,
    float3 rockNormal,
    float3 weights) {
    float3 tangentNormal = normalize(forestNormal * weights.x + dirtNormal * weights.y + rockNormal * weights.z);
    return applyNormalMap(baseNormal, worldPosition, uv, tangentNormal);
}

fragment float4 world_fragment(
    VertexOut input [[stage_in]],
    bool frontFacing [[front_facing]],
    depth2d<float> shadowMap [[texture(0)]],
    texture2d<float> baseColorTexture [[texture(1)]],
    texture2d<float> normalTexture [[texture(2)]],
    texture2d<float> roughnessTexture [[texture(3)]],
    texture2d<float> metallicTexture [[texture(4)]],
    texture2d<float> ambientOcclusionTexture [[texture(5)]],
    texture2d<float> opacityTexture [[texture(6)]],
    texture2d<float> forestBaseColor [[texture(7)]],
    texture2d<float> forestNormalMap [[texture(8)]],
    texture2d<float> forestRoughness [[texture(9)]],
    texture2d<float> dirtBaseColor [[texture(10)]],
    texture2d<float> dirtNormalMap [[texture(11)]],
    texture2d<float> dirtRoughness [[texture(12)]],
    texture2d<float> rockBaseColor [[texture(13)]],
    texture2d<float> rockNormalMap [[texture(14)]],
    texture2d<float> rockRoughness [[texture(15)]],
    sampler shadowSampler [[sampler(0)]],
    sampler materialSampler [[sampler(1)]],
    constant FrameUniforms &frame [[buffer(0)]],
    constant MaterialUniforms &material [[buffer(1)]],
    constant TerrainMaterialUniforms &terrainMaterials [[buffer(2)]]) {
    float2 uv = input.texCoord * material.surfaceProperties.w;
    float4 sampledBase = baseColorTexture.sample(materialSampler, uv);
    float opacity = opacityTexture.sample(materialSampler, uv).r;
    float alpha = sampledBase.a * material.baseColorFactor.a * opacity;
    if (material.flags.x != 0 && alpha < material.surfaceProperties.z) {
        discard_fragment();
    }

    float3 normal = normalize(input.worldNormal);
    if (material.flags.y != 0 && !frontFacing) {
        normal = -normal;
    }
    float3 albedo = sampledBase.rgb * material.baseColorFactor.rgb * input.color.rgb;
    float roughness = material.surfaceProperties.x * roughnessTexture.sample(materialSampler, uv).r;
    float metallic = material.surfaceProperties.y * metallicTexture.sample(materialSampler, uv).r;
    float ambientOcclusion = ambientOcclusionTexture.sample(materialSampler, uv).r;

    if (material.flags.z != 0) {
        float slope = 1.0 - max(normal.y, 0.0);
        float rockWeight = smoothstep(0.25, 0.62, slope) * 0.82;
        float pathCenterX = frame.trailCurve.x * sin(input.worldPosition.z * frame.trailCurve.y)
            + frame.trailCurve.z * sin(input.worldPosition.z * frame.trailCurve.w);
        float pathWeight = (1.0 - smoothstep(1.0, 1.7, abs(input.worldPosition.x - pathCenterX))) * (1.0 - rockWeight);
        float3 weights = float3(max(0.0, 1.0 - pathWeight - rockWeight), pathWeight, rockWeight);
        float2 forestUV = input.worldPosition.xz * terrainMaterials.forest.surfaceProperties.w;
        float2 dirtUV = input.worldPosition.xz * terrainMaterials.dirt.surfaceProperties.w;
        float2 rockUV = input.worldPosition.xz * terrainMaterials.rock.surfaceProperties.w;
        float3 forestColor = forestBaseColor.sample(materialSampler, forestUV).rgb * terrainMaterials.forest.baseColorFactor.rgb;
        forestColor *= float3(0.48, 1.65, 0.30);
        float3 dirtColor = dirtBaseColor.sample(materialSampler, dirtUV).rgb * terrainMaterials.dirt.baseColorFactor.rgb;
        float3 rockColor = rockBaseColor.sample(materialSampler, rockUV).rgb * terrainMaterials.rock.baseColorFactor.rgb;
        albedo = (forestColor * weights.x + dirtColor * weights.y + rockColor * weights.z)
            * material.baseColorFactor.rgb * input.color.rgb;
        float forestRough = forestRoughness.sample(materialSampler, forestUV).r * terrainMaterials.forest.surfaceProperties.x;
        float dirtRough = dirtRoughness.sample(materialSampler, dirtUV).r * terrainMaterials.dirt.surfaceProperties.x;
        float rockRough = rockRoughness.sample(materialSampler, rockUV).r * terrainMaterials.rock.surfaceProperties.x;
        roughness = forestRough * weights.x + dirtRough * weights.y + rockRough * weights.z;
        float3 forestNormal = normalize(forestNormalMap.sample(materialSampler, forestUV).xyz * 2.0 - 1.0);
        float3 dirtNormal = normalize(dirtNormalMap.sample(materialSampler, dirtUV).xyz * 2.0 - 1.0);
        float3 rockNormal = normalize(rockNormalMap.sample(materialSampler, rockUV).xyz * 2.0 - 1.0);
        normal = terrainNormal(normal, input.worldPosition, input.worldPosition.xz, forestNormal, dirtNormal, rockNormal, weights);
    } else if (material.flags.w != 0) {
        float3 tangentNormal = normalize(normalTexture.sample(materialSampler, uv).xyz * 2.0 - 1.0);
        normal = applyNormalMap(normal, input.worldPosition, uv, tangentNormal);
    }

    float3 lightDirection = normalize(frame.lightDirection.xyz);
    float shadow = shadowAmount(input, normal, lightDirection, shadowMap, shadowSampler, frame);
    float3 color = pbrLighting(
        albedo,
        clamp(roughness, 0.045, 1.0),
        clamp(metallic, 0.0, 1.0),
        ambientOcclusion,
        normal,
        input.worldPosition,
        frame.cameraPosition.xyz,
        lightDirection,
        shadow
    );
    return float4(color, alpha);
}

fragment void shadow_fragment(
    ShadowVertexOut input [[stage_in]],
    texture2d<float> baseColorTexture [[texture(0)]],
    texture2d<float> opacityTexture [[texture(1)]],
    sampler materialSampler [[sampler(0)]],
    constant MaterialUniforms &material [[buffer(0)]]) {
    if (material.flags.x != 0) {
        float2 uv = input.texCoord * material.surfaceProperties.w;
        float alpha = baseColorTexture.sample(materialSampler, uv).a * material.baseColorFactor.a;
        alpha *= opacityTexture.sample(materialSampler, uv).r;
        if (alpha < material.surfaceProperties.z) {
            discard_fragment();
        }
    }
}
