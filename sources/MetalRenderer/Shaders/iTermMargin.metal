//
//  iTermMargin.metal
//  iTerm2
//
//  Created by George Nachman on 11/19/17.
//

#include <metal_stdlib>
using namespace metal;

#import "iTermShaderTypes.h"

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

typedef struct {
    float4 clipSpacePosition [[position]];
} iTermMarginVertexFunctionOutput;

vertex iTermMarginVertexFunctionOutput
iTermMarginVertexShader(uint vertexID [[ vertex_id ]],
                        constant vector_float2 *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                        constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]]) {
    iTermMarginVertexFunctionOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].xy;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    return out;
}

fragment float4
iTermMarginFragmentShader(iTermMarginVertexFunctionOutput in [[stage_in]],
                          constant vector_float4 *color [[ buffer(iTermFragmentBufferIndexMarginColor) ]]) {
    return *color;
}

// PIU-based drawing is used when extending a background color into the margin.
// It draws each line of the left and right margins separately.

typedef struct {
    float4 clipSpacePosition [[position]];
    vector_float4 color;
} iTermMarginPIUVertexFunctionOutput;

vertex iTermMarginPIUVertexFunctionOutput
iTermMarginPIUVertexShader(uint vertexID [[ vertex_id ]],
                           constant iTermMarginExtensionPIU *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                           unsigned int iid [[instance_id]],
                           constant vector_float2 *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                           constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]]) {
    iTermMarginPIUVertexFunctionOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].xy;
    pixelSpacePosition.y += perInstanceUniforms[iid].yOffset;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;
    
    out.color = iTermPremultiply(iTermBlendColors(perInstanceUniforms[iid].color,
                                                  perInstanceUniforms[iid].defaultBackgroundColor));

    return out;
}

fragment float4
iTermMarginPIUFragmentShader(iTermMarginPIUVertexFunctionOutput in [[stage_in]]) {
    return in.color;
}

