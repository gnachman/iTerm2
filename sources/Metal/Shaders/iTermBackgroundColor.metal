#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float4 color;
} iTermBackgroundColorVertexFunctionOutput;

float4 iTermBlendColors(float4 src, float4 dst) {
    float4 out;
    out.w = src.w + dst.w * (1 - src.w);
    if (out.w > 0) {
        out.xyz = (src.xyz * src.w + dst.xyz * dst.w * (1 - src.w)) / out.w;
    } else {
        out.xyz = 0;
    }
    return out;
}

float4 iTermPremultiply(float4 color) {
    float4 result = color;
    result.xyz *= color.w;
    return result;
}

vertex iTermBackgroundColorVertexFunctionOutput
iTermBackgroundColorVertexShader(uint vertexID [[ vertex_id ]],
                                 constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                                 constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                                 constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                                 device iTermBackgroundColorPIU *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                                 constant iTermMetalBackgroundColorInfo *info [[ buffer(iTermVertexInputIndexDefaultBackgroundColorInfo) ]],
                                 unsigned int iid [[instance_id]]) {
    iTermBackgroundColorVertexFunctionOutput out;

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

//    const float src_A = perInstanceUniforms[iid].color.w * info->transparencyAlpha;
//    const float dst_A = info->defaultBackgroundColor.w;
//    const float3 dst_RGB = info->defaultBackgroundColor.xyz;
//    const float3 src_RGB = perInstanceUniforms[iid].color.xyz;
//    const float out_A = src_A + dst_A * (1.0 - src_A);
//    float3 out_RGB;
//    if (out_A > 0) {
//        out_RGB = (src_RGB * src_A + dst_RGB * dst_A * (1 - src_A)) / out_A;
//    } else {
//        out_RGB = 0;
//    }
//    out.color.xyz = out_RGB;
//    out.color.w = out_A;
    out.color = iTermPremultiply(iTermBlendColors(perInstanceUniforms[iid].color, // Selection color  e.g. float4(0.75, 0.86, 1.0, 0.50) works
                                                  info->defaultBackgroundColor));
    return out;
}

fragment float4
iTermBackgroundColorFragmentShader(iTermBackgroundColorVertexFunctionOutput in [[stage_in]]) {
    return in.color;
}
