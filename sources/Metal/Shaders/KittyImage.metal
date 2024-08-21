#include <metal_stdlib>
using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float2 textureCoordinate;
} iTermKittyImageVertexFunctionOutput;

vertex iTermKittyImageVertexFunctionOutput
KittyImageVertexShader(uint vertexID [[ vertex_id ]],
                           constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                           constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                           unsigned int iid [[instance_id]]) {
    iTermKittyImageVertexFunctionOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;

    return out;
}

fragment float4
KittyImageFragmentShader(iTermKittyImageVertexFunctionOutput in [[stage_in]],
                         texture2d<float> texture [[ texture(iTermTextureIndexPrimary) ]]) {
    // return float4(1,0,0,1);
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);

    if (in.textureCoordinate.x < 0.0 ||
        in.textureCoordinate.x > 1.0 ||
        in.textureCoordinate.y < 0.0 ||
        in.textureCoordinate.y > 1.0) {
        return float4(0.0, 0.0, 0.0, 0.0);
    }
    return texture.sample(textureSampler, in.textureCoordinate);
}
