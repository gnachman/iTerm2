#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"

// Issue 12791: Bit ORed into the shared report buffer when the GPU-side geometry witness
// fails for any reason. The CPU side (iTermBackgroundColorRenderer.mm) distinguishes the
// cause (transient vs persistent, non-finite vs zero-area) from its own re-check.
constant uint iTermBgColorReportWitnessFailed = 0x1u;

typedef struct {
    float4 clipSpacePosition [[position]];
    float4 color;
    bool cancel;
    float isValid;  // Issue 12791: 1.0 = geometry witness passed, 0.0 = mismatch/non-finite
} iTermBackgroundColorVertexFunctionOutput;

// Issue 12791: FNV-1a-32 over the vertex array, hashed float-by-float to avoid struct
// padding. Witnesses the geometry buffer - the only per-vertex-varying input. Must match
// the CPU-side implementation in iTermBackgroundColorRenderer.mm.
static inline uint iTermBgColorGeometryHash(constant iTermVertex *vertices, uint count) {
    uint hash = 2166136261u;
    for (uint i = 0; i < count; i++) {
        uint words[4] = {
            as_type<uint>(vertices[i].position.x),
            as_type<uint>(vertices[i].position.y),
            as_type<uint>(vertices[i].textureCoordinate.x),
            as_type<uint>(vertices[i].textureCoordinate.y)
        };
        for (uint j = 0; j < 4; j++) {
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

    // Issue 12791: Independent geometry witness. The expected hash arrives via
    // setVertexBytes (inline command-buffer payload, not an MTLBuffer), so a stomp on the
    // pooled unit-quad buffer between CPU write and GPU read produces a mismatch. The hash
    // is over the whole vertex array, so every vertex agrees on the verdict. expected==0 is
    // a "don't check" sentinel (used for the freshly-built suppressed region).
    out.isValid = 1.0;
    if (bgChecksum->expected != 0u && !out.cancel) {
        const uint computed = iTermBgColorGeometryHash(vertexArray, bgChecksum->vertexCount);
        const bool nonFinite = !isfinite(pixelSpacePosition.x) || !isfinite(pixelSpacePosition.y);
        if (computed != bgChecksum->expected || nonFinite) {
            out.isValid = 0.0;
            // Rescue the vertex to a full-screen triangle so the fragment shader always runs
            // and can witness the failure. This matters most for the exact symptom we chase:
            // a corrupted (e.g. non-finite) vertex would otherwise collapse the triangle so no
            // fragment ever runs, and a fragment-side witness would never see it. Every failing
            // vertex maps to the same big triangle, so the whole quad flashes red for one frame.
            const uint corner = vertexID % 3u;
            out.clipSpacePosition = float4(corner == 1u ? 3.0 : -1.0,
                                           corner == 2u ? 3.0 : -1.0,
                                           0.0, 1.0);
        }
    }
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
    // Issue 12791: Geometry witness failed for a triangle that still rasterized. Signal the
    // CPU side (read in -[iTermBackgroundColorRendererTransientState didComplete]) and paint
    // red for a visible witness. Checked after cancel so discarded fragments never report.
    if (in.isValid < 0.5) {
        atomic_fetch_or_explicit(checksumReport, iTermBgColorReportWitnessFailed, memory_order_relaxed);
        return float4(1.0, 0.0, 0.0, 1.0);
    }
    return in.color;
}
