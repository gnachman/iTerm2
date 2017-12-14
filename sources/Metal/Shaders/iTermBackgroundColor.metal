#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float4 color;
} iTermBackgroundColorVertexFunctionOutput;

vertex iTermBackgroundColorVertexFunctionOutput
iTermBackgroundColorVertexShader(uint vertexID [[ vertex_id ]],
                                 constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                                 constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                                 constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                                 constant iTermBackgroundColorPIU *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                                 unsigned int iid [[instance_id]]) {
    iTermBackgroundColorVertexFunctionOutput out;

    // Stretch it horizontally by a factor of runLength. This works because vertex x coordinates are
    // either 0 or the width of a cell.
    const float runLength = perInstanceUniforms[iid].runLength;
    float2 pixelSpacePosition = (vertexArray[vertexID].position.xy * float2(runLength, 1) +
                                 perInstanceUniforms[iid].offset.xy +
                                 offset[0]);
    float2 viewportSize = float2(*viewportSizePointer);
    
    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;
    
    out.color = perInstanceUniforms[iid].color;
    
    return out;
}

fragment float4
iTermBackgroundColorFragmentShader(iTermBackgroundColorVertexFunctionOutput in [[stage_in]]) {
    return in.color;
}
