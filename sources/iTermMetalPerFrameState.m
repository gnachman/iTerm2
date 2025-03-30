//
//  iTermMetalPerFrameState.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/19/18.
//

#import "iTermMetalPerFrameState.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAlphaBlendingHelper.h"
#import "iTermAttributedStringBuilder.h"
#import "iTermAttributedStringProxy.h"
#import "iTermBoxDrawingBezierCurveFactory.h"
#import "iTermCharacterSource.h"
#import "iTermColorMap.h"
#import "iTermController.h"
#import "iTermCoreTextLineRenderingHelper.h"
#import "iTermData.h"
#import "iTermImageInfo.h"
#import "iTermLRUDictionary.h"
#import "iTermMarkRenderer.h"
#import "iTermMetalPerFrameStateConfiguration.h"
#import "iTermMetalPerFrameStateRow.h"
#import "iTermMutableAttributedStringBuilder.h"
#import "iTermPreferences.h"
#import "iTermSelection.h"
#import "iTermSmartCursorColor.h"
#import "iTermTextDrawingHelper.h"
#import "iTermTextRendererTransientState.h"
#import "iTermTuple.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSMutableData+iTerm.h"
#import "NSStringITerm.h"
#import "PTYFontInfo.h"
#import "PTYTextView.h"
#import "VT100Screen.h"
#import "VT100ScreenMark.h"

NS_ASSUME_NONNULL_BEGIN

extern void CGContextSetFontSmoothingStyle(CGContextRef, int);
extern int CGContextGetFontSmoothingStyle(CGContextRef);

typedef struct {
    unsigned int isMatch : 1;
    unsigned int inUnderlinedRange : 1;  // This is the underline for semantic history
    unsigned int selected : 1;
    unsigned int foregroundColor : 8;
    unsigned int fgGreen : 8;
    unsigned int fgBlue  : 8;
    unsigned int bold : 1;
    unsigned int faint : 1;
    vector_float4 background;
    ColorMode mode : 2;
    unsigned int isBlock : 1;
} iTermTextColorKey;

typedef struct {
    int bgColor;
    int bgGreen;
    int bgBlue;
    ColorMode bgColorMode;
    BOOL selected;
    BOOL isMatch;
    BOOL image;
} iTermBackgroundColorKey;

static vector_float4 VectorForColor(NSColor *colorInUnknownSpace, NSColorSpace *colorSpace) {
    NSColor *color = [colorInUnknownSpace colorUsingColorSpace:colorSpace];
    return (vector_float4) { color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent };
}

static NSColor *ColorForVector(vector_float4 v) {
    return [NSColor colorWithRed:v.x green:v.y blue:v.z alpha:v.w];
}

typedef struct {
    BOOL havePreviousCharacterAttributes;
    screen_char_t previousCharacterAttributes;
    vector_float4 lastUnprocessedColor;
    BOOL havePreviousForegroundColor;
    vector_float4 previousForegroundColor;
} iTermMetalPerFrameStateCaches;

@interface iTermMetalPerFrameState()<iTermAttributedStringBuilderDelegate> {
    iTermMetalPerFrameStateConfiguration *_configuration;

    // Cursor
    BOOL _cursorVisible;
    BOOL _cursorBlinking;
    iTermMetalCursorInfo *_cursorInfo;
    NSTimeInterval _timeSinceCursorMoved;

    // Geometry
    CGRect _documentVisibleRect;
    NSRect _adjustedDocumentVisibleRect;
    long long _totalScrollbackOverflow;
    VT100GridCoordRange _visibleRange;
    NSInteger _numberOfScrollbackLines;
    long long _firstVisibleAbsoluteLineNumber;
    long long _lastVisibleAbsoluteLineNumber;
    NSRect _containerRect;
    NSRect _relativeFrame;

    // Badge
    NSImage *_badgeImage;
    CGRect _badgeSourceRect;
    CGRect _badgeDestinationRect;

    // IME
    NSRange _inputMethodMarkedRange;
    iTermMetalIMEInfo *_imeInfo;

    NSMutableArray<iTermMetalPerFrameStateRow *> *_rows;
    NSMutableArray<iTermIndicatorDescriptor *> *_indicators;
    iTermImageWrapper *_backgroundImage;
    NSDictionary<NSNumber *, NSIndexSet *> *_rowToAnnotationRanges;  // Row on screen to characters with annotation underline on that row.
    NSArray<iTermHighlightedRow *> *_highlightedRows;
    NSTimeInterval _startTime;
    NSEdgeInsets _extraMargins;
    BOOL _haveOffscreenCommandLine;
    NSArray<iTermKittyImageDraw *> *_kittyImageDraws;

    VT100GridRange _linesToSuppressDrawing;
    CGFloat _pointsOnBottomToSuppressDrawing;
    iTermAttributedStringBuilder *_attributedStringBuilder;
}
@end

@implementation iTermMetalPerFrameState {
    CGContextRef _metalContext;
}

- (instancetype)initWithTextView:(PTYTextView *)textView
                          screen:(VT100Screen *)screen
                            glue:(id<iTermMetalPerFrameStateDelegate>)glue
                         context:(CGContextRef)context
         attributedStringBuilder:(iTermAttributedStringBuilder *)attributedStringBuilder {
    assert([NSThread isMainThread]);
    self = [super init];
    if (self) {
        _configuration = [[iTermMetalPerFrameStateConfiguration alloc] init];
        _rows = [NSMutableArray array];
        _startTime = [NSDate timeIntervalSinceReferenceDate];
        _metalContext = CGContextRetain(context);
        _attributedStringBuilder = attributedStringBuilder;
        [textView performBlockWithFlickerFixerGrid:^{
            [self loadAllWithTextView:textView screen:screen glue:glue];
        }];
    }
    return self;
}

- (void)dealloc {
    if (_metalContext) {
        CGContextRelease(_metalContext);
    }
}

- (NSString *)statisticsString {
    return _attributedStringBuilder.statisticsString;
}

- (void)loadAllWithTextView:(PTYTextView *)textView
                     screen:(VT100Screen *)screen
                       glue:(id<iTermMetalPerFrameStateDelegate>)glue {
    iTermTextDrawingHelper *drawingHelper = textView.drawingHelper;

    [_configuration loadSettingsWithDrawingHelper:drawingHelper textView:textView glue:glue];

    [_attributedStringBuilder copySettingsFrom:drawingHelper.attributedStringBuilder
                                      colorMap:_configuration->_colorMap
                                      delegate:self];

    [self loadSettingsWithDrawingHelper:drawingHelper textView:textView];
    [self loadMetricsWithDrawingHelper:drawingHelper textView:textView screen:screen];
    [self loadLinesWithDrawingHelper:drawingHelper textView:textView screen:screen];
    [self loadBadgeWithDrawingHelper:drawingHelper textView:textView];
    [self loadBlinkingCursorWithTextView:textView glue:glue];
    [self loadCursorInfoWithDrawingHelper:drawingHelper textView:textView];
    [self loadBackgroundImageWithGlue:glue];
    [self loadMarkedTextWithDrawingHelper:drawingHelper];
    [self loadIndicatorsFromTextView:textView drawingHelper:drawingHelper];
    [self loadHighlightedRowsFromTextView:textView];
    [self loadAnnotationRangesFromTextView:textView];
    [self loadOffscreenCommandLine:textView screen:screen drawingHelper:drawingHelper];
    [self loadImagesFromTextView:textView];

    // This isn't really appropriate here but there isn't a great place for it and we do have
    // everything we need, and the effect works well.
    [textView smearCursorIfNeededWithDrawingHelper:drawingHelper];
}

- (void)loadImagesFromTextView:(PTYTextView *)textView {
    _kittyImageDraws = [textView.dataSource.kittyImageDraws copy];
}

- (void)loadSettingsWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper
                             textView:(PTYTextView *)textView {
    _numberOfScrollbackLines = textView.dataSource.numberOfScrollbackLines;
    _cursorBlinking = textView.isCursorBlinking;
    _inputMethodMarkedRange = drawingHelper.inputMethodMarkedRange;
}

- (void)loadMetricsWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper
                            textView:(PTYTextView *)textView
                              screen:(VT100Screen *)screen {
    const long long totalScrollbackOverflow = [screen totalScrollbackOverflow];
    _documentVisibleRect = textView.textDrawingHelperVisibleRectExcludingTopMargin;
    _adjustedDocumentVisibleRect = textView.textDrawingHelperVisibleRectIncludingTopMargin;
    _totalScrollbackOverflow = totalScrollbackOverflow;

    _visibleRange = [drawingHelper coordRangeForRect:_documentVisibleRect];
    DLog(@"Visible range for document visible rect %@ is %@",
         NSStringFromRect(_documentVisibleRect), VT100GridCoordRangeDescription(_visibleRange));
    _visibleRange.start.x = MAX(0, _visibleRange.start.x);
    _visibleRange.start.y = MAX(0, _visibleRange.start.y);
    _visibleRange.end.x = _visibleRange.start.x + _configuration->_gridSize.width;
    _visibleRange.end.y = _visibleRange.start.y + _configuration->_gridSize.height;
    DLog(@"Safe visible range is %@", VT100GridCoordRangeDescription(_visibleRange));
    _firstVisibleAbsoluteLineNumber = _visibleRange.start.y + totalScrollbackOverflow;
    _lastVisibleAbsoluteLineNumber = _visibleRange.end.y + totalScrollbackOverflow;
    _relativeFrame = textView.delegate.textViewRelativeFrame;
    _containerRect = textView.delegate.textViewContainerRect;
    _extraMargins = textView.delegate.textViewExtraMargins;

    _linesToSuppressDrawing = drawingHelper.linesToSuppress;
    _linesToSuppressDrawing.location -= _visibleRange.start.y;
    _pointsOnBottomToSuppressDrawing = drawingHelper.pointsOnBottomToSuppressDrawing;
}

- (void)loadLinesWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper
                          textView:(PTYTextView *)textView
                            screen:(VT100Screen *)screen {
    iTermMetalPerFrameStateRowFactory *factory = [[iTermMetalPerFrameStateRowFactory alloc] initWithDrawingHelper:drawingHelper
                                                                                                         textView:textView
                                                                                                           screen:screen
                                                                                                    configuration:_configuration
                                                                                                            width:_configuration->_gridSize.width];
    for (int i = _visibleRange.start.y; i < _visibleRange.end.y; i++) {
        [_rows addObject:[factory newRowForLine:i]];
    }
}

- (void)loadBadgeWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper
                          textView:(PTYTextView *)textView {
    _badgeImage = drawingHelper.badgeImage;
    if (_badgeImage) {
        _badgeDestinationRect = [iTermTextDrawingHelper rectForBadgeImageOfSize:_badgeImage.size
                                                           destinationFrameSize:textView.frame.size
                                                                  sourceRectPtr:&_badgeSourceRect
                                                                        margins:NSEdgeInsetsMake(drawingHelper.badgeTopMargin,
                                                                                                 0,
                                                                                                 0,
                                                                                                 drawingHelper.badgeRightMargin)
                                                                 verticalOffset:0];
    }
}

- (void)loadBlinkingCursorWithTextView:(PTYTextView *)textView
                                  glue:(id<iTermMetalPerFrameStateDelegate>)glue {
    VT100GridCoord cursorScreenCoord = VT100GridCoordMake(textView.dataSource.cursorX - 1,
                                                          textView.dataSource.cursorY - 1);
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!VT100GridCoordEquals(cursorScreenCoord, glue.oldCursorScreenCoord)) {
        glue.lastTimeCursorMoved = now;
    }
    _timeSinceCursorMoved = now - glue.lastTimeCursorMoved;
    glue.oldCursorScreenCoord = cursorScreenCoord;
}

