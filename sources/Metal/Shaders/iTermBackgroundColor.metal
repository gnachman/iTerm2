#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float4 color;
    bool cancel;
} iTermBackgroundColorVertexFunctionOutput;

// Matches function in iTermOffscreenCommandLineBackgroundRenderer.m
static float4 iTermBlendColors(float4 src, float4 dst) {
    float4 out;
    out.w = src.w + dst.w * (1 - src.w);
    if (out.w > 0) {
        out.xyz = (src.xyz * src.w + dst.xyz * dst.w * (1 - src.w)) / out.w;
    } else {
        out.xyz = 0;
    }
    return out;
}

static float4 iTermPremultiply(float4 color) {
    float4 result = color;
    result.xyz *= color.w;
    return result;
}

vertex iTermBackgroundColorVertexFunctionOutput
iTermBackgroundColorVertexShader(uint vertexID [[ vertex_id ]],
                                 constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                                 constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                                 constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                                 constant iTermBackgroundColorPIU *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                                 constant iTermMetalBackgroundColorInfo *info [[ buffer(iTermVertexInputIndexDefaultBackgroundColorInfo) ]],
                                 unsigned int iid [[instance_id]]) {
    iTermBackgroundColorVertexFunctionOutput out;

    switch (info->mode) {
        case iTermBackgroundColorRendererModeAll:
            out.cancel = false;
            break;
        case iTermBackgroundColorRendererModeDefaultOnly:
            out.cancel = !perInstanceUniforms[iid].isDefault;
            break;
        case iTermBackgroundColorRendererModeNondefaultOnly:
            out.cancel = perInstanceUniforms[iid].isDefault;
            break;

    }

    // Stretch it horizontally and vertically. Vertex coordinates are 0 or the width/height of
    // a cell, so this works.
    const float runLength = perInstanceUniforms[iid].runLength;
    const float numRows = perInstanceUniforms[iid].numRows;
    float2 pixelSpacePosition = (vertexArray[vertexID].position.xy * float2(runLength, numRows) +
                                 perInstanceUniforms[iid].offset.xy +
                                 offset[0]);
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    out.color = iTermPremultiply(iTermBlendColors(perInstanceUniforms[iid].color,
                                                  info->defaultBackgroundColor));
    return out;
}

// Trivial changes in this implementation trigger metal compiler bugs (like putting `return in.color` in an else clause).
fragment float4
iTermBackgroundColorFragmentShader(iTermBackgroundColorVertexFunctionOutput in [[stage_in]]) {
    if (in.cancel) {
        discard_fragment();
        return float4(0, 0, 0, 0);
    }
    return in.color;
}
