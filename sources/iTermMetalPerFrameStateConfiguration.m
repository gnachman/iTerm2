//
//  iTermMetalPerFrameStateConfiguration.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/19/18.
//

#import "iTermMetalPerFrameStateConfiguration.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "PTYTextView.h"
#import "VT100Terminal.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermColorMap.h"
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
    _fontTable = textView.fontTable;
    _useBoldFont = textView.useBoldFont;
    _useItalicFont = textView.useItalicFont;
    _useNonAsciiFont = textView.useNonAsciiFont;
    _reverseVideo = textView.dataSource.terminalReverseVideo;
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
    _useSelectedTextColor = drawingHelper.useSelectedTextColor;
    _showBroadcastStripes = drawingHelper.showStripes;
    NSColorSpace *colorSpace = textView.window.screen.colorSpace ?: [NSColorSpace it_defaultColorSpace];
    _processedDefaultBackgroundColor = [[drawingHelper defaultBackgroundColor] colorUsingColorSpace:colorSpace];
    _processedDeselectedDefaultBackgroundColor = [[drawingHelper deselectedDefaultBackgroundColor] colorUsingColorSpace:colorSpace];
    _forceRegularBottomMargin = drawingHelper.forceRegularBottomMargin;
    _processedDefaultTextColor = [[drawingHelper defaultTextColor] colorUsingColorSpace:colorSpace];
    NSColor *selectionColor = [[_colorMap colorForKey:kColorMapSelection] colorUsingColorSpace:colorSpace];
    _selectionColor = simd_make_float4((float)selectionColor.redComponent,
                                       (float)selectionColor.greenComponent,
                                       (float)selectionColor.blueComponent,
                                       1.0);
    NSArray<NSColor *> *scoc = drawingHelper.selectedCommandOutlineColors;
    _selectedCommandOutlineColors[0] = scoc[0].vector;
    _selectedCommandOutlineColors[1] = scoc[1].vector;

    _lineStyleMarkColors = (iTermLineStyleMarkColors) {
        .success = [[[drawingHelper defaultBackgroundColor] blendedWithColor:[iTermTextDrawingHelper successMarkColor] weight:0.5] colorUsingColorSpace:colorSpace].vector,
        .other = [[[drawingHelper defaultBackgroundColor] blendedWithColor:[iTermTextDrawingHelper otherMarkColor] weight:0.5] colorUsingColorSpace:colorSpace].vector,
        .failure = [[[drawingHelper defaultBackgroundColor] blendedWithColor:[iTermTextDrawingHelper errorMarkColor] weight:0.5] colorUsingColorSpace:colorSpace].vector
    };

    _isFrontTextView = (textView == [[iTermController sharedInstance] frontTextView]);
    _unfocusedSelectionColor = VectorForColor([[_colorMap colorForKey:kColorMapSelection] colorDimmedBy:2.0/3.0
                                                                                       towardsGrayLevel:0.5]);
    _transparencyAlpha = textView.transparencyAlpha;
    _transparencyAffectsOnlyDefaultBackgroundColor = drawingHelper.transparencyAffectsOnlyDefaultBackgroundColor;

    // Cursor guide
    _cursorGuideEnabled = drawingHelper.highlightCursorLine;
    _cursorGuideColor = drawingHelper.cursorGuideColor;
    _colorSpace = textView.window.screen.colorSpace ?: [NSColorSpace it_defaultColorSpace];

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
    _asciiUnderlineDescriptor.offset = [drawingHelper yOriginForUnderlineForFont:_fontTable.asciiFont.font
                                                                         yOffset:0
                                                                      cellHeight:_cellSize.height];
    _asciiUnderlineDescriptor.thickness = [drawingHelper underlineThicknessForFont:_fontTable.asciiFont.font];

    if (_useNonAsciiFont) {
        _nonAsciiUnderlineDescriptor.color = _asciiUnderlineDescriptor.color;
        _nonAsciiUnderlineDescriptor.offset = [drawingHelper yOriginForUnderlineForFont:_fontTable.defaultNonASCIIFont.font
                                                                                yOffset:0
                                                                             cellHeight:_cellSize.height];
        _nonAsciiUnderlineDescriptor.thickness = [drawingHelper underlineThicknessForFont:_fontTable.defaultNonASCIIFont.font];
    } else {
        _nonAsciiUnderlineDescriptor = _asciiUnderlineDescriptor;
    }
    // We use the ASCII font's color and underline thickness for strikethrough.
    _strikethroughUnderlineDescriptor.color = _asciiUnderlineDescriptor.color;
    _strikethroughUnderlineDescriptor.offset = [drawingHelper yOriginForStrikethroughForFont:_fontTable.asciiFont.font
                                                                                     yOffset:0
                                                                                  cellHeight:_cellSize.height];
    _strikethroughUnderlineDescriptor.thickness = [drawingHelper strikethroughThicknessForFont:_fontTable.asciiFont.font];

    if (@available(macOS 11, *)) {
        _terminalButtons = [textView.terminalButtons mapWithBlock:^id _Nullable(iTermTerminalButton * _Nonnull button) {
            return [button clone];
        }];
    }

    // Indicators
    NSColor *color = [[textView indicatorFullScreenFlashColor] colorUsingColorSpace:_colorSpace];
    _fullScreenFlashColor = simd_make_float4(color.redComponent,
                                             color.greenComponent,
                                             color.blueComponent,
                                             textView.indicatorsHelper.fullScreenAlpha);

    // Timestamps
    _timestampsEnabled = drawingHelper.shouldShowTimestamps;
    _timestampFont = _fontTable.asciiFont.font;

    // Offscreen command line
    if (drawingHelper.offscreenCommandLine) {
        _offscreenCommandLineBackgroundColor = [textView.drawingHelper.offscreenCommandLineBackgroundColor colorUsingColorSpace:_colorSpace];
        _offscreenCommandLineOutlineColor = [textView.drawingHelper.offscreenCommandLineOutlineColor colorUsingColorSpace:_colorSpace];
        _offscreenCommandLineBackgroundColor = [textView.drawingHelper.offscreenCommandLineBackgroundColor colorUsingColorSpace:_colorSpace];
    }

    _selectedCommandRegion = drawingHelper.selectedCommandRegion;
    _selectedCommandRegion.location += drawingHelper.totalScrollbackOverflow;
    _totalScrollbackOverflow = drawingHelper.totalScrollbackOverflow;
}

@end