- (vector_float4)backgroundColorForCharacter:(screen_char_t)c
                                selected:(BOOL)selected
                               findMatch:(BOOL)findMatch {
    iTermBackgroundColorKey backgroundKey = {
        .bgColor = c.backgroundColor,
        .bgGreen = c.bgGreen,
        .bgBlue = c.bgBlue,
        .bgColorMode = c.backgroundColorMode,
        .selected = selected,
        .isMatch = findMatch,
        .image = c.image != 0 && c.virtualPlaceholder == 0,
    };
    BOOL isDefaultBackgroundColor = NO;
    const vector_float4 unprocessedBackgroundColor = [self unprocessedColorForBackgroundColorKey:&backgroundKey
                                                                   isDefault:&isDefaultBackgroundColor];
    return [_configuration->_colorMap fastProcessedBackgroundColorForBackgroundColor:unprocessedBackgroundColor];

}
- (void)loadCursorInfoWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper
                               textView:(PTYTextView *)textView {
    _cursorVisible = drawingHelper.isCursorVisible;
    const int offset = _visibleRange.start.y - _numberOfScrollbackLines;
    _cursorInfo = [[iTermMetalCursorInfo alloc] init];
    _cursorInfo.password = drawingHelper.passwordInput;
    _cursorInfo.copyMode = drawingHelper.copyMode;
    _cursorInfo.copyModeCursorCoord = VT100GridCoordMake(drawingHelper.copyModeCursorCoord.x,
                                                         drawingHelper.copyModeCursorCoord.y - _visibleRange.start.y);
    _cursorInfo.copyModeCursorSelecting = drawingHelper.copyModeSelecting;
    VT100GridCoord cursorCoord = [drawingHelper coordinateByTransformingScreenCoordinateForRTL:VT100GridCoordMake(textView.dataSource.cursorX - 1,
                                                                                                                  textView.dataSource.cursorY - 1)];
    cursorCoord.y -= offset;
    _cursorInfo.coord = cursorCoord;

    _cursorInfo.cursorShadow = drawingHelper.cursorShadow;
    NSInteger lineWithCursor = textView.dataSource.cursorY - 1 + _numberOfScrollbackLines;
    if ([self shouldDrawCursor] &&
        _cursorVisible &&
        _visibleRange.start.y <= lineWithCursor &&
        lineWithCursor < _visibleRange.end.y) {

        _cursorInfo.cursorVisible = YES;
        _cursorInfo.type = drawingHelper.cursorType;
        _cursorInfo.cursorColor = [self backgroundColorForCursor];
        {
            const screen_char_t *const line = _rows[_cursorInfo.coord.y]->_screenCharLine.line;
            const screen_char_t screenChar = _cursorInfo.coord.x < _rows[_cursorInfo.coord.y]->_screenCharLine.length ? line[_cursorInfo.coord.x] : (screen_char_t){0};
            
            if (screenChar.code) {
                if (ScreenCharIsDWC_RIGHT(screenChar)) {
                    _cursorInfo.doubleWidth = NO;
                } else {
                    const int column = _cursorInfo.coord.x;
                    _cursorInfo.doubleWidth = (column < _configuration->_gridSize.width - 1) && ScreenCharIsDWC_RIGHT(line[column + 1]);
                }
            } else {
                _cursorInfo.doubleWidth = NO;
            }
            iTermMetalPerFrameStateRow *row = _rows[_cursorInfo.coord.y];
            _cursorInfo.backgroundColor = [self backgroundColorForCharacter:screenChar
                                                                   selected:[row->_selectedIndexSet containsIndex:_cursorInfo.coord.x]
                                                                  findMatch:row->_matches && CheckFindMatchAtIndex(row->_matches, _cursorInfo.coord.x)];
            if (_cursorInfo.type == CURSOR_BOX) {
                _cursorInfo.shouldDrawText = YES;
                const BOOL focused = ((_configuration->_isInKeyWindow && _configuration->_textViewIsActiveSession) || _configuration->_shouldDrawFilledInCursor);


                iTermSmartCursorColor *smartCursorColor = nil;
                if (drawingHelper.useSmartCursorColor) {
                    smartCursorColor = [[iTermSmartCursorColor alloc] init];
                    smartCursorColor.delegate = self;
                }

                if (!focused) {
                    _cursorInfo.shouldDrawText = NO;
                    _cursorInfo.frameOnly = YES;
                } else if (smartCursorColor) {
                    _cursorInfo.textColor = [self fastCursorColorForCharacter:screenChar
                                                               wantBackground:YES
                                                                        muted:NO];
                    _cursorInfo.cursorColor = [smartCursorColor backgroundColorForCharacter:screenChar];
                    NSColor *regularTextColor = [NSColor colorWithRed:_cursorInfo.textColor.x
                                                                green:_cursorInfo.textColor.y
                                                                 blue:_cursorInfo.textColor.z
                                                                alpha:_cursorInfo.textColor.w];
                    NSColor *smartTextColor = [smartCursorColor textColorForCharacter:screenChar
                                                                     regularTextColor:regularTextColor
                                                                 smartBackgroundColor:_cursorInfo.cursorColor];
                    CGFloat components[4];
                    [smartTextColor getComponents:components];
                    _cursorInfo.textColor = simd_make_float4(components[0],
                                                             components[1],
                                                             components[2],
                                                             components[3]);
                } else {
                    if (_configuration->_reverseVideo) {
                        _cursorInfo.textColor = [_configuration->_colorMap fastColorForKey:kColorMapForeground];
                    } else {
                        _cursorInfo.textColor = [self colorForCode:ALTSEM_CURSOR
                                                             green:0
                                                              blue:0
                                                         colorMode:ColorModeAlternate
                                                              bold:NO
                                                             faint:NO
                                                      isBackground:NO].vector;
                    }
                }
            }
        }
    } else {
        _cursorInfo.cursorVisible = NO;
    }
}

- (void)loadBackgroundImageWithGlue:(id<iTermMetalPerFrameStateDelegate>)glue {
    _backgroundImage = [glue backgroundImage];
}

// Replace screen contents with input method editor.
- (void)loadMarkedTextWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper {
    if ([self hasMarkedText]) {
        VT100GridCoord startCoord = drawingHelper.cursorCoord;
        startCoord.y += drawingHelper.numberOfScrollbackLines - _visibleRange.start.y;
        [self copyMarkedText:drawingHelper.markedText.string
              cursorLocation:drawingHelper.inputMethodSelectedRange.location
                          to:drawingHelper.cursorCoord
      ambiguousIsDoubleWidth:drawingHelper.ambiguousIsDoubleWidth
               normalization:drawingHelper.normalization
              unicodeVersion:drawingHelper.unicodeVersion
                   gridWidth:drawingHelper.gridSize.width
            numberOfIMELines:drawingHelper.numberOfIMELines
         softAlternateScreen:drawingHelper.softAlternateScreenMode];
    }
}

- (void)loadHighlightedRowsFromTextView:(PTYTextView *)textView {
    _highlightedRows = [textView.highlightedRows copy];
}

- (BOOL)haveOffscreenCommandLine {
    return _haveOffscreenCommandLine;
}

- (iTermCharacterSourceDescriptor *)characterSourceDescriptorForASCIIWithGlyphSize:(CGSize)glyphSize
                                                                       asciiOffset:(CGSize)asciiOffset {
    return [iTermCharacterSourceDescriptor characterSourceDescriptorWithFontTable:_configuration->_fontTable
                                                                      asciiOffset:asciiOffset
                                                                        glyphSize:glyphSize
                                                                         cellSize:_configuration->_cellSize
                                                           cellSizeWithoutSpacing:_configuration->_cellSizeWithoutSpacing
                                                                            scale:_configuration->_scale
                                                                      useBoldFont:_configuration->_useBoldFont
                                                                    useItalicFont:_configuration->_useItalicFont
                                                                 usesNonAsciiFont:_configuration->_useNonAsciiFont
                                                                 asciiAntiAliased:_configuration->_asciiAntialias
                                                              nonAsciiAntiAliased:_configuration->_nonasciiAntialias];
}

- (CGFloat)transparencyAlpha {
    return _configuration->_transparencyAlpha;
}

- (CGFloat)blend {
    return _configuration->_backgroundImageBlend;
}

- (BOOL)hasBackgroundImage {
    return _backgroundImage != nil;
}

- (NSEdgeInsets)edgeInsets {
    return _configuration->_edgeInsets;
}

- (CGSize)cellSize {
    return _configuration->_cellSize;
}

- (CGSize)cellSizeWithoutSpacing {
    return _configuration->_cellSizeWithoutSpacing;
}

- (CGFloat)scale {
    return _configuration->_scale;
}

- (vector_float4)offscreenCommandLineOutlineColor {
    const float a = (float)_configuration->_offscreenCommandLineOutlineColor.alphaComponent;
    return simd_make_float4((float)_configuration->_offscreenCommandLineOutlineColor.redComponent * a,
                            (float)_configuration->_offscreenCommandLineOutlineColor.greenComponent * a,
                            (float)_configuration->_offscreenCommandLineOutlineColor.blueComponent * a,
                            a);
}

- (vector_float4)offscreenCommandLineBackgroundColor {
    const float a = (float)_configuration->_offscreenCommandLineBackgroundColor.alphaComponent;
    return simd_make_float4((float)_configuration->_offscreenCommandLineBackgroundColor.redComponent * a,
                            (float)_configuration->_offscreenCommandLineBackgroundColor.greenComponent * a,
                            (float)_configuration->_offscreenCommandLineBackgroundColor.blueComponent * a,
                            a);
}

- (VT100GridRange)linesToSuppressDrawing {
    return _linesToSuppressDrawing;
}

- (CGFloat)pointsOnBottomToSuppressDrawing {
    return _pointsOnBottomToSuppressDrawing;
}

// Populate _rowToAnnotationRanges.
- (void)loadAnnotationRangesFromTextView:(PTYTextView *)textView {
    NSRange rangeOfRows = NSMakeRange(_visibleRange.start.y, _visibleRange.end.y - _visibleRange.start.y + 1);
    NSArray<NSNumber *> *rows = [NSArray sequenceWithRange:rangeOfRows];
    _rowToAnnotationRanges = [rows reduceWithFirstValue:[NSMutableDictionary dictionary] block:^id(NSMutableDictionary *dict, NSNumber *second) {
        NSArray<NSValue *> *ranges = [textView.dataSource charactersWithNotesOnLine:second.intValue];
        if (ranges.count) {
            NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
            [ranges enumerateObjectsUsingBlock:^(NSValue * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                VT100GridRange gridRange = [obj gridRangeValue];
                [indexes addIndexesInRange:NSMakeRange(gridRange.location, gridRange.length)];
            }];
            dict[@(second.intValue - self->_visibleRange.start.y)] = indexes;
        }
        return dict;
    }];
}

// Replace the first entry in _rows with the offscren command line if we are showing one.
- (void)loadOffscreenCommandLine:(PTYTextView *)textView
                          screen:(VT100Screen *)screen 
                   drawingHelper:(iTermTextDrawingHelper *)drawingHelper {
    _haveOffscreenCommandLine = drawingHelper.offscreenCommandLine != nil;
    if (_haveOffscreenCommandLine) {
        _rows[0]->_screenCharLine = drawingHelper.offscreenCommandLine.characters;
        _rows[0]->_selectedIndexSet = [[NSIndexSet alloc] init];
        _rows[0]->_matches = nil;
        _rows[0]->_date = drawingHelper.offscreenCommandLine.date;
        const long long totalScrollbackOverflow = [screen totalScrollbackOverflow];
        const int i = drawingHelper.offscreenCommandLine.absoluteLineNumber - totalScrollbackOverflow;
        if (i < 0) {
            _rows[0]->_eaIndex = nil;
        } else {
            _rows[0]->_eaIndex = [[screen externalAttributeIndexForLine:i] copy];
        }
    }
}

- (void)loadIndicatorsFromTextView:(PTYTextView *)textView 
                     drawingHelper:(iTermTextDrawingHelper *)drawingHelper {
    _indicators = [NSMutableArray array];
    NSRect frame = drawingHelper.indicatorFrame;
    frame.origin.y -= MAX(0, textView.virtualOffset);
    
    [textView.indicatorsHelper enumerateTopRightIndicatorsInFrame:frame andDraw:NO block:^(NSString *identifier, NSImage *image, NSRect rect, BOOL dark) {
        iTermIndicatorDescriptor *indicator = [[iTermIndicatorDescriptor alloc] init];
        indicator.identifier = identifier;
        assert(image);
        indicator.image = image;
        indicator.frame = rect;
        indicator.alpha = 0.75;
        indicator.dark = dark;
        [self->_indicators addObject:indicator];
    }];
    [textView.indicatorsHelper enumerateCenterIndicatorsInFrame:frame block:^(NSString *identifier, NSImage *image, NSRect rect, CGFloat alpha, BOOL dark) {
        iTermIndicatorDescriptor *indicator = [[iTermIndicatorDescriptor alloc] init];
        indicator.identifier = identifier;
        indicator.image = image;
        assert(image);
        indicator.frame = rect;
        indicator.alpha = alpha;
        indicator.dark = dark;
        [self->_indicators addObject:indicator];
    }];
    [textView.indicatorsHelper didDraw];
}

- (screen_char_t)screenCharStyledForMarkedText:(screen_char_t)input {
    screen_char_t c = input;
    c.foregroundColor = ALTSEM_DEFAULT;
    c.fgGreen = 0;
    c.fgBlue = 0;
    c.foregroundColorMode = ColorModeAlternate;

    c.backgroundColor = ALTSEM_DEFAULT;
    c.bgGreen = 0;
    c.bgBlue = 0;
    c.backgroundColorMode = ColorModeAlternate;

    c.underline = YES;
    c.underlineStyle = VT100UnderlineStyleSingle;
    c.strikethrough = NO;
    c.rtlStatus = RTLStatusUnknown;

    return c;
}

- (void)copyMarkedText:(NSString *)str
        cursorLocation:(int)cursorLocation
                    to:(VT100GridCoord)startCoord
