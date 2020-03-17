#include <metal_stdlib>
#include <simd/simd.h>
#include "ShaderStructures.h"

using namespace metal;
constant bool deviceSupportsNonuniformThreadgroups [[ function_constant(0) ]];

struct TransformedVertex {
    float4 position [[position]];
    float2 texCoords;
};

vertex TransformedVertex vertex_shade(constant TextMeshVertex* vertices [[ buffer(0) ]],
                                      constant matrix_float4x4& viewProjectionMatrix [[ buffer(1) ]],
                                      uint vertexID [[ vertex_id ]]) {
    TransformedVertex outVert;
    outVert.position = viewProjectionMatrix * float4(vertices[vertexID].position);
    outVert.texCoords = vertices[vertexID].texCoords;
    return outVert;
}

fragment half4 fragment_shade(TransformedVertex vert [[stage_in]],
                              constant float4& color [[buffer(0)]],
                              sampler samplr [[sampler(0)]],
                              texture2d<float, access::sample> texture [[texture(0)]]) {
    // Outline of glyph is the isocontour with value 50%
    float edgeDistance = 0.5;
    // Sample the signed-distance field to find distance from this fragment to the glyph outline
    float sampleDistance = texture.sample(samplr, vert.texCoords).r;
    // Use local automatic gradients to find anti-aliased anisotropic edge width, cf. Gustavson 2012
    float edgeWidth = 0.75 * length(float2(dfdx(sampleDistance), dfdy(sampleDistance)));
    // Smooth the glyph edge by interpolating across the boundary in a band with the width determined above
    float insideness = smoothstep(edgeDistance - edgeWidth, edgeDistance + edgeWidth, sampleDistance);
    return half4(color.r, color.g, color.b, insideness);
}

kernel void quantizeDistanceField(texture2d<float, access::read_write> sdfTexture [[ texture(0) ]],
                                   constant float& normalizationFactor [[buffer(0)]],
                                uint2 position [[thread_position_in_grid]]) {
    const ushort2 textureSize = ushort2(sdfTexture.get_width(),
                                        sdfTexture.get_height());
    if (!deviceSupportsNonuniformThreadgroups) {
        if (position.x >= textureSize.x || position.y >= textureSize.y) {
            return;
        }
    }

    const float distance = sdfTexture.read(position).r;
    const float clampDist = fmax(-normalizationFactor, fmin(distance, normalizationFactor));
    const float scaledDist = clampDist / normalizationFactor;
    const float resultValue = ((scaledDist + 1) / 2);
    sdfTexture.write(resultValue, position);
}
