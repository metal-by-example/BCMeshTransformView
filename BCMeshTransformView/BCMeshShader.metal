//
//  BCMeshShader.metal
//  BCMeshTransformViewDemo
//
//  Copyright (c) 2014 Bartosz Ciechanowski. All rights reserved.
//  Translated to Metal, 2022 Warren Moore.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float4 position  [[attribute(0)]];
    float3 normal    [[attribute(1)]];
    float2 texCoords [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 shading;
    float2 texCoords;
};

struct Uniforms {
    float4x4 viewProjectionMatrix;
    float3x3 normalMatrix;
    float3 lightDirection;
    float diffuseFactor;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant Uniforms &uniforms [[buffer(1)]])
{
    VertexOut out;
    out.position = uniforms.viewProjectionMatrix * in.position;

    float3 worldNormal = normalize(uniforms.normalMatrix * in.normal);
    float diffuseIntensity = abs(dot(worldNormal, uniforms.lightDirection));
    float diffuse = mix(1.0, diffuseIntensity, uniforms.diffuseFactor);

    out.shading = float4(diffuse, diffuse, diffuse, 1.0);
    out.texCoords = in.texCoords;

    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float, access::sample> image [[texture(0)]])
{
    constexpr sampler imageSampler(coord::normalized,
                                   filter::linear,
                                   mip_filter::none,
                                   address::clamp_to_edge);

    // Branchless transparent texture border
    float2 centered = abs(in.texCoords - float2(0.5));
    // if tex coords are out of bounds, they're over 0.5 at this point
    float2 clamped = clamp(sign(centered - float2(0.5)), 0.0, 1.0);
    // If a tex coord is out of bounds, then it's equal to 1.0 at this point, otherwise it's 0.0.
    // If either coordinate is 1.0, then their sum will be larger than zero
    float inBounds = 1.0 - clamp(clamped.x + clamped.y, 0.0, 1.0);

    float4 color = in.shading * image.sample(imageSampler, in.texCoords) * inBounds;
    return color;
}