ambiguousIsDoubleWidth:(BOOL)ambiguousIsDoubleWidth
         normalization:(iTermUnicodeNormalization)normalization
        unicodeVersion:(NSInteger)unicodeVersion
             gridWidth:(int)gridWidth
      numberOfIMELines:(int)numberOfIMELines
   softAlternateScreen:(BOOL)softAlternateScreen {
    const int maxLen = [str length] * kMaxParts;
    screen_char_t buf[maxLen];
    screen_char_t fg = {0}, bg = {0};
    int len;
    int cursorIndex = cursorLocation;
    StringToScreenChars(str,
                        buf,
                        fg,
                        bg,
                        &len,
                        ambiguousIsDoubleWidth,
                        &cursorIndex,
                        NULL,
                        normalization,
                        unicodeVersion,
                        softAlternateScreen,
                        NULL);
    VT100GridCoord coord = startCoord;
    coord.y -= numberOfIMELines;
    BOOL foundCursor = NO;
    BOOL justWrapped = NO;
    BOOL foundStart = NO;
    if (coord.x == gridWidth) {
        coord.x = 0;
        coord.y++;
        justWrapped = YES;
    }

    _imeInfo = [[iTermMetalIMEInfo alloc] init];
    // i indexes into buf.
    for (int i = 0; i < len; i++) {
        if (coord.y >= 0 && coord.y < _rows.count) {
            if (i == cursorIndex) {
                foundCursor = YES;
                _imeInfo.cursorCoord = coord;
            }

            const BOOL wouldSplit = (i + 1 < len &&
                                     coord.x == gridWidth - 1 &&
                                     ScreenCharIsDWC_RIGHT(buf[i+1]) &&
                                     !buf[i+1].complexChar);
            if (wouldSplit) {
                // Bump DWC to start of next line instead of splitting it
                i--;
            } else {
                if (!foundStart) {
                    foundStart = YES;
                    [_imeInfo setRangeStart:coord];
                }
                ScreenCharArray *sca = _rows[coord.y]->_screenCharLine;
                const screen_char_t styled = [self screenCharStyledForMarkedText:buf[i]];
                _rows[coord.y]->_screenCharLine = [sca screenCharArrayBySettingCharacterAtIndex:coord.x
                                                                                             to:styled];
            }
        }
        justWrapped = NO;
        coord.x++;
        if (coord.x == gridWidth) {
            coord.x = 0;
            coord.y++;
            justWrapped = YES;
        }
        [_imeInfo setRangeEnd:coord];
    }

    if (!foundCursor) {
        if (justWrapped) {
            _imeInfo.cursorCoord = VT100GridCoordMake(gridWidth, coord.y - 1);
        } else {
            _imeInfo.cursorCoord = coord;
        }
    }
}

- (BOOL)isAnimating {
    return _highlightedRows.count > 0;
}

- (long long)firstVisibleAbsoluteLineNumber {
    return _firstVisibleAbsoluteLineNumber;
}

- (BOOL)timestampsEnabled {
    return _configuration->_timestampsEnabled;
}

- (NSColor *)timestampsTextColor {
    assert(_configuration->_timestampsEnabled);
    return [_configuration->_colorMap colorForKey:kColorMapForeground];
}

- (NSColor *)timestampsBackgroundColor {
    assert(_configuration->_timestampsEnabled);
    return [_configuration->_processedDefaultBackgroundColor colorUsingColorSpace:[NSImage colorSpaceForProgramaticallyGeneratedImages]];
}

- (void)enumerateIndicatorsInFrame:(NSRect)frame block:(void (^)(iTermIndicatorDescriptor * _Nonnull))block {
    [_indicators enumerateObjectsUsingBlock:^(iTermIndicatorDescriptor * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        block(obj);
    }];
}

- (void)metalEnumerateHighlightedRows:(void (^)(vector_float3, NSTimeInterval, int))block {
    for (iTermHighlightedRow *row in _highlightedRows) {
        long long line = row.absoluteLineNumber;
        if (line >= _firstVisibleAbsoluteLineNumber && line <= _lastVisibleAbsoluteLineNumber) {
            vector_float3 color;
            if (row.success) {
                color = simd_make_float3(0, 0, 1);
            } else {
                color = simd_make_float3(1, 0, 0);
            }
            block(color, _startTime - row.creationDate, line - _firstVisibleAbsoluteLineNumber);
        }
    }
}

- (vector_float4)fullScreenFlashColor {
    return _configuration->_fullScreenFlashColor;
}

- (BOOL)cursorGuideEnabled {
    return _configuration->_cursorGuideColor && _configuration->_cursorGuideEnabled;
}

- (NSColor *)cursorGuideColor {
    return _configuration->_cursorGuideColor;
}

- (BOOL)showBroadcastStripes {
    return _configuration->_showBroadcastStripes;
}

- (nullable iTermMetalIMEInfo *)imeInfo {
    return _imeInfo;
}

- (CGRect)badgeSourceRect {
    return _badgeSourceRect;
}

- (CGRect)badgeDestinationRect {
    return _badgeDestinationRect;
}

- (NSImage *)badgeImage {
    return _badgeImage;
}

- (VT100GridSize)gridSize {
    return _configuration->_gridSize;
}

- (NSColorSpace *)colorSpace {
    return _configuration->_colorSpace;
}

- (vector_float4)defaultBackgroundColor {
    NSColor *color = [_configuration->_colorMap colorForKey:kColorMapBackground];
    vector_float4 result = VectorForColor(color, _configuration->_colorSpace);
    result.w = 1;
    return result;
}

- (vector_float4)selectedBackgroundColor {
    return _configuration->_selectionColor;
}

- (vector_float4)processedDefaultBackgroundColor {
    float alpha;
    if (iTermTextIsMonochrome()) {
        if (_backgroundImage) {
            alpha = iTermAlphaValueForTopView(1 - _configuration->_transparencyAlpha,
                                              _configuration->_backgroundImageBlend);
        } else {
            alpha = iTermAlphaValueForTopView(1 - _configuration->_transparencyAlpha, 0);
        }
    } else {
        // Can assume transparencyAlpha is 1
        alpha = iTermAlphaValueForTopView(0, _configuration->_backgroundImageBlend);
    }
    return simd_make_float4((float)_configuration->_processedDefaultBackgroundColor.redComponent,
                            (float)_configuration->_processedDefaultBackgroundColor.greenComponent,
                            (float)_configuration->_processedDefaultBackgroundColor.blueComponent,
                            alpha);
}

- (const vector_float4 *)selectedCommandOutlineColors {
    return _configuration->_selectedCommandOutlineColors;
}

- (iTermRectArray *)buttonsBackgroundRects {
    return _configuration->_buttonsBackgroundRects;
}

- (vector_float4)shadeColor {
    return _configuration->_shadeColor;
}

- (BOOL)forceRegularBottomMargin {
    return _configuration->_forceRegularBottomMargin;
}

- (vector_float4)processedDefaultTextColor {
    return simd_make_float4((float)_configuration->_processedDefaultTextColor.redComponent,
                            (float)_configuration->_processedDefaultTextColor.greenComponent,
                            (float)_configuration->_processedDefaultTextColor.blueComponent,
                            1.0);
}

- (vector_float4)blockHoverColor {
    return simd_make_float4((float)_configuration->_blockHoverColor.redComponent,
                            (float)_configuration->_blockHoverColor.greenComponent,
                            (float)_configuration->_blockHoverColor.blueComponent,
                            1.0);
}

- (vector_float4)defaultTextColor {
    return simd_make_float4((float)_configuration->_defaultTextColor.redComponent,
                            (float)_configuration->_defaultTextColor.greenComponent,
                            (float)_configuration->_defaultTextColor.blueComponent,
                            1.0);
}

- (iTermLineStyleMarkColors)lineStyleMarkColors {
    return _configuration->_lineStyleMarkColors;
}

- (BOOL)hasSelectedCommand {
    return _configuration->_selectedCommandRegion.length > 0;
}

- (VT100GridRect)selectedCommandRect {
    long long minY = ((long long)_configuration->_selectedCommandRegion.location) - _visibleRange.start.y;
    minY -= _configuration->_totalScrollbackOverflow;
    long long maxY = ((long long)NSMaxRange(_configuration->_selectedCommandRegion)) - _visibleRange.start.y;
    maxY -= _configuration->_totalScrollbackOverflow;
    minY = MAX(-1, minY);
    maxY = MIN(_configuration->_gridSize.height + 1, maxY);

    return VT100GridRectMake(0,
                             minY,
                             _configuration->_gridSize.width,
                             MAX(0, maxY - minY));
}

- (NSRange)selectedCommandRegion {
    return _configuration->_selectedCommandRegion;
}

// Private queue
- (nullable iTermMetalCursorInfo *)metalDriverCursorInfo {
    return _cursorInfo;
}

// Private queue
- (iTermImageWrapper *)metalBackgroundImageGetMode:(nullable iTermBackgroundImageMode *)mode {
    if (mode) {
        *mode = _configuration->_backgroundImageMode;
    }
    return _backgroundImage;
}

NS_INLINE void iTermGlyphKeySetVisualPosition(iTermMetalGlyphKey *glyphKeys,
                                              int gk,
                                              int logicalIndex,
                                              const int *bidiLUT,
                                              int bidiLUTLength) {
    if (bidiLUT && logicalIndex < bidiLUTLength) {
        glyphKeys[gk].visualColumn = bidiLUT[logicalIndex];
    } else {
        glyphKeys[gk].visualColumn = logicalIndex;
    }
}

NS_INLINE int iTermGlyphKeyEmitPlaceholder(iTermMetalGlyphKey *glyphKeys,
                                           int i,
                                           int logicalIndex,
                                           const int *bidiLUT,
                                           int bidiLUTLength) {
    glyphKeys[i].type = iTermMetalGlyphTypeRegular;
    glyphKeys[i].payload.regular.drawable = NO;
    glyphKeys[i].payload.regular.combiningSuccessor = 0;
    iTermGlyphKeySetVisualPosition(glyphKeys, i, logicalIndex, bidiLUT, bidiLUTLength);
    return i + 1;
}

NS_INLINE int iTermGlyphKeyEmitRegular(iTermMetalGlyphKey *glyphKeys,
                                       int i,
                                       int logicalIndex,
                                       int width,
                                       BOOL characterIsDrawable,
                                       const screen_char_t *line,
                                       BOOL isBoxDrawingCharacter,
                                       BOOL thinStrokes,
                                       const int *bidiLUT,
                                       int bidiLUTLength) {
    glyphKeys[i].type = iTermMetalGlyphTypeRegular;
    if (characterIsDrawable) {
        glyphKeys[i].payload.regular.code = line[logicalIndex].code;
        glyphKeys[i].payload.regular.isComplex = line[logicalIndex].complexChar;
    } else {
        glyphKeys[i].payload.regular.code = ' ';
        glyphKeys[i].payload.regular.isComplex = NO;
    }
    glyphKeys[i].payload.regular.boxDrawing = isBoxDrawingCharacter;
    const int boldBit = line[logicalIndex].bold ? (1 << 0) : 0;
    const int italicBit = line[logicalIndex].italic ? (1 << 1) : 0;
    glyphKeys[i].typeface = (boldBit | italicBit);
    glyphKeys[i].payload.regular.drawable = YES;
    if (logicalIndex + 1 < width &&
        line[logicalIndex + 1].complexChar &&
        !(!line[logicalIndex].complexChar && line[logicalIndex].code < 128) &&
        ComplexCharCodeIsSpacingCombiningMark(line[logicalIndex + 1].code)) {
        // Next character is a combining spacing mark that will join with this non-ascii character.
        glyphKeys[i].payload.regular.combiningSuccessor = line[logicalIndex + 1].code;
    } else {
        glyphKeys[i].payload.regular.combiningSuccessor = 0;
    }
    glyphKeys[i].thinStrokes = thinStrokes;
    glyphKeys[i].logicalIndex = logicalIndex;
    iTermGlyphKeySetVisualPosition(glyphKeys, i, logicalIndex, bidiLUT, bidiLUTLength);
    return i + 1;
}

NS_INLINE int iTermGlyphKeyEmitDecomposedFromCheap(iTermGlyphKeyData *glyphKeyData,
                                                   BOOL bold,
                                                   BOOL italic,
                                                   int gk,
                                                   int logicalIndex,
                                                   iTermCheapAttributedString *cheapString,
                                                   BOOL thinStrokes,
                                                   const int *bidiLUT,
                                                   int bidiLUTLength) {
    CGGlyph glyphs[cheapString.length];
    NSFont *font = cheapString.attributes[NSFontAttributeName];
    BOOL ok = CTFontGetGlyphsForCharacters((CTFontRef)font,
                                           cheapString.characters,
                                           glyphs,
                                           cheapString.length);
    if (!ok) {
        return -1;
    }
    CGPoint positions[cheapString.length];
    memset(positions, 0, sizeof(positions));

    const BOOL fakeBold = [cheapString.attributes[iTermFakeBoldAttribute] boolValue];
    const BOOL fakeItalic = [cheapString.attributes[iTermFakeItalicAttribute] boolValue];
    return iTermGlyphKeyEmitDecomposedFromGlyphs(glyphKeyData,
                                                 bold,
                                                 italic,
                                                 fakeBold,
                                                 fakeItalic,
                                                 gk,
                                                 logicalIndex,
                                                 font,
                                                 glyphs,
                                                 cheapString.length,
                                                 thinStrokes,
                                                 bidiLUT,
                                                 bidiLUTLength);
}

