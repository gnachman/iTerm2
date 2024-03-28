//
//  Rectangle.metal
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/23/24.
//

#include <metal_stdlib>
using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float4 color;
} iTermRectangleVertexFunctionOutput;

vertex iTermRectangleVertexFunctionOutput
iTermRectangleVertexShader(uint vertexID [[ vertex_id ]],
                           constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                           constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                           device vector_float4 *color [[ buffer(iTermVertexColorArray) ]],
                           unsigned int iid [[instance_id]]) {
    iTermRectangleVertexFunctionOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    out.color = *color;
    return out;
}

fragment float4
iTermRectangleFragmentShader(iTermRectangleVertexFunctionOutput in [[stage_in]]) {
    return in.color;
}
