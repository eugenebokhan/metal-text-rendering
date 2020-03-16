#include <metal_stdlib>
#include <simd/simd.h>
#include "ShaderStructures.h"

using namespace metal;
constant bool deviceSupportsNonuniformThreadgroups [[ function_constant(0) ]];

struct TransformedVertex {
    float4 position [[position]];
    float2 texCoords;
};

vertex TransformedVertex vertex_shade(constant Vertex *vertices [[buffer(0)]],
                                      constant Uniforms &uniforms [[buffer(1)]],
                                      uint vid [[vertex_id]]) {
    TransformedVertex outVert;
    outVert.position = uniforms.viewProjectionMatrix * uniforms.modelMatrix * float4(vertices[vid].position);
    outVert.texCoords = vertices[vid].texCoords;
    return outVert;
}

fragment half4 fragment_shade(TransformedVertex vert [[stage_in]],
                              constant Uniforms &uniforms [[buffer(0)]],
                              sampler samplr [[sampler(0)]],
                              texture2d<float, access::sample> texture [[texture(0)]]) {
    float4 color = uniforms.foregroundColor;
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
    const float clampDist = fmax(-normalizationFactor,
                                 fmin(distance,
                                      normalizationFactor));
    const float scaledDist = clampDist / normalizationFactor;
    const float resultValue = ((scaledDist + 1) / 2);
    sdfTexture.write(resultValue, position);
}