NS_INLINE int iTermGlyphKeyEmitDecomposedFromGlyphs(iTermGlyphKeyData *glyphKeyData,
                                                    BOOL bold,
                                                    BOOL italic,
                                                    BOOL fakeBold,
                                                    BOOL fakeItalic,
                                                    int gk,
                                                    int logicalIndex,
                                                    NSFont *font,
                                                    CGGlyph *glyphs,
                                                    NSUInteger length,
                                                    BOOL thinStrokes,
                                                    const int *bidiLUT,
                                                    int bidiLUTLength) {
    if (glyphKeyData.count < gk + length) {
        glyphKeyData.count = (gk + length) * 2;
    }
    iTermMetalGlyphKey *glyphKeys = glyphKeyData.basePointer;

    for (NSUInteger i = 0; i < length; i++) {
        iTermGlyphKeyEmitDecomposedForSingleGlyph(glyphKeys,
                                                  bold,
                                                  italic,
                                                  fakeBold,
                                                  fakeItalic,
                                                  font.it_metalFontID,
                                                  glyphs[i],
                                                  CGPointZero,
                                                  gk + i,
                                                  logicalIndex + i,
                                                  thinStrokes,
                                                  bidiLUT,
                                                  bidiLUTLength);
    }
    return gk + length;
}

NS_INLINE void iTermGlyphKeyEmitDecomposedForSingleGlyph(iTermMetalGlyphKey *glyphKeys,
                                                         BOOL bold,
                                                         BOOL italic,
                                                         BOOL fakeBold,
                                                         BOOL fakeItalic,
                                                         int fontID,
                                                         CGGlyph glyph,
                                                         NSPoint glyphPositionRelativeToCellOrigin,
                                                         int gk,
                                                         CFIndex logicalIndex,
                                                         BOOL thinStrokes,
                                                         const int *bidiLUT,
                                                         int bidiLUTLength) {
    glyphKeys[gk].type = iTermMetalGlyphTypeDecomposed;
    glyphKeys[gk].payload.decomposed.fontID = fontID;
    glyphKeys[gk].payload.decomposed.glyphNumber = glyph;
    glyphKeys[gk].payload.decomposed.fakeBold = fakeBold;
    glyphKeys[gk].payload.decomposed.fakeItalic = fakeItalic;
    glyphKeys[gk].payload.decomposed.position = glyphPositionRelativeToCellOrigin;
    glyphKeys[gk].logicalIndex = logicalIndex;
    glyphKeys[gk].thinStrokes = thinStrokes;
    const int boldBit = bold ? (1 << 0) : 0;
    const int italicBit = italic ? (1 << 1) : 0;
    glyphKeys[gk].typeface = (boldBit | italicBit);

    iTermGlyphKeySetVisualPosition(glyphKeys, gk, logicalIndex, bidiLUT, bidiLUTLength);
}

NS_INLINE int iTermGlyphKeyEmitDecomposedFromNSAttributedString(iTermGlyphKeyData *glyphKeyData,
                                                                BOOL bold,
                                                                BOOL italic,
                                                                BOOL fakeBold,
                                                                BOOL fakeItalic,
                                                                int gk,
                                                                int logicalIndex,
                                                                NSAttributedString *attributedString,
                                                                BOOL thinStrokes,
                                                                const CTVector(CGFloat) *positions,
                                                                const int *bidiLUT,
                                                                int bidiLUTLength,
                                                                const int *characterIndexToSourceCell) {
    NSDictionary *attributes = [attributedString attributesAtIndex:0 effectiveRange:nil];
    if (attributes[iTermImageCodeAttribute] ||
        [attributes[iTermIsBoxDrawingAttribute] boolValue]) {
        assert(false);
        return gk;
    }

    static iTermLRUDictionary<iTermAttributedStringProxy *, id> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[iTermLRUDictionary alloc] initWithMaximumSize:10000];
    });
    iTermAttributedStringProxy *proxy = [iTermAttributedStringProxy withAttributedString:attributedString];
    CTLineRef lineRef = (__bridge CTLineRef)cache[proxy];
    if (lineRef == nil) {
        lineRef = CTLineCreateWithAttributedString((CFAttributedStringRef)attributedString);
        [cache addObjectWithKey:proxy
                          value:(__bridge id)lineRef
                           cost:1];
        CFRelease(lineRef);
    }

    iTermCoreTextLineRenderingHelper *helper = [[iTermCoreTextLineRenderingHelper alloc] initWithLine:lineRef
                                                                                               string:attributedString.string
                                                                                      drawInCellIndex:attributes[iTermDrawInCellIndexAttribute]];
    __block int o = gk;
    [helper enumerateGridAlignedRunsWithColumnPositions:CTVectorElementsFromIndex(positions, logicalIndex)
                                            alignToZero:YES
                                                closure:^(CTRunRef run,
                                                          CTFontRef font,
                                                          const CGGlyph *glyphs,
                                                          const NSPoint *positions,
                                                          const CFIndex *glyphIndexToCharacterIndex,
                                                          size_t length,
                                                          BOOL *stop) {
        if (glyphKeyData.count < o + length) {
            [glyphKeyData setCount:(o + length) * 2];
        }
        const int fontID = [(__bridge NSFont *)font it_metalFontID];
        for (int i = 0; i < length; i++) {
            const CFIndex characterIndex = glyphIndexToCharacterIndex[i];
            const int sourceCell = characterIndexToSourceCell ? characterIndexToSourceCell[characterIndex] : (logicalIndex + characterIndex);
            iTermGlyphKeyEmitDecomposedForSingleGlyph(glyphKeyData.basePointer,
                                                      bold,
                                                      italic,
                                                      fakeBold,
                                                      fakeItalic,
                                                      fontID,
                                                      glyphs[i],
                                                      positions[i],
                                                      o + i,
                                                      sourceCell,
                                                      thinStrokes,
                                                      bidiLUT,
                                                      bidiLUTLength);
        }
        o += length;
    }];
    return o;
}

NS_INLINE int iTermGlyphKeyEmitDecomposed(iTermGlyphKeyData *glyphKeyData,
                                          BOOL bold,
                                          BOOL italic,
                                          int gk,
                                          int logicalIndex,
                                          id<iTermAttributedString> attributedString,
                                          BOOL thinStrokes,
                                          const CTVector(CGFloat) *positions,
                                          const int *bidiLUT,
                                          int bidiLUTLength) {
    iTermCheapAttributedString *cheapString = [iTermCheapAttributedString castFrom:attributedString];
    NSAttributedString *nsAttributedString = nil;
    if (cheapString) {
        int result = iTermGlyphKeyEmitDecomposedFromCheap(glyphKeyData,
                                                          bold,
                                                          italic,
                                                          gk,
                                                          logicalIndex,
                                                          cheapString,
                                                          thinStrokes,
                                                          bidiLUT,
                                                          bidiLUTLength);
        if (result >= 0) {
            return result;
        }
        NSString *string = [NSString stringWithCharacters:cheapString.characters
                                                   length:cheapString.length];
        nsAttributedString = [NSAttributedString attributedStringWithString:string
                                                                 attributes:cheapString.attributes];
    }
    if (!nsAttributedString) {
        nsAttributedString = [NSAttributedString castFrom:attributedString];
    }
    if (!nsAttributedString) {
        assert(false);
        return gk;
    }
    const BOOL fakeBold = [[nsAttributedString attribute:iTermFakeBoldAttribute atIndex:0 effectiveRange:nil] boolValue];
    const BOOL fakeItalic = [[nsAttributedString attribute:iTermFakeItalicAttribute atIndex:0 effectiveRange:nil] boolValue];
    NSData *data = [NSData castFrom:[nsAttributedString attribute:iTermSourceCellIndexAttribute atIndex:0 effectiveRange:nil]];
    const int *characterIndexToSourceCell = (const int *)data.bytes;
    return iTermGlyphKeyEmitDecomposedFromNSAttributedString(glyphKeyData,
                                                             bold,
                                                             italic,
                                                             fakeBold,
                                                             fakeItalic,
                                                             gk,
                                                             logicalIndex,
                                                             nsAttributedString,
                                                             thinStrokes,
                                                             positions,
                                                             bidiLUT,
                                                             bidiLUTLength,
                                                             characterIndexToSourceCell);
}

NS_INLINE void iTermGlyphKeyEmitImage(const screen_char_t *const line,
                                      int logicalIndex,
                                      int row,
                                      iTermExternalAttribute *ea,
                                      iTermKittyUnicodePlaceholderState *kittyPlaceholderStatePtr,
                                      NSMutableArray<iTermKittyImageRun *> *kittyImageRuns,
                                      NSArray<iTermKittyImageDraw *> *kittyImageDraws,
                                      int *previousImageCodePtr,
                                      VT100GridCoord *previousImageCoordPtr,
                                      NSMutableArray<iTermMetalImageRun *> *imageRuns) {
    if (line[logicalIndex].virtualPlaceholder) {
        iTermKittyUnicodePlaceholderInfo info;
        if (iTermDecodeKittyUnicodePlaceholder(&line[logicalIndex], ea, kittyPlaceholderStatePtr, &info)) {
            if (info.runLength > 1) {
                kittyImageRuns.lastObject.length += 1;
            } else {
                iTermKittyImageDraw *draw = [kittyImageDraws objectPassingTest:^BOOL(iTermKittyImageDraw *draw, NSUInteger index, BOOL *stop) {
                    return draw.placementID == info.placementID;
                }];
                if (draw) {
                    iTermKittyImageRun *run =
                    [[iTermKittyImageRun alloc] initWithDraw:draw
                                                 sourceCoord:VT100GridCoordMake(info.column,
                                                                                info.row)
                                                   destCoord:VT100GridCoordMake(logicalIndex, row)
                                                      length:1];
                    [kittyImageRuns addObject:run];
                }
            }
        }
    } else {
        if (line[logicalIndex].code == *previousImageCodePtr &&
            line[logicalIndex].foregroundColor == ((previousImageCoordPtr->x + 1) & 0xff) &&
            line[logicalIndex].backgroundColor == previousImageCoordPtr->y) {
            imageRuns.lastObject.length = imageRuns.lastObject.length + 1;
            previousImageCoordPtr->x++;
        } else {
            *previousImageCodePtr = line[logicalIndex].code;
            iTermMetalImageRun *run = [[iTermMetalImageRun alloc] init];
            *previousImageCoordPtr = GetPositionOfImageInChar(line[logicalIndex]);
            run.code = line[logicalIndex].code;
            run.startingCoordInImage = *previousImageCoordPtr;
            run.startingCoordOnScreen = VT100GridCoordMake(logicalIndex, row);
            run.length = 1;
            run.imageInfo = GetImageInfo(line[logicalIndex].code);
            [imageRuns addObject:run];
        }
    }
}

