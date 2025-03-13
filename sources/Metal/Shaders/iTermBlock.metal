//
//  iTermBlock.metal
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/27/23.
//

#include <metal_stdlib>
using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float2 pixelPosition;
    float2 minBounds;
    float2 maxBounds;
    bool outline;
    uint8_t colorIndex;
} iTermBlockVertexFunctionOutput;

vertex iTermBlockVertexFunctionOutput
iTermBlockVertexShader(uint vertexID [[ vertex_id ]],
                       constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                       constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                       device vector_float2 *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                       unsigned int iid [[instance_id]]) {
    iTermBlockVertexFunctionOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    pixelSpacePosition.y += perInstanceUniforms[iid].y;
    float2 viewportSize = float2(*viewportSizePointer);

    // Convert to clip space
    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    // Store pixel-space position
    out.pixelPosition = pixelSpacePosition;

    // Compute quad bounds
    float2 minBounds = float2(INFINITY);
    float2 maxBounds = float2(-INFINITY);
    for (uint i = 0; i < 3; i++) {
        float2 pos = vertexArray[i].position.xy;
        pos.y += perInstanceUniforms[iid].y;
        minBounds = min(minBounds, pos);
        maxBounds = max(maxBounds, pos);
    }

    out.minBounds = minBounds;
    out.maxBounds = maxBounds;
    out.outline = !!(static_cast<int>(perInstanceUniforms[iid].x) & 1);
    out.colorIndex = !!(static_cast<int>(perInstanceUniforms[iid].x) & 2);

    return out;
}

fragment float4
iTermBlockFragmentShader(iTermBlockVertexFunctionOutput in [[stage_in]],
                         constant vector_float4 *colors [[ buffer(iTermFragmentBufferIndexMarginColor) ]],
                         constant float *scale [[ buffer(iTermFragmentBufferIndexScale) ]]) {
    if (in.outline) {
        float2 distanceToEdge = min(in.pixelPosition - in.minBounds, in.maxBounds - in.pixelPosition);
        if (distanceToEdge.x <= *scale || distanceToEdge.y <= *scale) {
            return colors[in.colorIndex];
        } else {
            discard_fragment();
        }
    }
    return colors[in.colorIndex];
}
