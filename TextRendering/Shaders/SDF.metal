#include <metal_stdlib>
#include <simd/simd.h>
#include "ShaderStructures.h"

namespace mtlswift {}

using namespace metal;

constant bool deviceSupportsNonuniformThreadgroups [[ function_constant(0) ]];

float hypot(float x, float y)
{
    union {float f; uint32_t i;} ux = {x}, uy = {y}, ut;
    float z;

    ux.i &= -1U>>1;
    uy.i &= -1U>>1;
    if (ux.i < uy.i) {
        ut = ux;
        ux = uy;
        uy = ut;
    }

    x = ux.f;
    y = uy.f;
    if (uy.i == 0xff<<23)
        return y;
    if (ux.i >= 0xff<<23 || uy.i == 0 || ux.i - uy.i >= 25<<23)
        return x + y;

    z = 1;
    if (ux.i >= (0x7f+60)<<23) {
        z = 0x1p90f;
        x *= 0x1p-90f;
        y *= 0x1p-90f;
    } else if (uy.i < (0x7f-60)<<23) {
        z = 0x1p-90f;
        x *= 0x1p90f;
        y *= 0x1p90f;
    }
    return z*sqrt((float)x*x + (float)y*y);
}

/// mtlswift:dispatch:optimal(4):over:distanceMapTexture
kernel void sdfInitializationPhase(texture2d<float, access::write> distanceMapTexture [[ texture(0) ]],
                                   texture2d<ushort, access::write> boundaryPointMapTexture [[ texture(1) ]],
                                   constant float& maxDist [[buffer(0)]],
                                uint2 position [[thread_position_in_grid]]) {
    const ushort2 textureSize = ushort2(distanceMapTexture.get_width(),
                                        distanceMapTexture.get_height());
    if (!deviceSupportsNonuniformThreadgroups) {
        if (position.x >= textureSize.x || position.y >= textureSize.y) {
            return;
        }
    }

    distanceMapTexture.write(maxDist, position);
    boundaryPointMapTexture.write(0, position);
}

/// mtlswift:dispatch:optimal(4):over:distanceMapTexture
kernel void sdfInteriorExteriorPhase(texture2d<float, access::read_write> atlasTexture [[ texture(0) ]],
                                     texture2d<float, access::read_write> distanceMapTexture [[ texture(1) ]],
                                     texture2d<ushort, access::read_write> boundaryPointMapTexture [[ texture(2) ]],
                                     constant float& maxDist [[buffer(0)]],
                                     uint2 position [[thread_position_in_grid]]) {
    const ushort2 textureSize = ushort2(distanceMapTexture.get_width(),
                                        distanceMapTexture.get_height());
    if (!deviceSupportsNonuniformThreadgroups) {
        if (position.x >= textureSize.x || position.y >= textureSize.y) {
            return;
        }
    }

    if (position.x == 0 ||
        position.y == textureSize.x - 1 ||
        position.y == 0 ||
        position.y == textureSize.y - 1) {
        return;
    }

    bool inside = atlasTexture.read(position).r > 0x7f;
    if (atlasTexture.read(position.x - 1, position.y).r != inside ||
        atlasTexture.read(position.x + 1, position.y).r != inside ||
        atlasTexture.read(position.x, position.y - 1).r != inside ||
        atlasTexture.read(position.x, position.y + 1).r != inside) {
        distanceMapTexture.write(0, position);
        boundaryPointMapTexture.write(ushort4(position.x, position.y, 0, 1), position);
    }
}