static int iTermGetMetalBackgroundColors(iTermMetalPerFrameState *self,
                                         const screen_char_t *const line,
                                         iTermMetalBackgroundColorRLE *backgroundRLE,
                                         iTermMetalGlyphAttributes *attributes,
                                         vector_float4 *unprocessedBackgroundColors,
                                         int width,
                                         NSIndexSet *selectedIndexes,
                                         NSData *findMatches,
                                         id<iTermColorMapReading> colorMap,
                                         iTermBidiDisplayInfo *bidiInfo) {
    iTermBackgroundColorKey lastBackgroundKey;
    vector_float4 lastUnprocessedBackgroundColor = simd_make_float4(0, 0, 0, 0);
    int rles = 0;
    const int *bidiLUT = [bidiInfo lut];
    const int bidiLUTLength = bidiInfo.numberOfCells;
    int prevVisualX = -1;

    // Set background colors
    for (int logicalX = 0; logicalX < width; logicalX++) {
        int visualX = logicalX;
        if (logicalX < bidiLUTLength) {
            visualX = bidiLUT[logicalX];
        }
        const BOOL selected = [selectedIndexes containsIndex:visualX];
        BOOL findMatch = NO;
        if (findMatches && !selected) {
            findMatch = CheckFindMatchAtIndex(findMatches, logicalX);
        }

        // Background colors
        iTermBackgroundColorKey backgroundKey = {
            .bgColor = line[logicalX].backgroundColor,
            .bgGreen = line[logicalX].bgGreen,
            .bgBlue = line[logicalX].bgBlue,
            .bgColorMode = line[logicalX].backgroundColorMode,
            .selected = selected,
            .isMatch = findMatch,
            .image = line[logicalX].image && !line[logicalX].virtualPlaceholder,
        };

        vector_float4 backgroundColor;
        vector_float4 unprocessedBackgroundColor;
        if (logicalX > 0 &&
            abs(visualX - prevVisualX) == 1 &&
            backgroundKey.bgColor == lastBackgroundKey.bgColor &&
            backgroundKey.bgGreen == lastBackgroundKey.bgGreen &&
            backgroundKey.bgBlue == lastBackgroundKey.bgBlue &&
            backgroundKey.bgColorMode == lastBackgroundKey.bgColorMode &&
            backgroundKey.selected == lastBackgroundKey.selected &&
            backgroundKey.isMatch == lastBackgroundKey.isMatch &&
            backgroundKey.image == lastBackgroundKey.image) {
            // Extend RLE
            const int previousRLE = rles - 1;
            backgroundColor = backgroundRLE[previousRLE].color;
            backgroundRLE[previousRLE].count++;
            if (visualX < prevVisualX) {
                backgroundRLE[previousRLE].origin -= 1;
            }
            unprocessedBackgroundColor = lastUnprocessedBackgroundColor;
        } else {
            // Start new RLE
            BOOL isDefaultBackgroundColor = NO;
            unprocessedBackgroundColor = [self unprocessedColorForBackgroundColorKey:&backgroundKey
                                                                           isDefault:&isDefaultBackgroundColor];
            lastUnprocessedBackgroundColor = unprocessedBackgroundColor;
            // The unprocessed color is needed for minimum contrast computation for text color.
            backgroundColor = [colorMap fastProcessedBackgroundColorForBackgroundColor:unprocessedBackgroundColor];
            backgroundRLE[rles].color = backgroundColor;
            backgroundRLE[rles].origin = visualX;
            backgroundRLE[rles].count = 1;
            backgroundRLE[rles].logicalOrigin = logicalX;
            backgroundRLE[rles].isDefault = isDefaultBackgroundColor;
            unprocessedBackgroundColors[rles] = unprocessedBackgroundColor;
            rles++;
        }
        prevVisualX = visualX;
        lastBackgroundKey = backgroundKey;
        attributes[visualX].backgroundColor = backgroundColor;
        attributes[visualX].unprocessedBackgroundColor = unprocessedBackgroundColor;
    }

    return rles;
}

static void iTermInitializeColorKey(BOOL findMatch,
                                    BOOL inUnderlinedRange,
                                    BOOL selected,
                                    BOOL isBlockCharacter,
                                    vector_float4 bgColor,
                                    const screen_char_t *characterPointer,
                                    iTermTextColorKey *currentColorKey) {
    currentColorKey->isMatch = findMatch;
    currentColorKey->inUnderlinedRange = inUnderlinedRange;
    currentColorKey->selected = selected;
    currentColorKey->mode = characterPointer->foregroundColorMode;
    currentColorKey->foregroundColor = characterPointer->foregroundColor;
    currentColorKey->fgGreen = characterPointer->fgGreen;
    currentColorKey->fgBlue = characterPointer->fgBlue;
    currentColorKey->bold = characterPointer->bold;
    currentColorKey->faint = characterPointer->faint;
    currentColorKey->background = bgColor;
    currentColorKey->isBlock = isBlockCharacter;
}

static BOOL iTermColorKeysEqual(const iTermTextColorKey *lhs,
                                const iTermTextColorKey *rhs) {
    return (lhs->isMatch == rhs->isMatch &&
            lhs->inUnderlinedRange == rhs->inUnderlinedRange &&
            lhs->selected == rhs->selected &&
            lhs->foregroundColor == rhs->foregroundColor &&
            lhs->mode == rhs->mode &&
            lhs->fgGreen == rhs->fgGreen &&
            lhs->fgBlue == rhs->fgBlue &&
            lhs->bold == rhs->bold &&
            lhs->faint == rhs->faint &&
            simd_equal(lhs->background, rhs->background) &&
            lhs->isBlock == rhs->isBlock);
}

static void iTermMetalSetUnderline(iTermMetalPerFrameState *self,
                                   BOOL annotated,
                                   BOOL inUnderlinedRange,
                                   BOOL underlineHyperlinks,
                                   const screen_char_t *const line,
                                   const iTermTextColorKey *currentColorKey,
                                   int logicalIndex,
                                   int visualX,
                                   iTermURL *url,
                                   iTermExternalAttribute *ea,
                                   iTermMetalGlyphAttributes *attributes) {
    if (annotated) {
        attributes[visualX].underlineStyle = iTermMetalGlyphAttributesUnderlineSingle;
    } else if (line[logicalIndex].underline || inUnderlinedRange) {
        const BOOL curly = line[logicalIndex].underline && line[logicalIndex].underlineStyle == VT100UnderlineStyleCurly;
        if (url != nil) {
            attributes[visualX].underlineStyle = iTermMetalGlyphAttributesUnderlineHyperlink;
        } else if (line[logicalIndex].underline && line[logicalIndex].underlineStyle == VT100UnderlineStyleDouble && !inUnderlinedRange) {
            attributes[visualX].underlineStyle = iTermMetalGlyphAttributesUnderlineDouble;
        } else if (curly && !inUnderlinedRange) {
            attributes[visualX].underlineStyle = iTermMetalGlyphAttributesUnderlineCurly;
        } else {
            attributes[visualX].underlineStyle = iTermMetalGlyphAttributesUnderlineSingle;
        }
    } else if (url != nil && underlineHyperlinks) {
        attributes[visualX].underlineStyle = iTermMetalGlyphAttributesUnderlineDashedSingle;
    } else {
        attributes[visualX].underlineStyle = iTermMetalGlyphAttributesUnderlineNone;
    }
    if (line[logicalIndex].strikethrough) {
        // This right here is why strikethrough and underline is mutually exclusive
        attributes[visualX].underlineStyle |= iTermMetalGlyphAttributesUnderlineStrikethroughFlag;
    }
    if (ea) {
        attributes[visualX].hasUnderlineColor = ea.hasUnderlineColor;
        if (attributes[visualX].hasUnderlineColor) {
            attributes[visualX].underlineColor = [self vectorColorForCode:ea.underlineColor.red
                                                              green:ea.underlineColor.green
                                                               blue:ea.underlineColor.blue
                                                          colorMode:ea.underlineColor.mode
                                                               bold:NO
                                                              faint:currentColorKey->faint
                                                       isBackground:NO];
        }
    } else {
        attributes[visualX].hasUnderlineColor = NO;
    }
}

static int iTermEmitGlyphsAndSetAttributes(iTermMetalPerFrameState *self,
                                           const screen_char_t *const line,
                                           int row,
                                           int width,
                                           NSArray<id<iTermAttributedString>> *attributedStrings,
                                           CTVector(CGFloat) positions,
                                           iTermBidiDisplayInfo *bidiInfo,
                                           NSIndexSet *selectedIndexes,
                                           NSIndexSet *annotatedIndexes,
                                           NSData *findMatches,
                                           NSRange underlinedRange,
                                           iTermExternalAttributeIndex *eaIndex,
                                           iTermMetalPerFrameStateConfiguration *_configuration,
                                           NSMutableArray<iTermKittyImageRun *> *kittyImageRuns,
                                           NSArray<iTermKittyImageDraw *> *kittyImageDraws,
                                           NSMutableArray<iTermMetalImageRun *> *imageRuns,
                                           // out parameters:
                                           iTermGlyphKeyData *glyphKeysData,
                                           iTermMetalGlyphKey *glyphKeys,
                                           iTermMetalGlyphAttributes *attributes,
                                           int *drawableGlyphsPtr) {
    const int *bidiLUT = [bidiInfo lut];
    const int bidiLUTLength = bidiInfo.numberOfCells;
    int asIndex = -1;
    int previousVisualX = -1;
    BOOL lastSelected = NO;
    NSCharacterSet *boxCharacterSet = [iTermBoxDrawingBezierCurveFactory boxDrawingCharactersWithBezierPathsIncludingPowerline:_configuration->_useNativePowerlineGlyphs];
    iTermTextColorKey keys[2];
    iTermTextColorKey *currentColorKey = &keys[0];
    iTermTextColorKey *previousColorKey = &keys[1];
    const BOOL underlineHyperlinks = [iTermAdvancedSettingsModel underlineHyperlinks];
    int nextAttributedStringLogicalStartIndex = attributedStrings.count > 0 ? [attributedStrings.firstObject sourceColumnRange].location : -1;
    id<iTermAttributedString> attributedString = nil;
    NSInteger gk = 0;
    BOOL haveEmittedAttributedString = NO;
    NSCharacterSet *blockCharacterSet = [iTermBoxDrawingBezierCurveFactory blockDrawingCharacters];
    int previousImageCode = -1;
    VT100GridCoord previousImageCoord;
    int lastDrawableGlyph = -1;

    iTermKittyUnicodePlaceholderState kittyPlaceholderState;
    iTermKittyUnicodePlaceholderStateInit(&kittyPlaceholderState);

    iTermMetalPerFrameStateCaches caches;
    memset(&caches, 0, sizeof(caches));

    for (int logicalIndex = 0; logicalIndex < width; logicalIndex++) {
        if (attributedStrings && logicalIndex == nextAttributedStringLogicalStartIndex) {
            // Check for an attributed string.
            if (asIndex + 1 < attributedStrings.count) {
                const NSRange columnRange = [attributedStrings[asIndex + 1] sourceColumnRange];
                if (NSLocationInRange(logicalIndex, columnRange)) {
                    // We can use this attributed string.
                    asIndex += 1;
                    nextAttributedStringLogicalStartIndex = NSMaxRange(columnRange);
                    attributedString = attributedStrings[asIndex];
                    haveEmittedAttributedString = NO;
                } else {
                    // There is a gap before the next attributed string.
                    nextAttributedStringLogicalStartIndex = columnRange.location;
                    attributedString = nil;
                }
            } else {
                // We are out of attributed strings.
                nextAttributedStringLogicalStartIndex = -1;
                attributedString = nil;
            }
        }
        int visualX = logicalIndex;
        if (logicalIndex < bidiLUTLength) {
            visualX = bidiLUT[logicalIndex];
        }

        const vector_float4 bgColor = attributes[visualX].backgroundColor;
        BOOL selected = [selectedIndexes containsIndex:visualX];
        BOOL findMatch = NO;
        if (findMatches && !selected) {
            findMatch = CheckFindMatchAtIndex(findMatches, logicalIndex);
        }
        if (lastSelected && ScreenCharIsDWC_RIGHT(line[logicalIndex])) {
            // If the left half of a DWC was selected, extend the selection to the right half.
            lastSelected = selected;
            selected = YES;
        } else if (!lastSelected && selected && ScreenCharIsDWC_RIGHT(line[logicalIndex])) {
            // If the right half of a DWC is selected but the left half is not, un-select the right half.
            lastSelected = YES;
            selected = NO;
        } else {
            // Normal code path
            lastSelected = selected;
        }
        const BOOL annotated = [annotatedIndexes containsIndex:visualX];
        const BOOL inUnderlinedRange = NSLocationInRange(logicalIndex, underlinedRange) || annotated;


        attributes[visualX].annotation = annotated;

        iTermExternalAttribute *ea = eaIndex[logicalIndex];
        iTermURL *url = ea.url;
        const BOOL characterIsDrawable = iTermTextDrawingHelperIsCharacterDrawable(&line[logicalIndex],
                                                                                   logicalIndex > 0 ? &line[logicalIndex - 1] : NULL,
                                                                                   line[logicalIndex].complexChar && (ScreenCharToStr(&line[logicalIndex]) != nil),
                                                                                   _configuration->_blinkingItemsVisible,
                                                                                   _configuration->_blinkAllowed,
                                                                                   NO /* preferSpeedToFullLigatureSupport */,
                                                                                   url != nil);
        const BOOL isBoxDrawingCharacter = (characterIsDrawable &&
                                            !line[logicalIndex].complexChar &&
                                            line[logicalIndex].code > 127 &&
                                            [boxCharacterSet characterIsMember:line[logicalIndex].code]);
        const BOOL isBlockCharacter = (characterIsDrawable &&
                                       !line[logicalIndex].complexChar &&
                                       line[logicalIndex].code > 127 &&
                                       [blockCharacterSet characterIsMember:line[logicalIndex].code]);
        // Foreground colors
        // Build up a compact key describing all the inputs to a text color
        iTermInitializeColorKey(findMatch,
                                inUnderlinedRange,
                                selected,
                                isBlockCharacter,
                                bgColor,
                                &line[logicalIndex],
                                currentColorKey);
        if (logicalIndex > 0 && iTermColorKeysEqual(currentColorKey, previousColorKey)) {
            attributes[visualX].foregroundColor = attributes[previousVisualX].foregroundColor;
        } else {
            vector_float4 textColor = [self textColorForCharacter:&line[logicalIndex]
                                                             line:row
                                                  backgroundColor:attributes[visualX].unprocessedBackgroundColor
                                                         selected:selected
                                                        findMatch:findMatch
                                                inUnderlinedRange:inUnderlinedRange && !annotated
                                           disableMinimumContrast:isBlockCharacter
                                                           caches:&caches];
            attributes[visualX].foregroundColor = textColor;
            attributes[visualX].foregroundColor.w = 1;
        }
        iTermMetalSetUnderline(self,
                               annotated,
                               inUnderlinedRange,
                               underlineHyperlinks,
                               line,
                               currentColorKey,
                               logicalIndex,
                               visualX,
                               url,
                               ea,
                               attributes);

        // Swap current and previous
        iTermTextColorKey *temp = currentColorKey;
        currentColorKey = previousColorKey;
        previousColorKey = temp;

        if (line[logicalIndex].image) {
            iTermGlyphKeyEmitImage(line,
                                   logicalIndex,
                                   row,
                                   ea,
                                   &kittyPlaceholderState,
                                   kittyImageRuns,
                                   kittyImageDraws,
                                   &previousImageCode,
                                   &previousImageCoord,
                                   imageRuns);
            gk = iTermGlyphKeyEmitPlaceholder(glyphKeys, gk, logicalIndex, bidiLUT, bidiLUTLength);
        } else if (attributedString && !isBoxDrawingCharacter) {
            if (!haveEmittedAttributedString) {
                gk = iTermGlyphKeyEmitDecomposed(glyphKeysData,
                                                 !!line[logicalIndex].bold,
                                                 !!line[logicalIndex].italic,
                                                 gk,
                                                 logicalIndex,
                                                 attributedString,
                                                 [self useThinStrokesWithAttributes:&attributes[visualX]],
                                                 &positions,
                                                 bidiLUT,
                                                 bidiLUTLength);
                haveEmittedAttributedString = YES;
            }
        } else if (attributes[visualX].underlineStyle != iTermMetalGlyphAttributesUnderlineNone || characterIsDrawable) {
            lastDrawableGlyph = logicalIndex;
            gk = iTermGlyphKeyEmitRegular(glyphKeys,
                                          gk,
                                          logicalIndex,
                                          width,
                                          characterIsDrawable,
                                          line,
                                          isBoxDrawingCharacter,
                                          [self useThinStrokesWithAttributes:&attributes[visualX]],
                                          bidiLUT,
                                          bidiLUTLength);
        } else {
            iTermGlyphKeyEmitPlaceholder(glyphKeys, gk, logicalIndex, bidiLUT, bidiLUTLength);
        }
        previousVisualX = visualX;
    }

    *drawableGlyphsPtr = lastDrawableGlyph + 1;
    return gk;
}

