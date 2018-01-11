//
//  iTermMargin.metal
//  iTerm2
//
//  Created by George Nachman on 11/19/17.
//

#include <metal_stdlib>
using namespace metal;

#import "iTermShaderTypes.h"

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
