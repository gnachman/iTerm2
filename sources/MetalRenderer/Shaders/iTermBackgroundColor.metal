#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float4 color;
    bool cancel;
    float isValid;  // Issue 12604/12791: 1.0 = PIU checksum matched, 0.0 = mismatch (uniform across draw)
} iTermBackgroundColorVertexFunctionOutput;

// Issue 12604/12791: FNV-1a-32 over the PIU array, hashed field-by-field to avoid
// struct padding. Must match the CPU-side implementation in iTermBackgroundColorRenderer.mm.
static inline uint iTermBgColorPiuHash(constant iTermBackgroundColorPIU *pius, uint count) {
    uint hash = 2166136261u;
    for (uint i = 0; i < count; i++) {
        uint words[9] = {
            as_type<uint>(pius[i].offset.x),
            as_type<uint>(pius[i].offset.y),
            (uint)pius[i].runLength,
            (uint)pius[i].numRows,
            as_type<uint>(pius[i].color.x),
            as_type<uint>(pius[i].color.y),
            as_type<uint>(pius[i].color.z),
            as_type<uint>(pius[i].color.w),
            (uint)pius[i].isDefault
        };
        for (uint j = 0; j < 9; j++) {
            hash ^= words[j];
            hash *= 16777619u;
        }
    }
    // Match CPU-side: reserve 0 as a "skip check" sentinel.
    return hash == 0u ? 1u : hash;
}

// Matches function in iTermOffscreenCommandLineBackgroundRenderer.m
static float4 iTermBlendColors(float4 src, float4 dst) {
    float4 out;
    out.w = src.w + dst.w * (1 - src.w);
    if (out.w > 0) {
        out.xyz = (src.xyz * src.w + dst.xyz * dst.w * (1 - src.w)) / out.w;
    } else {
        out.xyz = 0;
    }
    return out;
}

static float4 iTermPremultiply(float4 color) {
    float4 result = color;
    result.xyz *= color.w;
    return result;
}

vertex iTermBackgroundColorVertexFunctionOutput
iTermBackgroundColorVertexShader(uint vertexID [[ vertex_id ]],
                                 constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                                 constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                                 constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                                 constant iTermBackgroundColorPIU *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                                 constant iTermMetalBackgroundColorInfo *info [[ buffer(iTermVertexInputIndexDefaultBackgroundColorInfo) ]],
                                 constant iTermBgColorChecksumParams *bgChecksum [[ buffer(iTermVertexInputIndexBgColorChecksum) ]],
                                 unsigned int iid [[instance_id]]) {
    iTermBackgroundColorVertexFunctionOutput out;

    // Issue 12604/12791: Independent checksum witness. The expected hash arrives via
    // setVertexBytes (inline command-buffer payload, not an MTLBuffer), so a stomp on
    // the pooled PIU buffer between CPU write and GPU read produces a mismatch.
    // expected==0 is a sentinel meaning "don't check this draw".
    out.isValid = 1.0;
    if (bgChecksum->expected != 0u) {
        const uint computed = iTermBgColorPiuHash(perInstanceUniforms, bgChecksum->count);
        out.isValid = (computed == bgChecksum->expected) ? 1.0 : 0.0;
    }

    switch (info->mode) {
        case iTermBackgroundColorRendererModeAll:
            out.cancel = false;
            break;
        case iTermBackgroundColorRendererModeDefaultOnly:
            out.cancel = !perInstanceUniforms[iid].isDefault;
            break;
        case iTermBackgroundColorRendererModeNondefaultOnly:
            out.cancel = perInstanceUniforms[iid].isDefault;
            break;

    }

    // Stretch it horizontally and vertically. Vertex coordinates are 0 or the width/height of
    // a cell, so this works.
    const float runLength = perInstanceUniforms[iid].runLength;
    const float numRows = perInstanceUniforms[iid].numRows;
    float2 pixelSpacePosition = (vertexArray[vertexID].position.xy * float2(runLength, numRows) +
                                 perInstanceUniforms[iid].offset.xy +
                                 offset[0]);
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    out.color = iTermPremultiply(iTermBlendColors(perInstanceUniforms[iid].color,
                                                  info->defaultBackgroundColor));
    return out;
}

// Trivial changes in this implementation trigger metal compiler bugs (like putting `return in.color` in an else clause).
fragment float4
iTermBackgroundColorFragmentShader(iTermBackgroundColorVertexFunctionOutput in [[stage_in]],
                                   device atomic_uint *checksumReport [[ buffer(iTermFragmentBufferIndexBgColorChecksumReport) ]]) {
    if (in.cancel) {
        discard_fragment();
        return float4(0, 0, 0, 0);
    }
    // Issue 12604/12791: PIU checksum mismatch. Atomically signal the CPU side (read in
    // -[iTermBackgroundColorRendererTransientState didComplete]) and paint red for a
    // visible witness. Checked after cancel so discarded fragments never report or paint.
    if (in.isValid < 0.5) {
        atomic_fetch_or_explicit(checksumReport, 1u, memory_order_relaxed);
        return float4(1.0, 0.0, 0.0, 1.0);
    }
    return in.color;
}