// Private queue
- (void)metalGetGlyphKeysData:(iTermGlyphKeyData *)glyphKeysData
                glyphKeyCount:(out NSUInteger *)glyphKeyCountPtr
                   attributes:(iTermMetalGlyphAttributes *)attributes
                    imageRuns:(NSMutableArray<iTermMetalImageRun *> *)imageRuns
               kittyImageRuns:(NSMutableArray<iTermKittyImageRun *> *)kittyImageRuns
                   background:(iTermMetalBackgroundColorRLE *)backgroundRLE
                     rleCount:(int *)rleCount
                    markStyle:(out iTermMarkStyle *)markStylePtr
                   hoverState:(out BOOL *)hoverStatePtr
                lineStyleMark:(out nonnull BOOL *)lineStyleMarkPtr
      lineStyleMarkRightInset:(out nonnull int *)lineStyleMarkRightInsetPtr
                          row:(int)row
                        width:(int)width
                     bidiInfo:(iTermBidiDisplayInfo *)bidiInfo
               drawableGlyphs:(int *)drawableGlyphsPtr
                         date:(out NSDate **)datePtr
               belongsToBlock:(out BOOL *)belongsToBlockPtr {
    iTermMetalGlyphKey *glyphKeys = glyphKeysData.basePointer;
    if (_configuration->_timestampsEnabled) {
        *datePtr = _rows[row]->_date;
    }
    *belongsToBlockPtr = _rows[row]->_belongsToBlock;
    ScreenCharArray *lineData = [_rows[row]->_screenCharLine paddedToAtLeastLength:width];
    ITDebugAssert(lineData != nil);
    NSData *findMatches = _rows[row]->_matches;
    NSIndexSet *selectedIndexes = _rows[row]->_selectedIndexSet;
    NSRange underlinedRange = _rows[row]->_underlinedRange;
    NSIndexSet *annotatedIndexes = _rowToAnnotationRanges[@(row)];
    if (VT100GridRangeContains(_linesToSuppressDrawing, row)) {
        lineData = [ScreenCharArray emptyLineOfLength:width];
        findMatches = nil;
        selectedIndexes = nil;
        underlinedRange = NSMakeRange(NSNotFound, 0);
        annotatedIndexes = nil;
    }
    const screen_char_t *const line = (const screen_char_t *const)lineData.line;
    iTermExternalAttributeIndex *eaIndex = _rows[row]->_eaIndex;

    *hoverStatePtr =_rows[row]->_hoverState;
    *markStylePtr = [_rows[row]->_markStyle intValue];
    *lineStyleMarkPtr = _rows[row]->_lineStyleMark;
    *lineStyleMarkRightInsetPtr = _rows[row]->_lineStyleMarkRightInset;
    vector_float4 unprocessedBackgroundColors[width];

    int rles = iTermGetMetalBackgroundColors(self,
                                             line,
                                             backgroundRLE,
                                             attributes,
                                             unprocessedBackgroundColors,
                                             width,
                                             selectedIndexes,
                                             findMatches,
                                             _configuration->_colorMap,
                                             bidiInfo);
    *rleCount = rles;

    CTVector(CGFloat) positions;
    CTVectorCreate(&positions, width);

    NSMutableArray<id<iTermAttributedString>> *allAttributedStrings = nil;

    if (bidiInfo || _configuration->_ligaturesEnabled) {
        allAttributedStrings = [NSMutableArray array];

        for (int i = 0; i < rles; i++) {
            const iTermMetalBackgroundColorRLE *bgrle = &backgroundRLE[i];
            NSColor *bgColor = [NSColor colorWithDisplayP3Red:bgrle->color.x
                                                        green:bgrle->color.y
                                                         blue:bgrle->color.z
                                                        alpha:bgrle->color.w];
            iTermBackgroundColorRun run = {
                .modelRange = NSMakeRange(bgrle->logicalOrigin, bgrle->count),
                .visualRange = NSMakeRange(bgrle->origin, bgrle->count),
                .bgColor = line[bgrle->origin].backgroundColor,
                .bgGreen = line[bgrle->origin].bgGreen,
                .bgBlue = line[bgrle->origin].bgBlue,
                .bgColorMode = line[bgrle->origin].backgroundColorMode,
                .selected = [selectedIndexes containsIndex:bgrle->origin],
                .isMatch = (findMatches &&
                            !run.selected &&
                            CheckFindMatchAtIndex(findMatches, bgrle->origin)),
                .beneathFaintText = line[bgrle->origin].faint
            };
            NSArray<id<iTermAttributedString>> *attributedStrings =
                [_attributedStringBuilder attributedStringsForLine:line
                                                          bidiInfo:bidiInfo
                                                externalAttributes:eaIndex
                                                             range:run.modelRange
                                                   hasSelectedText:selectedIndexes.count > 0
                                                   backgroundColor:bgColor
                                                    forceTextColor:nil
                                                          colorRun:&run
                                                       findMatches:findMatches
                                                   underlinedRange:underlinedRange
                                                         positions:&positions];

            [allAttributedStrings addObjectsFromArray:attributedStrings];
        }
    }

    *glyphKeyCountPtr = iTermEmitGlyphsAndSetAttributes(self,
                                                        line,
                                                        row,
                                                        width,
                                                        allAttributedStrings,
                                                        positions,
                                                        bidiInfo,
                                                        selectedIndexes,
                                                        annotatedIndexes,
                                                        findMatches,
                                                        underlinedRange,
                                                        eaIndex,
                                                        _configuration,
                                                        kittyImageRuns,
                                                        _kittyImageDraws,
                                                        imageRuns,
                                                        glyphKeysData,
                                                        glyphKeys,
                                                        attributes,
                                                        drawableGlyphsPtr);

    // Tweak the text color for the cell that has a box cursor.
    if (row == _cursorInfo.coord.y &&
        _cursorInfo.type == CURSOR_BOX &&
        _cursorInfo.cursorVisible &&
        !_cursorInfo.frameOnly) {
        vector_float4 cursorTextColor;
        if (_cursorInfo.shouldDrawText) {
            cursorTextColor = _cursorInfo.textColor;
        } else if (_configuration->_reverseVideo) {
            cursorTextColor = VectorForColor([_configuration->_colorMap colorForKey:kColorMapBackground],
                                             _configuration->_colorSpace);
        } else {
            cursorTextColor = [self vectorColorForCode:ALTSEM_CURSOR
                                                 green:0
                                                  blue:0
                                             colorMode:ColorModeAlternate
                                                  bold:NO
                                                 faint:NO
                                          isBackground:NO];
        }
        if (_cursorInfo.coord.x < width) {
            attributes[_cursorInfo.coord.x].foregroundColor = cursorTextColor;
            attributes[_cursorInfo.coord.x].foregroundColor.w = 1;
        }
    }
    CTVectorDestroy(&positions);
}

- (BOOL)useThinStrokesWithAttributes:(iTermMetalGlyphAttributes *)attributes {
    switch (_configuration->_thinStrokes) {
        case iTermThinStrokesSettingAlways:
            return YES;

        case iTermThinStrokesSettingDarkBackgroundsOnly:
            break;

        case iTermThinStrokesSettingNever:
            return NO;

        case iTermThinStrokesSettingRetinaDarkBackgroundsOnly:
            if (!_configuration->_isRetina) {
                return NO;
            }
            break;

        case iTermThinStrokesSettingRetinaOnly:
            return _configuration->_isRetina;
    }

    const float backgroundBrightness = SIMDPerceivedBrightness(attributes->backgroundColor);
    const float foregroundBrightness = SIMDPerceivedBrightness(attributes->foregroundColor);
    return backgroundBrightness < foregroundBrightness;
}

- (vector_float4)selectionColorForCurrentFocus {
    if (_configuration->_isFrontTextView) {
        return VectorForColor([_configuration->_colorMap processedBackgroundColorForBackgroundColor:[_configuration->_colorMap colorForKey:kColorMapSelection]],
                              _configuration->_colorSpace);
    } else {
        return _configuration->_unfocusedSelectionColor;
    }
}

- (vector_float4)unprocessedColorForBackgroundColorKey:(iTermBackgroundColorKey *)colorKey
                                             isDefault:(BOOL *)isDefault {
    vector_float4 color = { 0, 0, 0, 0 };
    CGFloat alpha = _configuration->_transparencyAlpha;
    *isDefault = NO;
    if (colorKey->selected) {
        color = [self selectionColorForCurrentFocus];
        if (_configuration->_transparencyAffectsOnlyDefaultBackgroundColor) {
            alpha = 1;
        }
    } else if (colorKey->image) {
        // Recurse to get the default background color
        iTermBackgroundColorKey temp = {
            .bgColor = ALTSEM_DEFAULT,
            .bgGreen = 0,
            .bgBlue = 0,
            .bgColorMode = ColorModeAlternate,
            .selected = NO,
            .isMatch = NO,
            .image = NO,
        };
        return [self unprocessedColorForBackgroundColorKey:&temp isDefault:isDefault];
    } else if (colorKey->isMatch) {
        color = VectorForColor([_configuration->_colorMap colorForKey:kColorMapMatch],
                              _configuration->_colorSpace);
    } else {
        const BOOL defaultBackground = (colorKey->bgColor == ALTSEM_DEFAULT &&
                                        colorKey->bgColorMode == ColorModeAlternate);
        // When set in preferences, applies alpha only to the defaultBackground
        // color, useful for keeping Powerline segments opacity(background)
        // consistent with their seperator glyphs opacity(foreground).
        if (_configuration->_transparencyAffectsOnlyDefaultBackgroundColor && !defaultBackground) {
            alpha = 1;
        }
        if (_configuration->_reverseVideo && defaultBackground) {
            // Reverse video is only applied to default background-
            // color chars.
            color = [self vectorColorForCode:ALTSEM_DEFAULT
                                       green:0
                                        blue:0
                                   colorMode:ColorModeAlternate
                                        bold:NO
                                       faint:NO
                                isBackground:NO];
        } else {
            *isDefault = defaultBackground;
            // Use the regular background color.
            color = [self vectorColorForCode:colorKey->bgColor
                                       green:colorKey->bgGreen
                                        blue:colorKey->bgBlue
                                   colorMode:colorKey->bgColorMode
                                        bold:NO
                                       faint:NO
                                isBackground:YES];
            if (*isDefault) {
                alpha = 0;
            }
        }
    }
    color.w = alpha;
    return color;
}

