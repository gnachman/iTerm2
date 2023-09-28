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
} iTermBlockVertexFunctionOutput;

vertex iTermBlockVertexFunctionOutput
iTermBlockVertexShader(uint vertexID [[ vertex_id ]],
                       constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                       constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                       device vector_float2 *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                       unsigned int iid [[instance_id]]) {
    iTermBlockVertexFunctionOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    pixelSpacePosition += perInstanceUniforms[iid].xy;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    return out;
}

fragment float4
iTermBlockFragmentShader(iTermBlockVertexFunctionOutput in [[stage_in]],
                         constant vector_float4 *color [[ buffer(iTermFragmentBufferIndexMarginColor) ]]) {
    return *color;
}
