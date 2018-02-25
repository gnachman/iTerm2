//
//  iTermColorComputer.metal
//  iTerm2
//
//  Created by George Nachman on 2/24/18.
//

#include <metal_stdlib>
using namespace metal;

#import "iTermMetalScreenCharAccessors.h"
#import "iTermShaderTypes.h"
#import "iTermSharedColor.h"

kernel void
iTermColorKernelFunction(device unsigned char *colorMap [[ buffer(iTermVertexInputIndexColorMap) ]],
                         device screen_char_t *line_ALL [[ buffer(iTermComputeIndexScreenChars) ]],
                         device unsigned char *selectedIndices_ALL [[ buffer(iTermVertexInputSelectedIndices) ]],
                         device unsigned char *findMatchIndices_ALL [[ buffer(iTermVertexInputFindMatchIndices) ]],
                         device unsigned char *annotatedIndices_ALL [[ buffer(iTermVertexInputAnnotatedIndices) ]],
                         device unsigned char *markedIndices_ALL [[ buffer(iTermVertexInputMarkedIndices) ]],
                         device unsigned char *underlinedIndices_ALL [[ buffer(iTermVertexInputUnderlinedIndices) ]],
                         device iTermColorsConfiguration *config [[ buffer(iTermComputeIndexColorsConfig) ]],
                         device iTermMetalDebugBuffer *debugBuffer [[ buffer(iTermVertexInputDebugBuffer) ]],
                         device iTermCellColors *colorsOut [[ buffer(iTermComputeIndexColors) ]],  // OUTPUT
                         uint2 gid [[thread_position_in_grid]]) {
    // Bounds check
    const unsigned int width = config->gridSize.x;
    if (gid.x >= width ||
        gid.y >= config->gridSize.y) {
        return;
    }

    const int x = gid.x;
    const int i = x + (config->gridSize.x + 1) * gid.y;

    const int offset = gid.y * (width + 1);
    device screen_char_t *line = line_ALL + offset;

#if ENABLE_DEBUG_COLOR_COMPUTER
    colorsOut[i].coord = gid;
    colorsOut[i].index = i;
#endif

    colorsOut[i].nonascii = SCComplex(&line[x]) || SCCode(&line[x]) > 126 || SCCode(&line[x]) < ' ' || SCImage(&line[x]);

    // Get pointers to this line in the various bit fields.
    device unsigned char *selectedIndices = selectedIndices_ALL + offset;
    device unsigned char *findMatchIndices = findMatchIndices_ALL + offset;
    device unsigned char *annotatedIndices = annotatedIndices_ALL + offset;
    device unsigned char *markedIndices = markedIndices_ALL + offset;
    device unsigned char *underlinedIndices = underlinedIndices_ALL + offset;

    const int mask = 1 << (i & 7);
    const bool selected = !!(selectedIndices[i / 8] & mask);
    const bool findMatch = !!(findMatchIndices[i / 8] & mask);
    const bool annotated = !!(annotatedIndices[i / 8] & mask);
    const bool marked = !!(markedIndices[i / 8] & mask);
    const bool inUnderlinedRange = !!(underlinedIndices[i / 8] & mask);

    const vector_float4 backgroundColor = BackgroundColor(&line[x],
                                                          config->transparencyAlpha,
                                                          config->transparencyAffectsOnlyDefaultBackgroundColor,
                                                          config->reverseVideo,
                                                          config->useBrightBold,
                                                          config->isFrontTextView,
                                                          config->mutingAmount,
                                                          config->dimOnlyText,
                                                          config->dimmingAmount,
                                                          config->hasBackgroundImage,
                                                          config->unfocusedSelectionColor,
                                                          colorMap,
                                                          selected,
                                                          findMatch);
    const vector_float4 textColor = TextColor(&line[x],
                                              config->minimumContrast,
                                              config->dimmingAmount,
                                              config->mutingAmount,
                                              config->dimOnlyText,
                                              config->reverseVideo,
                                              config->useBrightBold,
                                              colorMap,
                                              backgroundColor,
                                              selected,
                                              findMatch,
                                              inUnderlinedRange && !annotated);
    const iTermMetalGlyphAttributesUnderline underlineStyle = UnderlineStyle(&line[x], annotated, inUnderlinedRange);
    const bool useThinStrokes = UseThinStrokes(config->thinStrokesSetting,
                                               config->scale > 1,
                                               backgroundColor,
                                               textColor);

    // Assign values to output.
    if (underlineStyle != iTermMetalGlyphAttributesUnderlineNone) {
        colorsOut[i].underlineColor = UnderlineColor(config->asciiUnderlineColor,
                                                     textColor,
                                                     annotated,
                                                     marked);
    }
    colorsOut[i].backgroundColor = backgroundColor;
    colorsOut[i].textColor = textColor;
    colorsOut[i].underlineStyle = underlineStyle;
    colorsOut[i].useThinStrokes = useThinStrokes;
}



/*
kernel void
HelloWorld(device screen_char_t *line [[ buffer(iTermComputeIndexScreenChars) ]],
           device iTermCellColors *colorsOut [[ buffer(iTermComputeIndexColors) ]],
           constant iTermColorsConfig *config [[ buffer(iTermComputeIndexColorsConfig) ]],
           uint2 gid [[thread_position_in_grid]]) {
    // Bounds check
    if (gid.x >= config->gridSize.x ||
        gid.y >= config->gridSize.y) {
        return;
    }

    const int outputIndex = gid.x * gid.y;
    colorsOut[outputIndex].textColor = float4(0, 0.5, 0.75, 1);
    colorsOut[outputIndex].backgroundColor = float4(gid.x, gid.y, 0, 1);
}


*/
