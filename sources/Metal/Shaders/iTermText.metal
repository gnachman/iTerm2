#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float2 textureCoordinate;
    float2 backgroundTextureCoordinate;
    float4 textColor;
    float4 backgroundColor;
    bool recolor;
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

    out.backgroundTextureCoordinate = pixelSpacePosition / viewportSize;
    out.backgroundTextureCoordinate.y = 1 - out.backgroundTextureCoordinate.y;
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate + perInstanceUniforms[iid].textureOffset;
    out.textColor = perInstanceUniforms[iid].textColor;
    out.backgroundColor = perInstanceUniforms[iid].backgroundColor;
    out.recolor = perInstanceUniforms[iid].remapColors;

    return out;
}

fragment float4
iTermTextFragmentShaderSolidBackground(iTermTextVertexFunctionOutput in [[stage_in]],
                                       texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]],
                                       constant unsigned char *colorModels [[ buffer(iTermFragmentBufferIndexColorModels) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    const half4 bwColor = texture.sample(textureSampler, in.textureCoordinate);

    if (!in.recolor) {
        return static_cast<float4>(bwColor);
    }
    if (bwColor.x == 1 && bwColor.y == 1 && bwColor.z == 1) {
        discard_fragment();
    }
    // For a discussion of this code, see this document:
    // https://docs.google.com/document/d/1vfBq6vg409Zky-IQ7ne-Yy7olPtVCl0dq3PG20E8KDs

    // The formulas for bilinear interpolation came from:
    // https://en.wikipedia.org/wiki/Bilinear_interpolation
    //
    // The goal is to estimate the color of a pixel at P. We have to find the correct remapping
    // table for this cell's foreground/background color. The x axis is the text color and the
    // y axis is the background color.
    //
    // We'll find the four remapping tables that are closest to representing the text/background
    // color at this cell. We'll look up the black-and-white glyph's  color for this pixel in those
    // in those four remapping tables. Then we'll use bilinear interpolation to come up with an
    // estimate of what color to output.
    //
    // From a random sample of 1000 text/bg color combinations this gets within 2.3/255 of the
    // correct color in the worst case.
    //
    // TODO: Ask someone smart if there's a more efficient way to do this.
    //
    //    |   Q12             Q22
    // y2 |..*...............*...........
    //    |  :       :       :
    //    |  :       :P      :
    //  y |..........*...................
    //    |  :       :       :
    //    |  :       :       :
    //    |  :Q11    :       :Q21
    // y1 |..*...............*...........
    //    |  :       :       :
    //    |  :       :       :
    //    +---------------------------------
    //      x1       x       x2

    // Get text and background color in [0, 255]
    float4 x = in.textColor * 255.0;
    // TODO: Sample the background color from the drawable and blend it if needed.
    float4 y = in.backgroundColor * 255.0;

    // Indexes to lower and upper neighbors for x in [0, 17]
    int4 x1i = static_cast<int4>(floor(x / 15.0));
    int4 x2i = min(17, x1i + 1);
    // Make sure x1i != x2i
    x1i = max(0, x2i - 1);

    // Values of lower and upper neighbors for x in [0, 255]
    float4 x1 = static_cast<float4>(x1i) * 15.0;
    float4 x2 = static_cast<float4>(x2i) * 15.0;

    // Indexes to lower and upper neighbors for y in [0, 17]
    int4 y1i = static_cast<int4>(floor(y / 15.0));
    int4 y2i = min(17, y1i + 1);
    // Make sure y1i != y2i
    y1i = max(0, y2i - 1);

    // Values of lower and upper neighbors for y in [0, 255]
    float4 y1 = static_cast<float4>(y1i) * 15.0;
    float4 y2 = static_cast<float4>(y2i) * 15.0;

    // Index into tables (x,y,z ~ index for r,g,b)
    int4 i = static_cast<int4>(round(bwColor * 255));

    // indexes to use to look up f(Q_y_x)
    // 18 is the multiplier because the color models are quantized to the color in [0,255] / 17.0 and
    // there's an off-by-one thing going on here.
    int4 fq11i = 256 * (x1i * 18 + y1i) + i;
    int4 fq12i = 256 * (x1i * 18 + y2i) + i;
    int4 fq21i = 256 * (x2i * 18 + y1i) + i;
    int4 fq22i = 256 * (x2i * 18 + y2i) + i;

    // Four neighbors' values in [0, 255]. The vectors' x,y,z correspond to red, green, and blue.
    float4 fq11 = float4(colorModels[fq11i.x],
                         colorModels[fq11i.y],
                         colorModels[fq11i.z],
                         255);
    float4 fq12 = float4(colorModels[fq12i.x],
                         colorModels[fq12i.y],
                         colorModels[fq12i.z],
                         255);
    float4 fq21 = float4(colorModels[fq21i.x],
                         colorModels[fq21i.y],
                         colorModels[fq21i.z],
                         255);
    float4 fq22 = float4(colorModels[fq22i.x],
                         colorModels[fq22i.y],
                         colorModels[fq22i.z],
                         255);

    // Do bilinear interpolation on the r, g, and b values simultaneously.
    float4 f_x_y1 = (x2 - x) / (x2 - x1) * fq11 + (x - x1) / (x2 - x1) * fq21;
    float4 f_x_y2 = (x2 - x) / (x2 - x1) * fq12 + (x - x1) / (x2 - x1) * fq22;
    float4 f_x_y = (y2 - y) / (y2 - y1) * f_x_y1 + (y - y1) / (y2 - y1) * f_x_y2;

    float4 color = float4(f_x_y.x,
                          f_x_y.y,
                          f_x_y.z,
                          255) / 255.0;

#warning TODO: Only do this when transparency is present.
    // In the face of transparency, we need to blend non-black colors toward the text color and transparent
    float average = (bwColor.x + bwColor.y + bwColor.z) / 3;
    // If importance is 1, don't touch it. If importance is 0, make it transparent gray.
    float p = 2 * (1 - average);
    float importance = pow((1 - average), p);
    float unimportance = 1 - importance;

    float4 muted = color * importance + in.textColor * unimportance;
    float p2 = 0.5 + average;

    muted.w = 1 - pow(average, p2);

    return muted;
}

fragment float4
iTermTextFragmentShaderWithBlending(iTermTextVertexFunctionOutput in [[stage_in]],
                                    texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]],
                                    texture2d<half> drawable [[ texture(iTermTextureIndexBackground) ]],
                                    constant unsigned char *colorModels [[ buffer(iTermFragmentBufferIndexColorModels) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    const half4 bwColor = texture.sample(textureSampler, in.textureCoordinate);

    if (!in.recolor) {
        return static_cast<float4>(bwColor);
    }
    if (bwColor.x == 1 && bwColor.y == 1 && bwColor.z == 1) {
        discard_fragment();
    }

    // For a discussion of this code, see this document:
    // https://docs.google.com/document/d/1vfBq6vg409Zky-IQ7ne-Yy7olPtVCl0dq3PG20E8KDs

    // The formulas for bilinear interpolation came from:
    // https://en.wikipedia.org/wiki/Bilinear_interpolation
    //
    // The goal is to estimate the color of a pixel at P. We have to find the correct remapping
    // table for this cell's foreground/background color. The x axis is the text color and the
    // y axis is the background color.
    //
    // We'll find the four remapping tables that are closest to representing the text/background
    // color at this cell. We'll look up the black-and-white glyph's  color for this pixel in those
    // in those four remapping tables. Then we'll use bilinear interpolation to come up with an
    // estimate of what color to output.
    //
    // From a random sample of 1000 text/bg color combinations this gets within 2.3/255 of the
    // correct color in the worst case.
    //
    // TODO: Ask someone smart if there's a more efficient way to do this.
    //
    //    |   Q12             Q22
    // y2 |..*...............*...........
    //    |  :       :       :
    //    |  :       :P      :
    //  y |..........*...................
    //    |  :       :       :
    //    |  :       :       :
    //    |  :Q11    :       :Q21
    // y1 |..*...............*...........
    //    |  :       :       :
    //    |  :       :       :
    //    +---------------------------------
    //      x1       x       x2

    // Get text and background color in [0, 255]
    float4 x = in.textColor * 255.0;
    float4 y = static_cast<float4>(drawable.sample(textureSampler, in.backgroundTextureCoordinate)) * 255.0;

    // Indexes to lower and upper neighbors for x in [0, 17]
    int4 x1i = static_cast<int4>(floor(x / 15.0));
    int4 x2i = min(17, x1i + 1);
    // Make sure x1i != x2i
    x1i = max(0, x2i - 1);

    // Values of lower and upper neighbors for x in [0, 255]
    float4 x1 = static_cast<float4>(x1i) * 15.0;
    float4 x2 = static_cast<float4>(x2i) * 15.0;

    // Indexes to lower and upper neighbors for y in [0, 17]
    int4 y1i = static_cast<int4>(floor(y / 15.0));
    int4 y2i = min(17, y1i + 1);
    // Make sure y1i != y2i
    y1i = max(0, y2i - 1);

    // Values of lower and upper neighbors for y in [0, 255]
    float4 y1 = static_cast<float4>(y1i) * 15.0;
    float4 y2 = static_cast<float4>(y2i) * 15.0;

    // Index into tables (x,y,z ~ index for r,g,b)
    int4 i = static_cast<int4>(round(bwColor * 255));

    // indexes to use to look up f(Q_y_x)
    // 18 is the multiplier because the color models are quantized to the color in [0,255] / 17.0 and
    // there's an off-by-one thing going on here.
    int4 fq11i = 256 * (x1i * 18 + y1i) + i;
    int4 fq12i = 256 * (x1i * 18 + y2i) + i;
    int4 fq21i = 256 * (x2i * 18 + y1i) + i;
    int4 fq22i = 256 * (x2i * 18 + y2i) + i;

    // Four neighbors' values in [0, 255]. The vectors' x,y,z correspond to red, green, and blue.
    float4 fq11 = float4(colorModels[fq11i.x],
                         colorModels[fq11i.y],
                         colorModels[fq11i.z],
                         255);
    float4 fq12 = float4(colorModels[fq12i.x],
                         colorModels[fq12i.y],
                         colorModels[fq12i.z],
                         255);
    float4 fq21 = float4(colorModels[fq21i.x],
                         colorModels[fq21i.y],
                         colorModels[fq21i.z],
                         255);
    float4 fq22 = float4(colorModels[fq22i.x],
                         colorModels[fq22i.y],
                         colorModels[fq22i.z],
                         255);

    // Do bilinear interpolation on the r, g, and b values simultaneously.
    float4 f_x_y1 = (x2 - x) / (x2 - x1) * fq11 + (x - x1) / (x2 - x1) * fq21;
    float4 f_x_y2 = (x2 - x) / (x2 - x1) * fq12 + (x - x1) / (x2 - x1) * fq22;
    float4 f_x_y = (y2 - y) / (y2 - y1) * f_x_y1 + (y - y1) / (y2 - y1) * f_x_y2;

    return float4(f_x_y.x,
                  f_x_y.y,
                  f_x_y.z,
                  255) / 255.0;
}