- (vector_float4)vectorColorForCode:(int)theIndex
                              green:(int)green
                               blue:(int)blue
                          colorMode:(ColorMode)theMode
                               bold:(BOOL)isBold
                              faint:(BOOL)isFaint
                       isBackground:(BOOL)isBackground {
    iTermColorMapKey key = [self colorMapKeyForCode:theIndex
                                              green:green
                                               blue:blue
                                          colorMode:theMode
                                               bold:isBold
                                       isBackground:isBackground];
    if (isBackground) {
        return VectorForColor([_configuration->_colorMap colorForKey:key],
                              _configuration->_colorSpace);
    } else {
        vector_float4 color = VectorForColor([_configuration->_colorMap colorForKey:key],
                                             _configuration->_colorSpace);
        if (isFaint) {
            // TODO: I think this is wrong and the color components need premultiplied alpha.
            color.w = _configuration->_colorMap.faintTextAlpha;
        }
        return color;
    }
}

- (iTermColorMapKey)colorMapKeyForCode:(int)theIndex
                                 green:(int)green
                                  blue:(int)blue
                             colorMode:(ColorMode)theMode
                                  bold:(BOOL)isBold
                          isBackground:(BOOL)isBackground {
    BOOL isBackgroundForDefault = isBackground;
    switch (theMode) {
        case ColorModeAlternate:
            switch (theIndex) {
                case ALTSEM_SELECTED:
                    if (isBackground) {
                        return kColorMapSelection;
                    } else {
                        return kColorMapSelectedText;
                    }
                case ALTSEM_CURSOR:
                    if (isBackground) {
                        return kColorMapCursor;
                    } else {
                        return kColorMapCursorText;
                    }
                case ALTSEM_SYSTEM_MESSAGE:
                    return [_configuration->_colorMap keyForSystemMessageForBackground:isBackground];
                case ALTSEM_REVERSED_DEFAULT:
                    isBackgroundForDefault = !isBackgroundForDefault;
                    // Fall through.
                case ALTSEM_DEFAULT:
                    if (isBackgroundForDefault) {
                        return kColorMapBackground;
                    } else {
                        if (isBold && _configuration->_useCustomBoldColor) {
                            return kColorMapBold;
                        } else {
                            return kColorMapForeground;
                        }
                    }
            }
            break;
        case ColorMode24bit:
            return [iTermColorMap keyFor8bitRed:theIndex green:green blue:blue];
        case ColorModeNormal:
            // Render bold text as bright. The spec (ECMA-48) describes the intense
            // display setting (esc[1m) as "bold or bright". We make it a
            // preference.
            if (isBold &&
                _configuration->_brightenBold &&
                (theIndex < 8) &&
                !isBackground) { // Only colors 0-7 can be made "bright".
                theIndex |= 8;  // set "bright" bit.
            }
            return kColorMap8bitBase + (theIndex & 0xff);

        case ColorModeInvalid:
            return kColorMapInvalid;
    }
    ITAssertWithMessage(ok, @"Bogus color mode %d", (int)theMode);
    return kColorMapInvalid;
}

- (id)metalASCIICreationIdentifierWithOffset:(CGSize)asciiOffset {
    return @{ @"font": _configuration->_fontTable.uniqueIdentifier ?: [NSNull null],
              @"useBold": @(_configuration->_useBoldFont),
              @"useItalic": @(_configuration->_useItalicFont),
              @"asciiAntialiased": @(_configuration->_asciiAntialias),
              @"nonasciiAntialiased": @(_configuration->_nonasciiAntialias),
              @"asciiOffset": @(asciiOffset), };
}

- (nullable NSDictionary<NSNumber *, iTermCharacterBitmap *> *)metalImagesForGlyphKey:(iTermMetalGlyphKey *)glyphKey
                                                                          asciiOffset:(CGSize)asciiOffset
                                                                                 size:(CGSize)size
                                                                                scale:(CGFloat)scale
                                                                                emoji:(nonnull BOOL *)emoji {
    switch (glyphKey->type) {
        case iTermMetalGlyphTypeRegular:
            return [self imagesForRegularGlyphKey:glyphKey
                                      asciiOffset:asciiOffset
                                             size:size
                                            scale:scale
                                            emoji:emoji];
        case iTermMetalGlyphTypeDecomposed:
            return [self imagesForDecomposedGlyphKey:glyphKey
                                                size:size
                                               scale:scale
                                               emoji:emoji];
    }
}

- (nullable NSDictionary<NSNumber *, iTermCharacterBitmap *> *)imagesForDecomposedGlyphKey:(iTermMetalGlyphKey *)glyphKey
                                                                                      size:(CGSize)size
                                                                                     scale:(CGFloat)scale
                                                                                     emoji:(nonnull BOOL *)emoji {
    const BOOL bold = !!(glyphKey->typeface & iTermMetalGlyphKeyTypefaceBold);
    const BOOL italic = !!(glyphKey->typeface & iTermMetalGlyphKeyTypefaceItalic);
    const int radius = iTermTextureMapMaxCharacterParts / 2;
    iTermCharacterSourceDescriptor *descriptor =
    [iTermCharacterSourceDescriptor characterSourceDescriptorWithFontTable:_configuration->_fontTable
                                                               asciiOffset:CGSizeZero
                                                                 glyphSize:size
                                                                  cellSize:_configuration->_cellSize
                                                    cellSizeWithoutSpacing:_configuration->_cellSizeWithoutSpacing
                                                                     scale:scale
                                                               useBoldFont:_configuration->_useBoldFont
                                                             useItalicFont:_configuration->_useItalicFont
                                                          usesNonAsciiFont:_configuration->_useNonAsciiFont
                                                          asciiAntiAliased:_configuration->_asciiAntialias
                                                       nonAsciiAntiAliased:_configuration->_nonasciiAntialias];
    iTermCharacterSourceAttributes *attributes =
    [iTermCharacterSourceAttributes characterSourceAttributesWithThinStrokes:glyphKey->thinStrokes
                                                                        bold:bold
                                                                      italic:italic];
    iTermCharacterSource *characterSource =
    [[iTermCharacterSource alloc] initWithFontID:glyphKey->payload.decomposed.fontID
                                        fakeBold:glyphKey->payload.decomposed.fakeBold
                                      fakeItalic:glyphKey->payload.decomposed.fakeItalic
                                     glyphNumber:glyphKey->payload.decomposed.glyphNumber
                                        position:glyphKey->payload.decomposed.position
                                      descriptor:descriptor
                                      attributes:attributes
                                          radius:radius
                                         context:_metalContext];
    if (characterSource == nil) {
        return nil;
    }
    NSMutableDictionary<NSNumber *, iTermCharacterBitmap *> *result = [NSMutableDictionary dictionary];
    [characterSource.parts enumerateObjectsUsingBlock:^(NSNumber * _Nonnull partNumber, NSUInteger idx, BOOL * _Nonnull stop) {
        int part = partNumber.intValue;
        result[partNumber] = [characterSource bitmapForPart:part];
    }];
    if (emoji) {
        *emoji = characterSource.isEmoji;
    }
    return result;
}

- (nullable NSDictionary<NSNumber *, iTermCharacterBitmap *> *)imagesForRegularGlyphKey:(iTermMetalGlyphKey *)glyphKey
                                                                            asciiOffset:(CGSize)asciiOffset
                                                                                   size:(CGSize)size
                                                                                  scale:(CGFloat)scale
                                                                                  emoji:(nonnull BOOL *)emoji {
    const BOOL bold = !!(glyphKey->typeface & iTermMetalGlyphKeyTypefaceBold);
    const BOOL italic = !!(glyphKey->typeface & iTermMetalGlyphKeyTypefaceItalic);
    const BOOL isAscii = !glyphKey->payload.regular.isComplex && (glyphKey->payload.regular.code < 128);

    const int radius = iTermTextureMapMaxCharacterParts / 2;
    iTermCharacterSourceDescriptor *descriptor =
    [iTermCharacterSourceDescriptor characterSourceDescriptorWithFontTable:_configuration->_fontTable
                                                               asciiOffset:asciiOffset
                                                                 glyphSize:size
                                                                  cellSize:_configuration->_cellSize
                                                    cellSizeWithoutSpacing:_configuration->_cellSizeWithoutSpacing
                                                                     scale:scale
                                                               useBoldFont:_configuration->_useBoldFont
                                                             useItalicFont:_configuration->_useItalicFont
                                                          usesNonAsciiFont:_configuration->_useNonAsciiFont
                                                          asciiAntiAliased:_configuration->_asciiAntialias
                                                       nonAsciiAntiAliased:_configuration->_nonasciiAntialias];
    iTermCharacterSourceAttributes *attributes =
    [iTermCharacterSourceAttributes characterSourceAttributesWithThinStrokes:glyphKey->thinStrokes
                                                                        bold:bold
                                                                      italic:italic];
    NSString *string = CharToStr(glyphKey->payload.regular.code, glyphKey->payload.regular.isComplex);
    if (glyphKey->payload.regular.combiningSuccessor) {
        if (ComplexCharCodeIsSpacingCombiningMark(glyphKey->payload.regular.combiningSuccessor) &&
            !(glyphKey->payload.regular.isComplex && ComplexCharCodeIsSpacingCombiningMark(glyphKey->payload.regular.code))) {
            // Append the successor cell's spacing combining mark, provided it has a predecessor.
            NSString *successorString = CharToStr(glyphKey->payload.regular.combiningSuccessor, YES);
            string = [string stringByAppendingString:successorString];
        }
    }
    iTermCharacterSource *characterSource =
    [[iTermCharacterSource alloc] initWithCharacter:string
                                         descriptor:descriptor
                                         attributes:attributes
                                         boxDrawing:glyphKey->payload.regular.boxDrawing
                                             radius:radius
                           useNativePowerlineGlyphs:_configuration->_useNativePowerlineGlyphs
                                            context:_metalContext];
    if (characterSource == nil) {
        return nil;
    }

    NSMutableDictionary<NSNumber *, iTermCharacterBitmap *> *result = [NSMutableDictionary dictionary];
    [characterSource.parts enumerateObjectsUsingBlock:^(NSNumber * _Nonnull partNumber, NSUInteger idx, BOOL * _Nonnull stop) {
        int part = partNumber.intValue;
        if (isAscii &&
            part != iTermImagePartFromDeltas(0, 0) &&
            part != iTermImagePartFromDeltas(-1, 0) &&
            part != iTermImagePartFromDeltas(1, 0)) {
            return;
        }
        result[partNumber] = [characterSource bitmapForPart:part];
    }];
    if (emoji) {
        *emoji = characterSource.isEmoji;
    }
    return result;
}

- (void)metalGetUnderlineDescriptorsForASCII:(out iTermMetalUnderlineDescriptor *)ascii
                                    nonASCII:(out iTermMetalUnderlineDescriptor *)nonAscii
                               strikethrough:(out iTermMetalUnderlineDescriptor *)strikethrough {
    *ascii = _configuration->_asciiUnderlineDescriptor;
    *nonAscii = _configuration->_nonAsciiUnderlineDescriptor;
    *strikethrough = _configuration->_strikethroughUnderlineDescriptor;
}

// Use 24-bit color to set the text and background color of a cell.
- (void)setTextColor:(vector_float4)textColor
     backgroundColor:(vector_float4)backgroundColor
             atCoord:(VT100GridCoord)coord
               lines:(screen_char_t *)lines
            gridSize:(VT100GridSize)gridSize {
    if (coord.x < 0 || coord.y < 0 || coord.x >= gridSize.width || coord.y >= gridSize.height) {
        return;
    }
    screen_char_t *c = &lines[coord.x + coord.y * (gridSize.width + 1)];
    c->foregroundColorMode = ColorMode24bit;
    c->foregroundColor = textColor.x * 255;
    c->fgGreen = textColor.y * 255;
    c->fgBlue = textColor.z * 255;

    c->backgroundColorMode = ColorMode24bit;
    c->backgroundColor = backgroundColor.x * 255;
    c->bgGreen = backgroundColor.y * 255;
    c->bgBlue = backgroundColor.z * 255;
}

