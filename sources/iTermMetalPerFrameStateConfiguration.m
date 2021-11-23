//
//  iTermMetalPerFrameStateConfiguration.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/19/18.
//

#import "iTermMetalPerFrameStateConfiguration.h"
#import "NSColor+iTerm.h"
#import "PTYTextView.h"
#import "VT100Terminal.h"
#import "iTermController.h"
#import "iTermMetalPerFrameState.h"
#import "iTermTextDrawingHelper.h"

static vector_float4 VectorForColor(NSColor *color) {
    return (vector_float4) { color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent };
}

@implementation iTermMetalPerFrameStateConfiguration

- (void)loadSettingsWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper
                             textView:(PTYTextView *)textView
                                 glue:(id<iTermMetalPerFrameStateDelegate>)glue {
    _cellSize = drawingHelper.cellSize;
    _cellSizeWithoutSpacing = drawingHelper.cellSizeWithoutSpacing;
    _scale = textView.window.backingScaleFactor;

    _gridSize = VT100GridSizeMake(textView.dataSource.width,
                                  textView.dataSource.height);
    _baselineOffset = drawingHelper.baselineOffset;
    _colorMap = [textView.colorMap copy];
    _asciiFont = textView.primaryFont;
    _nonAsciiFont = textView.secondaryFont;
    _useBoldFont = textView.useBoldFont;
    _useItalicFont = textView.useItalicFont;
    _useNonAsciiFont = textView.useNonAsciiFont;
    _reverseVideo = textView.dataSource.terminal.reverseVideo;
    _useCustomBoldColor = textView.useCustomBoldColor;
    _brightenBold = textView.brightenBold;
    _thinStrokes = textView.thinStrokes;
    _isRetina = drawingHelper.isRetina;
    _isInKeyWindow = [textView isInKeyWindow];
    _textViewIsActiveSession = [textView.delegate textViewIsActiveSession];
    _shouldDrawFilledInCursor = ([textView.delegate textViewShouldDrawFilledInCursor] || textView.keyFocusStolenCount);
    _blinkAllowed = textView.blinkAllowed;
    _blinkingItemsVisible = drawingHelper.blinkingItemsVisible;
    const BOOL forceAA = (drawingHelper.forceAntialiasingOnRetina && drawingHelper.isRetina);
    _asciiAntialias = drawingHelper.asciiAntiAlias || forceAA;
    _nonasciiAntialias = (_useNonAsciiFont ? drawingHelper.nonAsciiAntiAlias : _asciiAntialias)  || forceAA;
    _useNativePowerlineGlyphs = drawingHelper.useNativePowerlineGlyphs;
    _showBroadcastStripes = drawingHelper.showStripes;
    _processedDefaultBackgroundColor = [[drawingHelper defaultBackgroundColor] colorUsingColorSpace:textView.window.screen.colorSpace ?: [NSColorSpace sRGBColorSpace]];
    _isFrontTextView = (textView == [[iTermController sharedInstance] frontTextView]);
    _unfocusedSelectionColor = VectorForColor([[_colorMap colorForKey:kColorMapSelection] colorDimmedBy:2.0/3.0
                                                                                       towardsGrayLevel:0.5]);
    _transparencyAlpha = textView.transparencyAlpha;
    _transparencyAffectsOnlyDefaultBackgroundColor = drawingHelper.transparencyAffectsOnlyDefaultBackgroundColor;

    // Cursor guide
    _cursorGuideEnabled = drawingHelper.highlightCursorLine;
    _cursorGuideColor = drawingHelper.cursorGuideColor;
    _colorSpace = textView.window.screen.colorSpace ?: [NSColorSpace sRGBColorSpace];

    // Background image
    _backgroundImageBlend = [glue backgroundImageBlend];
    _backgroundImageMode = [glue backroundImageMode];
    
    _edgeInsets = textView.delegate.textViewEdgeInsets;
    _edgeInsets.left++;
    _edgeInsets.right++;
    _edgeInsets.top *= _scale;
    _edgeInsets.bottom *= _scale;
    _edgeInsets.left *= _scale;
    _edgeInsets.right *= _scale;

    _asciiUnderlineDescriptor.color = VectorForColor([_colorMap colorForKey:kColorMapUnderline]);
    _asciiUnderlineDescriptor.offset = [drawingHelper yOriginForUnderlineForFont:_asciiFont.font
                                                                         yOffset:0
                                                                      cellHeight:_cellSize.height];
    _asciiUnderlineDescriptor.thickness = [drawingHelper underlineThicknessForFont:_asciiFont.font];

    if (_useNonAsciiFont) {
        _nonAsciiUnderlineDescriptor.color = _asciiUnderlineDescriptor.color;
        _nonAsciiUnderlineDescriptor.offset = [drawingHelper yOriginForUnderlineForFont:_nonAsciiFont.font
                                                                                yOffset:0
                                                                             cellHeight:_cellSize.height];
        _nonAsciiUnderlineDescriptor.thickness = [drawingHelper underlineThicknessForFont:_nonAsciiFont.font];
    } else {
        _nonAsciiUnderlineDescriptor = _asciiUnderlineDescriptor;
    }
    // We use the ASCII font's color and underline thickness for strikethrough.
    _strikethroughUnderlineDescriptor.color = _asciiUnderlineDescriptor.color;
    _strikethroughUnderlineDescriptor.offset = [drawingHelper yOriginForStrikethroughForFont:_asciiFont.font
                                                                                     yOffset:0
                                                                                  cellHeight:_cellSize.height];
    _strikethroughUnderlineDescriptor.thickness = [drawingHelper strikethroughThicknessForFont:_asciiFont.font];

    // Indicators
    NSColor *color = [[textView indicatorFullScreenFlashColor] colorUsingColorSpace:_colorSpace];
    _fullScreenFlashColor = simd_make_float4(color.redComponent,
                                             color.greenComponent,
                                             color.blueComponent,
                                             textView.indicatorsHelper.fullScreenAlpha);

    // Timestamps
    _timestampsEnabled = drawingHelper.shouldShowTimestamps;
    _timestampFont = textView.font;
}

@end
