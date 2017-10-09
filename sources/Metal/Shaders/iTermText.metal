#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float2 textureCoordinate;
    int colorModelIndex;
} iTermTextVertexFunctionOutput;

vertex iTermTextVertexFunctionOutput
iTermTextVertexShader(uint vertexID [[ vertex_id ]],
                      constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                      constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                      constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                      constant iTermTextPIU *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                      unsigned int iid [[instance_id]]) {
    iTermTextVertexFunctionOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].position.xy + perInstanceUniforms[iid].offset.xy + offset[0];
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    out.textureCoordinate = vertexArray[vertexID].textureCoordinate + perInstanceUniforms[iid].textureOffset;
    out.colorModelIndex = perInstanceUniforms[iid].colorModelIndex;

    return out;
}

fragment float4
iTermTextFragmentShader(iTermTextVertexFunctionOutput in [[stage_in]],
                        texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]],
                        constant unsigned char *colorModels [[ buffer(iTermFragmentBufferIndexColorModels) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    const half4 bwColor = texture.sample(textureSampler, in.textureCoordinate);

    if (bwColor.x == 1 && bwColor.y == 1 && bwColor.z == 1) {
        // TODO
        // This doesn't draw the background when the pixel doesn't contain any of the glyph.
        // But this will look terrible over a background image, diagonal stripes, or badge. I should
        // build a fixed number of color models that evenly sample the space of possible color
        // models, then sample the color in the drawable and have the fragment shader interpolate
        // between the nearest models for the background color of this pixel.
        discard_fragment();
    }
    const short4 bwIntColor = static_cast<short4>(bwColor * 255);
    const short4 bwIntIndices = bwIntColor * 3 + short4(0, 1, 2, 0);

    // Base index for this color model
    const int i = in.colorModelIndex * 256 * 3;
    // Find RGB values to map colors in the black-on-white glyph to
    const uchar4 rgba = uchar4(colorModels[i + bwIntIndices.x],
                               colorModels[i + bwIntIndices.y],
                               colorModels[i + bwIntIndices.z],
                               255);
    return static_cast<float4>(rgba) / 255;
}