- (void)setDebugString:(NSString *)debugString {
    NSMutableData *mutableData NS_VALID_UNTIL_END_OF_SCOPE;
    mutableData = [_rows[0]->_screenCharLine mutableLineData];
    screen_char_t *line = (screen_char_t *)mutableData.mutableBytes;
    for (int i = 0, o = MAX(0, _configuration->_gridSize.width - (int)debugString.length);
         i < debugString.length && o < _configuration->_gridSize.width;
         i++, o++) {
        [self setTextColor:simd_make_float4(1, 0, 1, 1)
           backgroundColor:simd_make_float4(0.1, 0.1, 0.1, 1)
                   atCoord:VT100GridCoordMake(o, 0)
                     lines:line
                  gridSize:_configuration->_gridSize];
        line[o].code = [debugString characterAtIndex:i];
    }
    _rows[0]->_screenCharLine = [[ScreenCharArray alloc] initWithData:mutableData
                                                             metadata:_rows[0]->_screenCharLine.metadata
                                                         continuation:_rows[0]->_screenCharLine.continuation];
}

- (id)screenCharArrayForRow:(int)y {
    return _rows[y]->_screenCharLine;
}

- (CGRect)containerRect {
    return _containerRect;
}

- (NSRect)adjustedDocumentVisibleRect {
    return _adjustedDocumentVisibleRect;
}

- (long long)totalScrollbackOverflow {
    return _totalScrollbackOverflow;
}

- (CGRect)relativeFrame {
    return NSMakeRect(_relativeFrame.origin.x,
                      1 - _relativeFrame.size.height - _relativeFrame.origin.y,
                      _relativeFrame.size.width,
                      _relativeFrame.size.height);
}

- (NSArray<iTermKittyImageDraw *> *)kittyImageDraws {
    return _kittyImageDraws;
}

- (NSEdgeInsets)extraMargins {
    return _extraMargins;
}

- (BOOL)thinStrokesForTimestamps {
    switch (_configuration->_thinStrokes) {
        case iTermThinStrokesSettingNever:
            return NO;
        case iTermThinStrokesSettingAlways:
            return YES;
        case iTermThinStrokesSettingRetinaOnly:
            return _configuration->_isRetina;
        case iTermThinStrokesSettingDarkBackgroundsOnly:
            return self.timestampsBackgroundColor.isDark;
        case iTermThinStrokesSettingRetinaDarkBackgroundsOnly:
            return _configuration->_isRetina && self.timestampsBackgroundColor.isDark;
    }
}

- (BOOL)asciiAntiAliased {
    return _configuration->_asciiAntialias;
}

- (NSFont *)timestampFont {
    return _configuration->_timestampFont;
}

#pragma mark - Color

- (vector_float4)textColorForCharacter:(const screen_char_t *const)c
                                  line:(int)line
                       backgroundColor:(vector_float4)unprocessedBackgroundColor
                              selected:(BOOL)selected
                             findMatch:(BOOL)findMatch
                     inUnderlinedRange:(BOOL)inUnderlinedRange
                disableMinimumContrast:(BOOL)disableMinimumContrast
                                caches:(iTermMetalPerFrameStateCaches *)caches {
    vector_float4 rawColor = { 0, 0, 0, 0 };
    iTermColorMap *colorMap = _configuration->_colorMap;
    const BOOL needsProcessing = (colorMap.minimumContrast > 0.001 ||
                                  colorMap.dimmingAmount > 0.001 ||
                                  colorMap.mutingAmount > 0.001 ||
                                  c->faint);  // faint implies alpha<1 and is faster than getting the alpha component


    if (findMatch) {
        // Black-on-yellow search result.
        NSColor *bgColor = [_configuration->_colorMap colorForKey:kColorMapMatch];
        rawColor = VectorForColor(iTermTextDrawingHelperTextColorForMatch(bgColor),
                                  _configuration->_colorSpace);
        caches->havePreviousCharacterAttributes = NO;
    } else if (inUnderlinedRange) {
        // Blue link text.
        rawColor = VectorForColor([_configuration->_colorMap colorForKey:kColorMapLink],
                                  _configuration->_colorSpace);
        caches->havePreviousCharacterAttributes = NO;
    } else if (selected && _configuration->_useSelectedTextColor) {
        // Selected text.
        rawColor = VectorForColor([colorMap colorForKey:kColorMapSelectedText],
                                  _configuration->_colorSpace);
        caches->havePreviousCharacterAttributes = NO;
    } else if (_configuration->_reverseVideo &&
               ((c->foregroundColor == ALTSEM_DEFAULT && c->foregroundColorMode == ColorModeAlternate) ||
                (c->foregroundColor == ALTSEM_CURSOR && c->foregroundColorMode == ColorModeAlternate))) {
           // Reverse video is on. Either is cursor or has default foreground color. Use
           // background color.
           rawColor = VectorForColor([colorMap colorForKey:kColorMapBackground],
                                     _configuration->_colorSpace);
           caches->havePreviousCharacterAttributes = NO;
    } else if (!caches->havePreviousCharacterAttributes ||
               c->foregroundColor != caches->previousCharacterAttributes.foregroundColor ||
               c->fgGreen != caches->previousCharacterAttributes.fgGreen ||
               c->fgBlue != caches->previousCharacterAttributes.fgBlue ||
               c->foregroundColorMode != caches->previousCharacterAttributes.foregroundColorMode ||
               c->bold != caches->previousCharacterAttributes.bold ||
               c->faint != caches->previousCharacterAttributes.faint ||
               !caches->havePreviousForegroundColor) {
        // "Normal" case for uncached text color. Recompute the unprocessed color from the character.
        caches->previousCharacterAttributes = *c;
        caches->havePreviousCharacterAttributes = YES;
        rawColor = [self vectorColorForCode:c->foregroundColor
                                      green:c->fgGreen
                                       blue:c->fgBlue
                                  colorMode:c->foregroundColorMode
                                       bold:c->bold
                                      faint:c->faint
                               isBackground:NO];
    } else {
        // Foreground attributes are just like the last character. There is a cached foreground color.
        if (needsProcessing) {
            // Process the text color for the current background color, which has changed since
            // the last cell.
            rawColor = caches->lastUnprocessedColor;
        } else {
            // Text color is unchanged. Either it's independent of the background color or the
            // background color has not changed.
            return caches->previousForegroundColor;
        }
    }

    caches->lastUnprocessedColor = rawColor;

    vector_float4 result;
    if (needsProcessing) {
      result = VectorForColor([_configuration->_colorMap processedTextColorForTextColor:ColorForVector(rawColor)
                                                                    overBackgroundColor:ColorForVector(unprocessedBackgroundColor)
                                                                 disableMinimumContrast:disableMinimumContrast],
                              _configuration->_colorSpace);
    } else {
        result = rawColor;
    }
    caches->previousForegroundColor = result;
    caches->havePreviousForegroundColor = YES;
    return result;
}

- (NSColor *)backgroundColorForCursor {
    NSColor *color;
    if (_configuration->_reverseVideo) {
        color = [[_configuration->_colorMap colorForKey:kColorMapCursorText] colorWithAlphaComponent:1.0];
    } else {
        color = [[_configuration->_colorMap colorForKey:kColorMapCursor] colorWithAlphaComponent:1.0];
    }
    return [_configuration->_colorMap colorByDimmingTextColor:color];
}

#pragma mark - iTermSmartCursorColorDelegate

- (iTermCursorNeighbors)cursorNeighbors {
    return [iTermSmartCursorColor neighborsForCursorAtCoord:_cursorInfo.coord
                                                   gridSize:_configuration->_gridSize
                                                 lineSource:^const screen_char_t *(int y) {
        const int i = y + self->_numberOfScrollbackLines - self->_visibleRange.start.y;
        if (i >= 0 && i < self->_rows.count) {
            return (const screen_char_t *)self->_rows[i]->_screenCharLine.line;
        } else {
            return nil;
        }
    }];
}

- (vector_float4)fastCursorColorForCharacter:(screen_char_t)screenChar
                              wantBackground:(BOOL)wantBackgroundColor
                                       muted:(BOOL)muted {
    BOOL isBackground = [iTermTextDrawingHelper cursorUsesBackgroundColorForScreenChar:screenChar
                                                                        wantBackground:wantBackgroundColor
                                                                          reverseVideo:_configuration->_reverseVideo];

    vector_float4 color;
    if (wantBackgroundColor) {
        color = [self vectorColorForCode:screenChar.backgroundColor
                                   green:screenChar.bgGreen
                                    blue:screenChar.bgBlue
                               colorMode:screenChar.backgroundColorMode
                                    bold:screenChar.bold
                                   faint:screenChar.faint
                            isBackground:isBackground];
    } else {
        color = [self vectorColorForCode:screenChar.foregroundColor
                                   green:screenChar.fgGreen
                                    blue:screenChar.fgBlue
                               colorMode:screenChar.foregroundColorMode
                                    bold:screenChar.bold
                                   faint:screenChar.faint
                            isBackground:isBackground];
    }
    if (muted) {
        color = [_configuration->_colorMap fastColorByMutingColor:color];
    }
    return color;
}

- (NSColor *)cursorColorForCharacter:(screen_char_t)screenChar
                      wantBackground:(BOOL)wantBackgroundColor
                               muted:(BOOL)muted {
    vector_float4 v = [self fastCursorColorForCharacter:screenChar wantBackground:wantBackgroundColor muted:muted];
    return [NSColor colorWithRed:v.x green:v.y blue:v.z alpha:v.w];
}

- (NSColor *)cursorColorByDimmingSmartColor:(NSColor *)color {
    return [_configuration->_colorMap colorByDimmingTextColor:color];
}

- (NSColor *)cursorWhiteColor {
    NSColor *whiteColor = [NSColor colorWithCalibratedRed:1
                                                    green:1
                                                     blue:1
                                                    alpha:1];
    return [_configuration->_colorMap colorByDimmingTextColor:whiteColor];
}

- (NSColor *)cursorBlackColor {
    NSColor *blackColor = [NSColor colorWithCalibratedRed:0
                                                    green:0
                                                     blue:0
                                                    alpha:1];
    return [_configuration->_colorMap colorByDimmingTextColor:blackColor];
}

#pragma mark - Cursor Logic

- (BOOL)shouldDrawCursor {
    BOOL hideCursorBecauseBlinking = [self hideCursorBecauseBlinking];

    // Draw the regular cursor only if there's not an IME open as it draws its
    // own cursor. Also, it must be not blinked-out, and it must be within the expected bounds of
    // the screen (which is just a sanity check, really).
    BOOL result = (![self hasMarkedText] &&
                   _cursorVisible &&
                   !hideCursorBecauseBlinking);
    DLog(@"shouldDrawCursor: hasMarkedText=%d, cursorVisible=%d, hideCursorBecauseBlinking=%d, result=%@",
         (int)[self hasMarkedText], (int)_cursorVisible, (int)hideCursorBecauseBlinking, @(result));
    return result;
}

- (BOOL)hideCursorBecauseBlinking {
    if (_cursorBlinking &&
        _configuration->_isInKeyWindow &&
        _configuration->_textViewIsActiveSession &&
        _configuration->_textViewIsFirstResponder &&
        _timeSinceCursorMoved > 0.5) {
        // Allow the cursor to blink if it is configured, the window is key, this session is active
        // in the tab, and the cursor has not moved for half a second.
        return !_configuration->_blinkingItemsVisible;
    } else {
        return NO;
    }
}

- (BOOL)hasMarkedText {
    return _inputMethodMarkedRange.length > 0;
}

- (NSArray<iTermTerminalButton *> *)terminalButtons NS_AVAILABLE_MAC(11) {
    return _configuration->_terminalButtons;
}

#pragma mark - iTermAttributedStringBuilderDelegate

- (BOOL)useSelectedTextColor {
    return _configuration->_useSelectedTextColor;
}

// I believe this is never called because we always set the background color in the text context.
// It is used in an optimization in the legacy renderer and we have to implement it to satisfy
// protocol conformance.
- (NSColor *)unprocessedColorForBackgroundRun:(const iTermBackgroundColorRun *)run
                               enableBlending:(BOOL)enableBlending {
    iTermBackgroundColorKey backgroundKey = {
        .bgColor = run->bgColor,
        .bgGreen = run->bgGreen,
        .bgBlue = run->bgBlue,
        .bgColorMode = run->bgColorMode,
        .selected = run->selected,
        .isMatch = run->isMatch,
        .image = NO
    };
    BOOL isDefault;

    vector_float4 v = [self unprocessedColorForBackgroundColorKey:&backgroundKey isDefault:&isDefault];
    return [NSColor colorWithDisplayP3Red:v.x
                                    green:v.y
                                     blue:v.z
                                    alpha:v.w];
}

- (NSColor *)colorForCode:(int)theIndex green:(int)green blue:(int)blue colorMode:(ColorMode)theMode bold:(BOOL)isBold faint:(BOOL)isFaint isBackground:(BOOL)isBackground {
    vector_float4 color = [self vectorColorForCode:theIndex
                                             green:green
                                              blue:blue
                                         colorMode:theMode
                                              bold:isBold
                                             faint:isFaint
                                      isBackground:isBackground];
    return [NSColor colorWithDisplayP3Red:color.x
                                    green:color.y
                                     blue:color.z
                                    alpha:color.w];
}
@end

NS_ASSUME_NONNULL_END
