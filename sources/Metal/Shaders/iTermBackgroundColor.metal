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
                                 device iTermBackgroundColorConfiguration *config [[ buffer(iTermVertexInputBackgroundColorConfiguration) ]],
                                 device iTermCellColors *cellColors [[ buffer(iTermVertexInputCellColors) ]],
                                 unsigned int iid [[instance_id]]) {
    iTermBackgroundColorVertexFunctionOutput out;

    const int width = config->gridSize.x + 1;  // include EOL marker
    const int height = config->gridSize.y - 1;
    float2 coord = float2(iid % width,
                          height - iid / width);
    float2 pixelSpacePosition = *offset + vertexArray[vertexID].position.xy + coord * config->cellSize;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    out.color = cellColors[iid].backgroundColor;

    return out;
}

fragment float4
iTermBackgroundColorFragmentShader(iTermBackgroundColorVertexFunctionOutput in [[stage_in]]) {
    return in.color;
}