/// mtlswift:dispatch:optimal(4):over:distanceMapTexture
kernel void sdfForwardDeadReckoningPass(texture2d<float, access::read_write> atlasTexture [[ texture(0) ]],
                                        texture2d<float, access::read_write> distanceMapTexture [[ texture(1) ]],
                                        texture2d<ushort, access::read_write> boundaryPointMapTexture [[ texture(2) ]],
                                        constant float& maxDist [[buffer(0)]],
                                        constant float& distDiag [[buffer(1)]],
                                        constant float& distUnit [[buffer(2)]],
                                        uint2 position [[thread_position_in_grid]]) {
    const ushort2 textureSize = ushort2(distanceMapTexture.get_width(),
                                        distanceMapTexture.get_height());
    if (!deviceSupportsNonuniformThreadgroups) {
        if (position.x >= textureSize.x || position.y >= textureSize.y) {
            return;
        }
    }

    if (position.x == 0 ||
        position.y == textureSize.x - 2 ||
        position.y == 0 ||
        position.y == textureSize.y - 2) {
        return;
    }

    const float distance = float(distanceMapTexture.read(position).r);

    uint2 currentPosition;

    currentPosition = uint2(position.x - 1, position.y - 1);
    if (distanceMapTexture.read(currentPosition).r + distDiag < distance) {
        auto nearestpt = boundaryPointMapTexture.read(currentPosition);
        auto distance = hypot(position.x - nearestpt.x, position.y - nearestpt.y);
        boundaryPointMapTexture.write(ushort4(ushort3(nearestpt), 1), position);
        distanceMapTexture.write(float4(float3(distance), 1), position);
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    currentPosition = uint2(position.x, position.y - 1);
    if (distanceMapTexture.read(currentPosition).r + distUnit < distance) {
        auto nearestpt = boundaryPointMapTexture.read(currentPosition);
        auto distance = hypot(position.x - nearestpt.x, position.y - nearestpt.y);
        boundaryPointMapTexture.write(ushort4(ushort3(nearestpt), 1), position);
        distanceMapTexture.write(float4(float3(distance), 1), position);
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    currentPosition = uint2(position.x + 1, position.y - 1);
    if (distanceMapTexture.read(currentPosition).r + distDiag < distance) {
        auto nearestpt = boundaryPointMapTexture.read(currentPosition);
        auto distance = hypot(position.x - nearestpt.x, position.y - nearestpt.y);
        boundaryPointMapTexture.write(ushort4(ushort3(nearestpt), 1), position);
        distanceMapTexture.write(float4(float3(distance), 1), position);
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    currentPosition = uint2(position.x - 1, position.y);
    if (distanceMapTexture.read(currentPosition).r + distUnit < distance) {
        auto nearestpt = boundaryPointMapTexture.read(currentPosition);
        auto distance = hypot(position.x - nearestpt.x, position.y - nearestpt.y);
        boundaryPointMapTexture.write(ushort4(ushort3(nearestpt), 1), position);
        distanceMapTexture.write(float4(float3(distance), 1), position);
    }
}

/// mtlswift:dispatch:optimal(4):over:distanceMapTexture
kernel void sdfBackwardDeadReckoningPass(texture2d<float, access::read_write> atlasTexture [[ texture(0) ]],
                                         texture2d<float, access::read_write> distanceMapTexture [[ texture(1) ]],
                                         texture2d<ushort, access::read_write> boundaryPointMapTexture [[ texture(2) ]],
                                         constant float& maxDist [[buffer(0)]],
                                         constant float& distDiag [[buffer(1)]],
                                         constant float& distUnit [[buffer(2)]],
                                         uint2 position [[thread_position_in_grid]]) {
    const ushort2 textureSize = ushort2(distanceMapTexture.get_width(),
                                        distanceMapTexture.get_height());
    if (!deviceSupportsNonuniformThreadgroups) {
        if (position.x >= textureSize.x || position.y >= textureSize.y) {
            return;
        }
    }

    auto x = textureSize.x - position.x;
    auto y = textureSize.y - position.y;
    auto newPosition = uint2(x, y);

    if (newPosition.x == 0 ||
        newPosition.y == textureSize.x - 2 ||
        newPosition.y == 0 ||
        newPosition.y == textureSize.y - 2) {
        return;
    }

    const float distance = float(distanceMapTexture.read(newPosition).r);

    uint2 currentPosition;

    currentPosition = uint2(newPosition.x + 1, newPosition.y);
    if (distanceMapTexture.read(currentPosition).r + distUnit < distance) {
        auto nearestpt = boundaryPointMapTexture.read(currentPosition);
        auto distance = hypot(newPosition.x - nearestpt.x, newPosition.y - nearestpt.y);
        boundaryPointMapTexture.write(ushort4(ushort3(nearestpt), 1), newPosition);
        distanceMapTexture.write(float4(float3(distance), 1), newPosition);
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    currentPosition = uint2(newPosition.x - 1, newPosition.y + 1);
    if (distanceMapTexture.read(currentPosition).r + distDiag < distance) {
        auto nearestpt = boundaryPointMapTexture.read(currentPosition);
        auto distance = hypot(newPosition.x - nearestpt.x, newPosition.y - nearestpt.y);
        boundaryPointMapTexture.write(ushort4(ushort3(nearestpt), 1), newPosition);
        distanceMapTexture.write(float4(float3(distance), 1), newPosition);
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    currentPosition = uint2(newPosition.x, newPosition.y + 1);
    if (distanceMapTexture.read(currentPosition).r + distUnit < distance) {
        auto nearestpt = boundaryPointMapTexture.read(currentPosition);
        auto distance = hypot(newPosition.x - nearestpt.x, newPosition.y - nearestpt.y);
        boundaryPointMapTexture.write(ushort4(ushort3(nearestpt), 1), newPosition);
        distanceMapTexture.write(float4(float3(distance), 1), newPosition);
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    currentPosition = uint2(newPosition.x + 1, newPosition.y + 1);
    if (distanceMapTexture.read(currentPosition).r + distDiag < distance) {
        auto nearestpt = boundaryPointMapTexture.read(currentPosition);
        auto distance = hypot(newPosition.x - nearestpt.x, newPosition.y - nearestpt.y);
        boundaryPointMapTexture.write(ushort4(ushort3(nearestpt), 1), newPosition);
        distanceMapTexture.write(float4(float3(distance), 1), newPosition);
    }

}

/// mtlswift:dispatch:optimal(4):over:distanceMapTexture
kernel void sdfinteriorDistanceNegationPass(texture2d<float, access::read_write> atlasTexture [[ texture(0) ]],
                                            texture2d<float, access::read_write> distanceMapTexture [[ texture(1) ]],
                                            uint2 position [[thread_position_in_grid]]) {
    const ushort2 textureSize = ushort2(distanceMapTexture.get_width(),
                                        distanceMapTexture.get_height());
    if (!deviceSupportsNonuniformThreadgroups) {
        if (position.x >= textureSize.x || position.y >= textureSize.y) {
            return;
        }
    }

    bool inside = atlasTexture.read(position).r > 0x7f;
    if (inside) {
        const float distance = float(distanceMapTexture.read(position).r);
        distanceMapTexture.write(float4(float3(-distance), 1), position);
    }

}
