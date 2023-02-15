#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float4 color;
} iTermSolidColorVertexShaderOutput;

vertex iTermSolidColorVertexShaderOutput
iTermSolidColorVertexShader(uint vertexID [[ vertex_id ]],
                            constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                            constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                            constant float4 *colors  [[ buffer(iTermVertexColorArray) ]]) {
    iTermSolidColorVertexShaderOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;
    out.color = colors[vertexID / 6];
    
    return out;
}

fragment float4
iTermSolidColorFragmentShader(iTermSolidColorVertexShaderOutput in [[stage_in]]) {
    return in.color;
}
