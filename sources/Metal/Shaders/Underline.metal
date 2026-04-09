//
//  Underline.metal
//  iTerm2
//
//  Standalone underline rendering shader for multi-pass underline rendering.
//  Draws underline/strikethrough patterns matching iTermTextShaderCommon.metal.
//

#include <metal_stdlib>
using namespace metal;
#import "iTermShaderTypes.h"

// Per-span info defined in iTermShaderTypes.h as iTermUnderlineSpanInfo.

struct UnderlineVertexOutput {
    float4 clipSpacePosition [[position]];
};

vertex UnderlineVertexOutput
iTermUnderlineVertexShader(uint vertexID [[ vertex_id ]],
                           constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                           constant vector_uint2 *viewportSizePointer [[ buffer(iTermVertexInputIndexViewportSize) ]]) {
    UnderlineVertexOutput out;
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    return out;
}

// Compute vertical coverage of a pixel at the given window-space position.
// Uses the same coordinate system as FractionOfPixelThatIntersectsUnderline in iTermTextShaderCommon.metal.
// windowY: the [[position]].y fragment coordinate (window space, after viewport transform)
// cellBottomY: cell's y offset matching cellOffset.y in the text shader
static float VerticalCoverage(float windowY,
                              float viewportHeight,
                              float cellBottomY,
                              float lineOffset,
                              float lineThickness) {
    // Same formula as FractionOfPixelThatIntersectsUnderline (iTermTextShaderCommon.metal:107-108)
    float originOnScreenInPixelSpace = viewportHeight - (windowY - 0.5);
    float originOfCellInPixelSpace = originOnScreenInPixelSpace - cellBottomY;

    float lowerBound = max(originOfCellInPixelSpace, lineOffset);
    float upperBound = min(originOfCellInPixelSpace + 1.0, lineOffset + lineThickness);
    return max(0.0, upperBound - lowerBound);
}

fragment float4
iTermUnderlineFragmentShader(UnderlineVertexOutput in [[stage_in]],
                             constant iTermUnderlineSpanInfo &spanInfo [[ buffer(0) ]],
                             constant vector_uint2 *viewportSizePointer [[ buffer(1) ]],
                             constant float *cellBottomYPtr [[ buffer(2) ]]) {
    const float viewportHeight = float((*viewportSizePointer).y);
    const float cellBottomY = *cellBottomYPtr;
    const float scale = spanInfo.scale;
    const int style = spanInfo.style;

    // Per-style thickness overrides matching ComputeWeightOfUnderlineRegular
    // in iTermTextShaderCommon.metal (lines 332-346).
    // Offset overrides are computed in UnderlineRenderer.swift and passed via spanInfo.lineOffset.
    float lineOffset = spanInfo.lineOffset;
    float lineThickness;
    switch (style) {
        case iTermMetalGlyphAttributesUnderlineCurly:
            lineThickness = scale;
            break;
        default:
            lineThickness = spanInfo.lineThickness;
            break;
    }

    // Adjust offset for styles that draw two lines (same as FractionOfPixelThatIntersectsUnderlineForStyle).
    if (style == iTermMetalGlyphAttributesUnderlineHyperlink ||
        style == iTermMetalGlyphAttributesUnderlineDouble) {
        lineOffset = max(0.0f, lineOffset - lineThickness);
    } else if (style == iTermMetalGlyphAttributesUnderlineCurly) {
        lineOffset = max(0.0f, lineOffset - lineThickness / 2.0f);
    }

    float weight = VerticalCoverage(in.clipSpacePosition.y, viewportHeight, cellBottomY, lineOffset, lineThickness);

    // Apply style-specific horizontal patterns.
    // These match the patterns in FractionOfPixelThatIntersectsUnderlineForStyle exactly.
    switch (style) {
        case iTermMetalGlyphAttributesUnderlineNone:
            return float4(0);

        case iTermMetalGlyphAttributesUnderlineStrikethrough:
        case iTermMetalGlyphAttributesUnderlineSingle:
            break;  // solid line, use weight as-is

        case iTermMetalGlyphAttributesUnderlineHyperlink:
            // Dashed bottom line + solid top line
            if (weight > 0 && fmod(in.clipSpacePosition.x, 7.0f * scale) >= 4.0f * scale) {
                weight = 0;  // hole in dashed bottom
            } else if (weight == 0) {
                // Try top line
                weight = VerticalCoverage(in.clipSpacePosition.y, viewportHeight, cellBottomY,
                                          lineOffset + lineThickness * 2.0f, lineThickness);
            }
            break;

        case iTermMetalGlyphAttributesUnderlineDouble:
            if (weight == 0) {
                // Try top line
                weight = VerticalCoverage(in.clipSpacePosition.y, viewportHeight, cellBottomY,
                                          lineOffset + lineThickness * 2.0f, lineThickness);
            }
            break;

        case iTermMetalGlyphAttributesUnderlineCurly: {
            const float wavelength = 6.0f;
            bool inSecondHalf = fmod(in.clipSpacePosition.x, wavelength * scale) >= (wavelength / 2.0f) * scale;
            if (weight > 0 && inSecondHalf) {
                weight = 0;  // hole in bottom line
            } else if (weight == 0 && !inSecondHalf) {
                weight = 0;  // hole in top line
            } else if (weight == 0) {
                // Top line visible
                weight = VerticalCoverage(in.clipSpacePosition.y, viewportHeight, cellBottomY,
                                          lineOffset + lineThickness, lineThickness);
            }
            break;
        }

        case iTermMetalGlyphAttributesUnderlineDashedSingle:
            if (weight > 0 && fmod(in.clipSpacePosition.x, 7.0f * scale) >= 4.0f * scale) {
                weight = 0;
            }
            break;

        case iTermMetalGlyphAttributesUnderlineDotted:
            if (weight > 0 && fmod(in.clipSpacePosition.x, 2.0f * scale) >= 1.0f * scale) {
                weight = 0;
            }
            break;

        case iTermMetalGlyphAttributesUnderlineDashed:
            if (weight > 0 && fmod(in.clipSpacePosition.x, 7.0f * scale) >= 4.0f * scale) {
                weight = 0;
            }
            break;

        default:
            break;
    }

    if (weight <= 0) {
        discard_fragment();
    }

    return float4(spanInfo.color.rgb * weight, spanInfo.color.a * weight);
}
