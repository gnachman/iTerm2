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
#import "iTermAdvancedSettingsModel.h"
#import "iTermAttributedStringBuilder.h"
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
    // Zero so the struct's padding is defined for byte-wise fingerprinting.
    memset(&_renderInputs, 0, sizeof(_renderInputs));

    _cellSize = drawingHelper.cellSize;
    _cellSizeWithoutSpacing = drawingHelper.cellSizeWithoutSpacing;
    _scale = textView.window.backingScaleFactor;

    _gridSize = VT100GridSizeMake(textView.dataSource.width,
                                  textView.dataSource.height);
    _baselineOffset = drawingHelper.baselineOffset;
    _colorMap = [textView.colorMap copy];
    _renderInputs.colorMapGeneration = _colorMap.generation;
    _fontTable = textView.fontTable;
    _useBoldFont = textView.useBoldFont;
    _useItalicFont = textView.useItalicFont;
    _renderInputs.useNonAsciiFont = textView.useNonAsciiFont;
    _renderInputs.reverseVideo = textView.dataSource.terminalReverseVideo;
    _softAlternateScreenMode = drawingHelper.softAlternateScreenMode;
    _renderInputs.useCustomBoldColor = textView.useCustomBoldColor;
    _renderInputs.brightenBold = textView.brightenBold;
    _renderInputs.thinStrokes = textView.thinStrokes;
    _renderInputs.isRetina = drawingHelper.isRetina;
    _isInKeyWindow = [textView isInKeyWindow];
    _textViewIsActiveSession = [textView.delegate textViewIsActiveSession];
    _textViewIsFirstResponder = drawingHelper.textViewIsFirstResponder;
    _shouldDrawFilledInCursor = ([textView.delegate textViewShouldDrawFilledInCursor] || textView.focusFollowsMouse.haveStolenFocus);
    _renderInputs.blinkAllowed = textView.blinkAllowed;
    _blinkingItemsVisible = drawingHelper.blinkingItemsVisible;
    const BOOL forceAA = (drawingHelper.forceAntialiasingOnRetina && drawingHelper.isRetina);
    _asciiAntialias = drawingHelper.asciiAntiAlias || forceAA;
    _nonasciiAntialias = (_renderInputs.useNonAsciiFont ? drawingHelper.nonAsciiAntiAlias : _asciiAntialias)  || forceAA;
    _renderInputs.useNativePowerlineGlyphs = drawingHelper.useNativePowerlineGlyphs;
    _renderInputs.useSelectedTextColor = drawingHelper.useSelectedTextColor;
    _renderInputs.ligaturesEnabled = drawingHelper.asciiLigatures || drawingHelper.nonAsciiLigatures;
    _renderInputs.underlineHyperlinks = [iTermAdvancedSettingsModel underlineHyperlinks];

    // Shaping settings that change the glyph-keys blob. Read from the same
    // attributed-string builder the metal glue snapshots via copySettingsFrom:,
    // so the fingerprint matches exactly what the row build uses.
    iTermAttributedStringBuilder *asb = drawingHelper.attributedStringBuilder;
    _renderInputs.asciiLigatures = asb.asciiLigatures;
    _renderInputs.asciiLigaturesAvailable = asb.asciiLigaturesAvailable;
    _renderInputs.nonAsciiLigatures = asb.nonAsciiLigatures;
    _renderInputs.zippy = asb.zippy;
    _renderInputs.preferSpeedToFullLigatureSupport = asb.preferSpeedToFullLigatureSupport;
    _renderInputs.lowFiCombiningMarks = asb.lowFiCombiningMarks;
    _renderInputs.boldAllowed = asb.boldAllowed;
    _renderInputs.italicAllowed = asb.italicAllowed;
    _showBroadcastStripes = drawingHelper.showStripes;
    NSColorSpace *colorSpace = textView.window.screen.colorSpace ?: [NSColorSpace it_defaultColorSpace];
    _processedDefaultBackgroundColor = [[drawingHelper defaultBackgroundColor] colorUsingColorSpace:colorSpace];
    NSColor *colorForMargins = textView.colorForMargins;
    _marginColorEnabled = colorForMargins != nil;
    _processedMarginColor = [colorForMargins colorUsingColorSpace:colorSpace].vector;
    _forceRegularBottomMargin = drawingHelper.forceRegularBottomMargin;
    _processedDefaultTextColor = [[drawingHelper defaultTextColor] colorUsingColorSpace:colorSpace];
    _blockHoverColor = [[drawingHelper blockHoverColor] colorUsingColorSpace:colorSpace];
    _defaultTextColor = [[_colorMap colorForKey:kColorMapForeground] colorUsingColorSpace:colorSpace];
    NSColor *selectionColor = [[_colorMap colorForKey:kColorMapSelection] colorUsingColorSpace:colorSpace];
    _selectionColor = simd_make_float4((float)selectionColor.redComponent,
                                       (float)selectionColor.greenComponent,
                                       (float)selectionColor.blueComponent,
                                       1.0);
    NSArray<NSColor *> *scoc = drawingHelper.selectedCommandOutlineColors;
    _selectedCommandOutlineColors[0] = scoc[0].vector;
    _selectedCommandOutlineColors[1] = scoc[1].vector;
    _shadeColor = drawingHelper.shadeColor.vector;
    _shadeColor.xyz *= _shadeColor.w;
    const CGFloat vmargin = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    _buttonsBackgroundRects = [drawingHelper.buttonsBackgroundRects shiftedBy:NSMakePoint(0, -textView.visibleRect.origin.y - vmargin)];

    if (@available(macOS 11, *)) {
        // Pass raw pill infos - the renderer will calculate Y from absLine and margins
        _buttonPillInfos = [drawingHelper buttonPillInfos];
    }

    _lineStyleMarkColors = (iTermLineStyleMarkColors) {
        .success = [[[drawingHelper defaultBackgroundColor] blendedWithColor:[iTermTextDrawingHelper successMarkColor] weight:0.5] colorUsingColorSpace:colorSpace].vector,
        .other = [[[drawingHelper defaultBackgroundColor] blendedWithColor:[iTermTextDrawingHelper otherMarkColor] weight:0.5] colorUsingColorSpace:colorSpace].vector,
        .failure = [[[drawingHelper defaultBackgroundColor] blendedWithColor:[iTermTextDrawingHelper errorMarkColor] weight:0.5] colorUsingColorSpace:colorSpace].vector
    };

    _renderInputs.isFrontTextView = (textView == [[iTermController sharedInstance] frontTextView]);
    _renderInputs.unfocusedSelectionColor = VectorForColor([[_colorMap colorForKey:kColorMapSelection] colorDimmedBy:2.0/3.0
                                                                                       towardsGrayLevel:0.5]);
    _renderInputs.transparencyAlpha = textView.transparencyAlpha;
    _renderInputs.transparencyAffectsOnlyDefaultBackgroundColor = drawingHelper.transparencyAffectsOnlyDefaultBackgroundColor;

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

    if (_renderInputs.useNonAsciiFont) {
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
    _timestampFontInfo = [_fontTable.asciiFont copy];
    _timestampBaseline = textView.timestampBaseline;

    // Offscreen command line
    if (drawingHelper.offscreenCommandLine) {
        _offscreenCommandLineBackgroundColor = [textView.drawingHelper.offscreenCommandLineBackgroundColor colorUsingColorSpace:_colorSpace];
        _offscreenCommandLineOutlineColor = [textView.drawingHelper.offscreenCommandLineOutlineColor colorUsingColorSpace:_colorSpace];
    }

    _selectedCommandRegion = drawingHelper.selectedCommandRegion;
    _selectedCommandRegion.location += drawingHelper.totalScrollbackOverflow;
    _totalScrollbackOverflow = drawingHelper.totalScrollbackOverflow;

    // All row-build inputs are populated. Derive a per-textview config
    // generation by exact comparison against the previous frame (collision-free,
    // unlike a hash). The color space and font table are compared as objects
    // since they can't be flattened exactly into the struct.
    // Pass the SOURCE color map (textView.colorMap), not _colorMap: the latter is
    // a fresh copy made every frame (line above), so its identity would differ
    // each frame and bump the generation unconditionally, defeating the cache. The
    // source object is stable across frames and only changes on an actual map swap
    // (profile/theme change), which is exactly what the identity check must catch;
    // in-place palette edits are still caught by _renderInputs.colorMapGeneration.
    _configGeneration = [glue metalConfigGenerationForRenderInputs:&_renderInputs
                                                          colorMap:textView.colorMap
                                                        colorSpace:_colorSpace
                                                         fontTable:_fontTable];
}

@end
