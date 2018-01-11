//
//  iTermHighlightRow.metal
//  iTerm2
//
//  Created by George Nachman on 11/19/17.
//

#include <metal_stdlib>
using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
} iTermHighlightRowVertexFunctionOutput;

vertex iTermHighlightRowVertexFunctionOutput
iTermHighlightRowVertexShader(uint vertexID [[ vertex_id ]],
                              constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                              constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]]) {
    iTermHighlightRowVertexFunctionOutput out;
    
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);
    
    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;
    
    return out;
}

fragment float4
iTermHighlightRowFragmentShader(iTermHighlightRowVertexFunctionOutput in [[stage_in]],
                                constant vector_float4 *color [[ buffer(iTermFragmentBufferIndexMarginColor) ]]) {
    return *color;
}
