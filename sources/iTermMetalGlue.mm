//
//  iTermMetalGlue.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/8/17.
//

#import "iTermMetalGlue.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermBoxDrawingBezierCurveFactory.h"
#import "iTermCharacterSource.h"
#import "iTermColorMap.h"
#import "iTermController.h"
#import "iTermData.h"
#import "iTermImageInfo.h"
#import "iTermMarkRenderer.h"
#import "iTermSelection.h"
#import "iTermSharedColor.h"
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

// Set the `index`th bit in an unsigned char array, `array`.
static inline void iTermSetBit(unsigned char *array, int index) {
    array[index / 8] |= (1 << (index & 7));
}

NS_ASSUME_NONNULL_BEGIN

extern void CGContextSetFontSmoothingStyle(CGContextRef, int);
extern int CGContextGetFontSmoothingStyle(CGContextRef);

static vector_float4 VectorForColor(NSColor *color) {
    return simd_make_float4(color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent);
}

static NSColor *ColorForVector(vector_float4 v) {
    return [NSColor colorWithRed:v.x green:v.y blue:v.z alpha:v.w];
}

static inline BOOL CanTakeASCIIFastPath(const screen_char_t &c) {
    return (c.code <= iTermASCIITextureMaximumCharacter &&
            !c.complexChar);
}

static void HandleImage(const screen_char_t &c,
                        const int &x,
                        const int &row,
                        NSMutableArray<iTermMetalImageRun *> *imageRuns,
                        int *previousImageCodePtr,
                        VT100GridCoord *previousImageCoordPtr,
                        iTermMetalGlyphKey *glyphKey) {
    if (c.code == *previousImageCodePtr &&
        c.foregroundColor == previousImageCoordPtr->x + 1 &&
        c.backgroundColor == previousImageCoordPtr->y) {
        imageRuns.lastObject.length = imageRuns.lastObject.length + 1;
        previousImageCoordPtr->x++;
    } else {
        *previousImageCodePtr = c.code;
        iTermMetalImageRun *run = [[iTermMetalImageRun alloc] init];
        *previousImageCoordPtr = GetPositionOfImageInChar(c);
        run.code = c.code;
        run.startingCoordInImage = *previousImageCoordPtr;
        run.startingCoordOnScreen = VT100GridCoordMake(x, row);
        run.length = 1;
        run.imageInfo = GetImageInfo(c.code);
        [imageRuns addObject:run];
    }
    glyphKey->drawable = NO;
}

static void HandleGlyph(const screen_char_t &c,
                        int x,
                        const iTermThinStrokesSetting &thinStrokes,
                        const BOOL &isRetina,
                        int *lastDrawableGlyphPtr,
                        iTermMetalGlyphKey *glyphKey) {
    static dispatch_once_t onceToken;
    static NSCharacterSet *boxCharacterSet;
    dispatch_once(&onceToken, ^{
        boxCharacterSet = [iTermBoxDrawingBezierCurveFactory boxDrawingCharactersWithBezierPaths];
    });
    *lastDrawableGlyphPtr = x;
    glyphKey->code = c.code;
    glyphKey->isComplex = c.complexChar;
    glyphKey->boxDrawing = !c.complexChar && [boxCharacterSet characterIsMember:c.code];
    glyphKey->thinStrokes = false;

    const int boldBit = c.bold ? (1 << 0) : 0;
    const int italicBit = c.italic ? (1 << 1) : 0;
    glyphKey->typeface = (boldBit | italicBit);
    glyphKey->drawable = YES;
}

@interface iTermMetalGlue()
// Screen-relative cursor location on last frame
@property (nonatomic) VT100GridCoord oldCursorScreenCoord;
// Used to remember the last time the cursor moved to avoid drawing a blinked-out
// cursor while it's moving.
@property (nonatomic) NSTimeInterval lastTimeCursorMoved;
@end

@interface iTermMetalPerFrameState : NSObject<
    iTermMetalDriverDataSourcePerFrameState,
    iTermSmartCursorColorDelegate> {
    BOOL _havePreviousCharacterAttributes;
    screen_char_t _previousCharacterAttributes;
    vector_float4 _lastUnprocessedColor;
    BOOL _havePreviousForegroundColor;
    vector_float4 _previousForegroundColor;
    NSMutableArray<iTermData *> *_lines;
    NSMutableArray<NSDate *> *_dates;
    NSMutableArray<NSIndexSet *> *_selectedIndexes;
    NSMutableDictionary<NSNumber *, NSData *> *_matches;
    NSMutableDictionary<NSNumber *, NSValue *> *_underlinedRanges;
    iTermColorMap *_colorMap;
    PTYFontInfo *_asciiFont;
    PTYFontInfo *_nonAsciiFont;
    BOOL _useBoldFont;
    BOOL _useItalicFont;
    BOOL _useNonAsciiFont;
    BOOL _reverseVideo;
    BOOL _useBrightBold;
    BOOL _isFrontTextView;
    vector_float4 _unfocusedSelectionColor;
    CGFloat _transparencyAlpha;
    BOOL _transparencyAffectsOnlyDefaultBackgroundColor;
    iTermMetalCursorInfo *_cursorInfo;
    iTermThinStrokesSetting _thinStrokes;
    BOOL _isRetina;
    BOOL _isInKeyWindow;
    BOOL _textViewIsActiveSession;
    BOOL _shouldDrawFilledInCursor;
    VT100GridSize _gridSize;
    VT100GridCoordRange _visibleRange;
    NSInteger _numberOfScrollbackLines;
    BOOL _cursorVisible;
    BOOL _cursorBlinking;
    BOOL _blinkingItemsVisible;
    BOOL _blinkAllowed;
    NSRange _inputMethodMarkedRange;
    NSTimeInterval _timeSinceCursorMoved;

    CGFloat _backgroundImageBlending;
    BOOL _backgroundImageTiled;
    NSImage *_backgroundImage;
    BOOL _asciiAntialias;
    BOOL _nonasciiAntialias;
    iTermMetalUnderlineDescriptor _asciiUnderlineDescriptor;
    iTermMetalUnderlineDescriptor _nonAsciiUnderlineDescriptor;
    NSImage *_badgeImage;
    CGRect _badgeSourceRect;
    CGRect _badgeDestinationRect;
    CGRect _documentVisibleRect;
    iTermMetalIMEInfo *_imeInfo;
    BOOL _showBroadcastStripes;
    NSMutableArray<NSNumber *> *_markStyles;
    BOOL _cursorGuideEnabled;
    NSColor *_cursorGuideColor;
    NSMutableArray<iTermIndicatorDescriptor *> *_indicators;
    vector_float4 _fullScreenFlashColor;
    NSColor *_processedDefaultBackgroundColor;  // dimmed, etc.
    BOOL _timestampsEnabled;
    long long _firstVisibleAbsoluteLineNumber;
    long long _lastVisibleAbsoluteLineNumber;

    // Row on screen to characters with annotation underline on that row.
    NSDictionary<NSNumber *, NSIndexSet *> *_rowToAnnotationRanges;
    NSArray<iTermHighlightedRow *> *_highlightedRows;
    NSTimeInterval _startTime;
    NSData *_serializedColorMap;
    BOOL _hasBackgroundImage;
    iTermData *_concatenatedLines;
}

@property (nonatomic, readonly) BOOL isAnimating;
@property (nonatomic, readonly) CGSize cellSize;
@property (nonatomic, readonly) CGSize cellSizeWithoutSpacing;
@property (nonatomic, readonly) CGFloat scale;

- (instancetype)initWithTextView:(PTYTextView *)textView
                          screen:(VT100Screen *)screen
                            glue:(iTermMetalGlue *)glue NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@implementation iTermMetalGlue {
    NSMutableSet<NSString *> *_missingImages;
    NSMutableSet<NSString *> *_loadedImages;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(imageDidLoad:)
                                                     name:iTermImageDidLoad
                                                   object:nil];
        _missingImages = [NSMutableSet set];
        _loadedImages = [NSMutableSet set];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)imageDidLoad:(NSNotification *)notification {
    iTermImageInfo *image = notification.object;
    [_loadedImages addObject:image.uniqueIdentifier];
    if ([self missingImageIsVisible:image]) {
        [_textView setNeedsDisplay:YES];
    }
}

#pragma mark - Private

- (BOOL)missingImageIsVisible:(iTermImageInfo *)image {
    if (![_missingImages containsObject:image.uniqueIdentifier]) {
        return NO;
    }
    return [_textView imageIsVisible:image];
}

#pragma mark - iTermMetalDriverDataSource

- (nullable id<iTermMetalDriverDataSourcePerFrameState>)metalDriverWillBeginDrawingFrame {
    if (self.textView.drawingHelper.delegate == nil) {
        return nil;
    }
    return [[iTermMetalPerFrameState alloc] initWithTextView:self.textView screen:self.screen glue:self];
}

- (void)metalDidFindImages:(NSSet<NSString *> *)foundImages
             missingImages:(NSSet<NSString *> *)missingImages
            animatedLines:(NSSet<NSNumber *> *)animatedLines {
    dispatch_async(dispatch_get_main_queue(), ^{
        [_missingImages unionSet:missingImages];
        [_missingImages minusSet:foundImages];
        if (animatedLines.count) {
            _textView.drawingHelper.animated = YES;
        }
        int width = _textView.dataSource.width;
        long long offset = _textView.dataSource.totalScrollbackOverflow;
        for (NSNumber *absoluteLine in animatedLines) {
            long long abs = absoluteLine.longLongValue;
            if (abs >= offset) {
                int row = abs - offset;
                [_textView.dataSource setRangeOfCharsAnimated:NSMakeRange(0, width) onLine:row];
            }
        }
        NSMutableSet<NSString *> *newlyLoaded = [_missingImages mutableCopy];
        [newlyLoaded intersectSet:_loadedImages];
        if (newlyLoaded.count) {
            [_textView setNeedsDisplay:YES];
            [_missingImages minusSet:_loadedImages];
        }
    });
}

- (void)metalDriverDidDrawFrame:(id<iTermMetalDriverDataSourcePerFrameState>)perFrameState {
    // Don't invoke the callback if geometry has changed.
    iTermMetalPerFrameState *state = (iTermMetalPerFrameState *)perFrameState;
    if (!VT100GridSizeEquals(state.gridSize, VT100GridSizeMake(_textView.dataSource.width,
                                                               _textView.dataSource.height))) {
        return;
    }
    if (!CGSizeEqualToSize(state.cellSize,
                           CGSizeMake(_textView.charWidth, _textView.lineHeight))) {
        return;
    }
    if (state.scale != _textView.window.backingScaleFactor) {
        return;
    }
    [self.delegate metalGlueDidDrawFrameAndNeedsRedraw:state.isAnimating];
}

- (void)metalDriverDidProduceDebugInfo:(nonnull NSData *)archive {
    [archive writeToFile:@"/tmp/iTerm2-frame-capture.zip" atomically:NO];
}


@end

#pragma mark -

@implementation iTermMetalPerFrameState

- (instancetype)initWithTextView:(PTYTextView *)textView
                          screen:(VT100Screen *)screen
                            glue:(iTermMetalGlue *)glue {
    assert([NSThread isMainThread]);
    self = [super init];
    if (self) {
        _startTime = [NSDate timeIntervalSinceReferenceDate];

        // Getting the drawingHelper may reset the cursorVisible flag as a side effect of the
        // hacky flicker fixer.
        BOOL savedCursorVisible = textView.cursorVisible;
        iTermTextDrawingHelper *drawingHelper = textView.drawingHelper;
        _cursorVisible = drawingHelper.cursorVisible;
        drawingHelper.cursorVisible = savedCursorVisible;

        // Copy lines from model. Always use these for consistency. I should also copy the color map
        // and any other data dependencies.
        _lines = [NSMutableArray array];
        _dates = [NSMutableArray array];
        _markStyles = [NSMutableArray array];
        _selectedIndexes = [NSMutableArray array];
        _matches = [NSMutableDictionary dictionary];
        _underlinedRanges = [NSMutableDictionary dictionary];

        [self loadMetricsWithDrawingHelper:drawingHelper textView:textView screen:screen];
        [self loadSettingsWithDrawingHelper:drawingHelper textView:textView];
        [self loadLinesWithDrawingHelper:drawingHelper textView:textView screen:screen];
        [self loadBadgeWithDrawingHelper:drawingHelper textView:textView];
        [self loadBlinkingCursorWithTextView:textView glue:glue];
        [self loadCursorInfoWithDrawingHelper:drawingHelper textView:textView];
        [self loadCursorGuideWithDrawingHelper:drawingHelper];
        [self loadBackgroundImageWithTextView:textView];
        [self loadUnderlineDescriptorsWithDrawingHelper:drawingHelper];
        [self loadMarkedTextWithDrawingHelper:drawingHelper];
        [self loadIndicatorsFromTextView:textView];
        [self loadHighlightedRowsFromTextView:textView];
        [self loadAnnotationRangesFromTextView:textView];

        [textView.dataSource setUseSavedGridIfAvailable:NO];
    }
    return self;
}

- (void)loadMetricsWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper
                            textView:(PTYTextView *)textView
                              screen:(VT100Screen *)screen {
    _gridSize = VT100GridSizeMake(textView.dataSource.width,
                                  textView.dataSource.height);
    _cellSize = drawingHelper.cellSize;
    _cellSizeWithoutSpacing = drawingHelper.cellSizeWithoutSpacing;
    _scale = textView.window.backingScaleFactor;
    _documentVisibleRect = textView.enclosingScrollView.documentVisibleRect;

    _visibleRange = [drawingHelper coordRangeForRect:_documentVisibleRect];
    _visibleRange.start.x = MAX(0, _visibleRange.start.x);
    _visibleRange.start.y = MAX(0, _visibleRange.start.y);
    _visibleRange.end.x = _visibleRange.start.x + _gridSize.width;
    _visibleRange.end.y = _visibleRange.start.y + _gridSize.height;
    const long long totalScrollbackOverflow = [screen totalScrollbackOverflow];
    _firstVisibleAbsoluteLineNumber = _visibleRange.start.y + totalScrollbackOverflow;
    _lastVisibleAbsoluteLineNumber = _visibleRange.end.y + totalScrollbackOverflow;
}

- (void)loadSettingsWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper
                             textView:(PTYTextView *)textView {
    _serializedColorMap = textView.colorMap.serializedData;  // Do this before copying so it can cache the serialized data which changes infrequently.
    _colorMap = [textView.colorMap copy];
    _asciiFont = textView.primaryFont;
    _nonAsciiFont = textView.secondaryFont;
    _useBoldFont = textView.useBoldFont;
    _useItalicFont = textView.useItalicFont;
    _useNonAsciiFont = textView.useNonAsciiFont;
    _reverseVideo = textView.dataSource.terminal.reverseVideo;
    _useBrightBold = textView.useBrightBold;
    _thinStrokes = textView.thinStrokes;
    _isRetina = drawingHelper.isRetina;
    _isInKeyWindow = [textView isInKeyWindow];
    _textViewIsActiveSession = [textView.delegate textViewIsActiveSession];
    _shouldDrawFilledInCursor = ([textView.delegate textViewShouldDrawFilledInCursor] || textView.keyFocusStolenCount);
    _numberOfScrollbackLines = textView.dataSource.numberOfScrollbackLines;
    _cursorBlinking = textView.isCursorBlinking;
    _blinkAllowed = textView.blinkAllowed;
    _blinkingItemsVisible = drawingHelper.blinkingItemsVisible;
    _inputMethodMarkedRange = drawingHelper.inputMethodMarkedRange;
    _asciiAntialias = drawingHelper.asciiAntiAlias;
    _nonasciiAntialias = drawingHelper.nonAsciiAntiAlias;
    _showBroadcastStripes = drawingHelper.showStripes;
    _processedDefaultBackgroundColor = [drawingHelper defaultBackgroundColor];
    _timestampsEnabled = drawingHelper.showTimestamps;
    _isFrontTextView = (textView == [[iTermController sharedInstance] frontTextView]);
    _unfocusedSelectionColor = VectorForColor([[_colorMap colorForKey:kColorMapSelection] colorDimmedBy:2.0/3.0
                                                                                       towardsGrayLevel:0.5]);
    _transparencyAlpha = textView.transparencyAlpha;
    _transparencyAffectsOnlyDefaultBackgroundColor = drawingHelper.transparencyAffectsOnlyDefaultBackgroundColor;
    _hasBackgroundImage = drawingHelper.hasBackgroundImage;
}

- (void)loadLinesWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper
                          textView:(PTYTextView *)textView
                            screen:(VT100Screen *)screen {
    const int width = _visibleRange.end.x - _visibleRange.start.x;
    const int height = _visibleRange.end.y - _visibleRange.start.y;
    const BOOL allowOtherMarkStyle = [iTermAdvancedSettingsModel showYellowMarkForJobStoppedBySignal];
    const long long totalScrollbackOverflow = [screen totalScrollbackOverflow];

    // newBufferWithBytesNoCopy: wants a page-aligned pointer.
    _concatenatedLines = [iTermData pageAlignedUninitializeDataOfLength:(width + 1) * height * sizeof(screen_char_t)];
    const size_t rowSize = sizeof(screen_char_t) * (width + 1);
    NSUInteger offset = 0;
    const NSUInteger stride = (width + 1) * sizeof(screen_char_t);
    unsigned char *concatenatedBytes = static_cast<unsigned char *>(_concatenatedLines.mutableBytes);

    for (int i = _visibleRange.start.y; i < _visibleRange.end.y; i++, offset += stride) {
        if (_timestampsEnabled) {
            [_dates addObject:[textView drawingHelperTimestampForLine:i]];
        }
        iTermData *data = [iTermData unownedDataWithBytes:concatenatedBytes + offset
                                                   length:stride];
        screen_char_t *myBuffer = reinterpret_cast<screen_char_t *>(data.mutableBytes);
        screen_char_t *line = [screen getLineAtIndex:i withBuffer:myBuffer];
        if (line != myBuffer) {
            memcpy(myBuffer, line, rowSize);
        }
        [_lines addObject:data];

        [_selectedIndexes addObject:[textView.selection selectedIndexesOnLine:i]];
        NSData *findMatches = [drawingHelper.delegate drawingHelperMatchesOnLine:i];
        if (findMatches) {
            _matches[@(i - _visibleRange.start.y)] = findMatches;
        }

        const long long absoluteLine = totalScrollbackOverflow + i;
        _underlinedRanges[@(i - _visibleRange.start.y)] = [NSValue valueWithRange:[drawingHelper underlinedRangeOnLine:absoluteLine]];

        [self loadMarksWithDrawingHelper:drawingHelper
                                textView:textView
                                    line:i
                     allowOtherMarkStyle:allowOtherMarkStyle];
    }
}

- (void)loadBadgeWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper
                          textView:(PTYTextView *)textView {
    _badgeImage = drawingHelper.badgeImage;
    if (_badgeImage) {
        _badgeDestinationRect = [iTermTextDrawingHelper rectForBadgeImageOfSize:_badgeImage.size
                                                                destinationRect:textView.enclosingScrollView.documentVisibleRect
                                                           destinationFrameSize:textView.frame.size
                                                                    visibleSize:textView.enclosingScrollView.documentVisibleRect.size
                                                                  sourceRectPtr:&_badgeSourceRect];
    }
}

- (void)loadBlinkingCursorWithTextView:(PTYTextView *)textView
                                  glue:(iTermMetalGlue *)glue {
    VT100GridCoord cursorScreenCoord = VT100GridCoordMake(textView.dataSource.cursorX - 1,
                                                          textView.dataSource.cursorY - 1);
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!VT100GridCoordEquals(cursorScreenCoord, glue.oldCursorScreenCoord)) {
        glue.lastTimeCursorMoved = now;
    }
    _timeSinceCursorMoved = now - glue.lastTimeCursorMoved;
    glue.oldCursorScreenCoord = cursorScreenCoord;
}

- (void)loadCursorInfoWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper
                               textView:(PTYTextView *)textView {
    const int offset = _visibleRange.start.y - _numberOfScrollbackLines;
    _cursorInfo = [[iTermMetalCursorInfo alloc] init];
    _cursorInfo.copyMode = drawingHelper.copyMode;
    _cursorInfo.copyModeCursorCoord = VT100GridCoordMake(drawingHelper.copyModeCursorCoord.x,
                                                         drawingHelper.copyModeCursorCoord.y - _visibleRange.start.y);
    _cursorInfo.copyModeCursorSelecting = drawingHelper.copyModeSelecting;
    _cursorInfo.coord = VT100GridCoordMake(textView.dataSource.cursorX - 1,
                                           textView.dataSource.cursorY - 1 - offset);
    NSInteger lineWithCursor = textView.dataSource.cursorY - 1 + _numberOfScrollbackLines;
    if ([self shouldDrawCursor] &&
        _cursorVisible &&
        _visibleRange.start.y <= lineWithCursor &&
        lineWithCursor < _visibleRange.end.y) {
        _cursorInfo.cursorVisible = YES;
        _cursorInfo.type = drawingHelper.cursorType;
        _cursorInfo.cursorColor = [self backgroundColorForCursor];
        if (_cursorInfo.type == CURSOR_BOX) {
            _cursorInfo.shouldDrawText = YES;
            const screen_char_t *line = (screen_char_t *)_lines[_cursorInfo.coord.y].mutableBytes;
            screen_char_t screenChar = line[_cursorInfo.coord.x];
            const BOOL focused = ((_isInKeyWindow && _textViewIsActiveSession) || _shouldDrawFilledInCursor);

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
                if (_reverseVideo) {
                    _cursorInfo.textColor = [_colorMap fastColorForKey:kColorMapBackground];
                } else {
                    _cursorInfo.textColor = [self colorForCode:ALTSEM_CURSOR
                                                         green:0
                                                          blue:0
                                                     colorMode:ColorModeAlternate
                                                          bold:NO
                                                         faint:NO
                                                  isBackground:NO];
                }
            }
        }
    } else {
        _cursorInfo.cursorVisible = NO;
    }
}

- (void)loadCursorGuideWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper {
    _cursorGuideEnabled = drawingHelper.highlightCursorLine;
    _cursorGuideColor = drawingHelper.cursorGuideColor;
}

- (void)loadBackgroundImageWithTextView:(PTYTextView *)textView {
    _backgroundImageBlending = textView.blend;
    _backgroundImageTiled = textView.delegate.backgroundImageTiled;
    _backgroundImage = [textView.delegate textViewBackgroundImage];
}

- (void)loadUnderlineDescriptorsWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper {
    _asciiUnderlineDescriptor.color = VectorForColor([_colorMap colorForKey:kColorMapUnderline]);
    _asciiUnderlineDescriptor.offset = [drawingHelper yOriginForUnderlineGivenFontXHeight:_asciiFont.font.xHeight yOffset:0];
    _asciiUnderlineDescriptor.thickness = [drawingHelper underlineThicknessForFont:_asciiFont.font];

    _nonAsciiUnderlineDescriptor.color = _asciiUnderlineDescriptor.color;
    _nonAsciiUnderlineDescriptor.offset = [drawingHelper yOriginForUnderlineGivenFontXHeight:_nonAsciiFont.font.xHeight yOffset:0];
    _nonAsciiUnderlineDescriptor.thickness = [drawingHelper underlineThicknessForFont:_nonAsciiFont.font];
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
            numberOfIMELines:drawingHelper.numberOfIMELines];
    }
}

- (void)loadHighlightedRowsFromTextView:(PTYTextView *)textView {
    _highlightedRows = [textView.highlightedRows copy];
}

- (void)loadMarksWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper
                          textView:(PTYTextView *)textView
                              line:(int)i
               allowOtherMarkStyle:(BOOL)allowOtherMarkStyle {
    iTermMarkStyle markStyle = iTermMarkStyleNone;
    if (drawingHelper.drawMarkIndicators) {
        VT100ScreenMark *mark = [textView.dataSource markOnLine:i];
        if (mark.isVisible) {
            if (mark.code == 0) {
                markStyle = iTermMarkStyleSuccess;
            } else if (allowOtherMarkStyle &&
                       mark.code >= 128 && mark.code <= 128 + 32) {
                markStyle = iTermMarkStyleOther;
            } else {
                markStyle = iTermMarkStyleFailure;
            }
        }
    }
    [_markStyles addObject:@(markStyle)];
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
            dict[@(second.intValue - _visibleRange.start.y)] = indexes;
        }
        return dict;
    }];
}

- (void)loadIndicatorsFromTextView:(PTYTextView *)textView {
    _indicators = [NSMutableArray array];
    NSRect frame = NSMakeRect(0, 0, textView.visibleRect.size.width, textView.visibleRect.size.height);
    [textView.indicatorsHelper enumerateTopRightIndicatorsInFrame:frame block:^(NSString *identifier, NSImage *image, NSRect rect) {
        rect.origin.y = frame.size.height - NSMaxY(rect);
        iTermIndicatorDescriptor *indicator = [[iTermIndicatorDescriptor alloc] init];
        indicator.identifier = identifier;
        indicator.image = image;
        indicator.frame = rect;
        indicator.alpha = 0.5;
        [_indicators addObject:indicator];
    }];
    [textView.indicatorsHelper enumerateCenterIndicatorsInFrame:frame block:^(NSString *identifier, NSImage *image, NSRect rect, CGFloat alpha) {
        rect.origin.y = frame.size.height - NSMaxY(rect);
        iTermIndicatorDescriptor *indicator = [[iTermIndicatorDescriptor alloc] init];
        indicator.identifier = identifier;
        indicator.image = image;
        indicator.frame = rect;
        indicator.alpha = alpha;
        [_indicators addObject:indicator];
    }];
    [textView.indicatorsHelper didDraw];
    NSColor *color = [[textView indicatorFullScreenFlashColor] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    _fullScreenFlashColor = simd_make_float4(color.redComponent,
                                             color.greenComponent,
                                             color.blueComponent,
                                             textView.indicatorsHelper.fullScreenAlpha);
}

- (iTermASCIIRow *)asciiRowAtIndex:(NSUInteger)index {
    iTermASCIIRow *row = [[iTermASCIIRow alloc] init];
    row.screenChars = _lines[index];
    return row;
}

- (void)getConfiguration:(iTermColorsConfiguration *)configurationPtr {
    configurationPtr->scale = _scale;
    configurationPtr->gridSize = simd_make_uint2(_gridSize.width, _gridSize.height);
    configurationPtr->minimumContrast = _colorMap.minimumContrast;
    configurationPtr->dimmingAmount = _colorMap.dimmingAmount;
    configurationPtr->mutingAmount = _colorMap.mutingAmount;
    configurationPtr->reverseVideo = _reverseVideo;
    configurationPtr->useBrightBold = _useBrightBold;
    configurationPtr->transparencyAlpha = _transparencyAlpha;
    configurationPtr->transparencyAffectsOnlyDefaultBackgroundColor = _transparencyAffectsOnlyDefaultBackgroundColor;
    configurationPtr->unfocusedSelectionColor = _unfocusedSelectionColor;
    configurationPtr->isFrontTextView = _isFrontTextView;
    configurationPtr->dimOnlyText = _colorMap.dimOnlyText;
    // Both ascii and non-ascii descriptors will have the same color, as there is only one setting for both.
    configurationPtr->underlineColor = _asciiUnderlineDescriptor.color;
    configurationPtr->thinStrokesSetting = _thinStrokes;
    configurationPtr->hasBackgroundImage = _hasBackgroundImage;
    configurationPtr->blend = _backgroundImageBlending;
}

- (void)copyMarkedText:(NSString *)str
        cursorLocation:(int)cursorLocation
                    to:(VT100GridCoord)startCoord
ambiguousIsDoubleWidth:(BOOL)ambiguousIsDoubleWidth
         normalization:(iTermUnicodeNormalization)normalization
        unicodeVersion:(NSInteger)unicodeVersion
             gridWidth:(int)gridWidth
      numberOfIMELines:(int)numberOfIMELines {
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
                        unicodeVersion);
    VT100GridCoord coord = startCoord;
    coord.y -= numberOfIMELines;
    BOOL foundCursor = NO;
    BOOL justWrapped = NO;
    BOOL foundStart = NO;
    _imeInfo = [[iTermMetalIMEInfo alloc] init];
    for (int i = 0; i < len; i++) {
        if (coord.y >= 0 && coord.y < _lines.count) {
            if (i == cursorIndex) {
                foundCursor = YES;
                _imeInfo.cursorCoord = coord;
            }
            screen_char_t *line = (screen_char_t *)_lines[coord.y].mutableBytes;
            screen_char_t c = buf[i];
            c.foregroundColor = iTermIMEColor.x * 255;
            c.fgGreen = iTermIMEColor.y * 255;
            c.fgBlue = iTermIMEColor.z * 255;
            c.foregroundColorMode = ColorMode24bit;

            c.backgroundColor = ALTSEM_DEFAULT;
            c.bgGreen = 0;
            c.bgBlue = 0;
            c.backgroundColorMode = ColorModeAlternate;

            c.underline = YES;

            if (i + 1 < len &&
                coord.x == gridWidth -1 &&
                line[i+1].code == DWC_RIGHT &&
                !line[i+1].complexChar) {
                // Bump DWC to start of next line instead of splitting it
                c.code = ' ';
                c.complexChar = NO;
                i--;
            } else {
                if (!foundStart) {
                    foundStart = YES;
                    [_imeInfo setRangeStart:coord];
                }
                line[coord.x] = c;
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
    return _timestampsEnabled;
}

- (NSColor *)timestampsTextColor {
    assert(_timestampsEnabled);
    return [_colorMap colorForKey:kColorMapForeground];
}

- (NSColor *)timestampsBackgroundColor {
    assert(_timestampsEnabled);
    return _processedDefaultBackgroundColor;
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
    return _fullScreenFlashColor;
}

- (BOOL)cursorGuideEnabled {
    return _cursorGuideColor && _cursorGuideEnabled;
}

- (NSColor *)cursorGuideColor {
    return _cursorGuideColor;
}

- (BOOL)showBroadcastStripes {
    return _showBroadcastStripes;
}

- (nullable iTermMetalIMEInfo *)imeInfo {
    return _imeInfo;
}

- (CGRect)badgeSourceRect {
    return _badgeSourceRect;
}

- (CGRect)badgeDestinationRect {
    CGRect rect = _badgeDestinationRect;
    rect.origin.x -= _documentVisibleRect.origin.x;
    rect.origin.y -= _documentVisibleRect.origin.y;
    return rect;
}

- (NSImage *)badgeImage {
    return _badgeImage;
}

- (VT100GridSize)gridSize {
    return _gridSize;
}

- (vector_float4)defaultBackgroundColor {
    NSColor *color = [_colorMap colorForKey:kColorMapBackground];
    return simd_make_float4((float)color.redComponent,
                            (float)color.greenComponent,
                            (float)color.blueComponent,
                            1);
}

- (vector_float4)processedDefaultBackgroundColor {
    return simd_make_float4((float)_processedDefaultBackgroundColor.redComponent,
                            (float)_processedDefaultBackgroundColor.greenComponent,
                            (float)_processedDefaultBackgroundColor.blueComponent,
                            _backgroundImage ? 1 - _backgroundImageBlending : 1);
}

// Private queue
- (nullable iTermMetalCursorInfo *)metalDriverCursorInfo {
    return _cursorInfo;
}

// Private queue
- (NSImage *)metalBackgroundImageGetTiled:(nullable BOOL *)tiled {
    if (tiled) {
        *tiled = _backgroundImageTiled;
    }
    return _backgroundImage;
}

// Private queue
- (void)metalGetGlyphKeys:(iTermMetalGlyphKey *)glyphKeys
                imageRuns:(NSMutableArray<iTermMetalImageRun *> *)imageRuns
                markStyle:(out iTermMarkStyle *)markStylePtr
                      row:(int)row
                    width:(int)width
           drawableGlyphs:(int *)drawableGlyphsPtr
                     date:(out NSDate **)datePtr {
    if (_timestampsEnabled) {
        *datePtr = _dates[row];
    }
    screen_char_t *line = (screen_char_t *)_lines[row].mutableBytes;
    int previousImageCode = -1;
    VT100GridCoord previousImageCoord;

    *markStylePtr = static_cast<iTermMarkStyle>([_markStyles[row] intValue]);
    int lastDrawableGlyph = -1;
    NSIndexSet *annotatedIndexes = _rowToAnnotationRanges[@(row)];
    for (int x = 0; x < width; x++) {
        if (line[x].image) {
            HandleImage(line[x],
                        x,
                        row,
                        imageRuns,
                        &previousImageCode,
                        &previousImageCoord,
                        &glyphKeys[x]);
        } else if (CanTakeASCIIFastPath(line[x])) {
            glyphKeys[x].drawable = NO;
        } else if ([annotatedIndexes containsIndex:x] ||
                   iTermTextDrawingHelperIsCharacterDrawable(&line[x],
                                                             line[x].complexChar && (ScreenCharToStr(&line[x]) != nil),
                                                             _blinkingItemsVisible,
                                                             _blinkAllowed)) {
            HandleGlyph(line[x],
                        x,
                        _thinStrokes,
                        _isRetina,
                        &lastDrawableGlyph,
                        &glyphKeys[x]);
        } else {
            glyphKeys[x].drawable = NO;
        }
    }
    *drawableGlyphsPtr = lastDrawableGlyph + 1;
}

- (vector_float4)colorForCode:(int)theIndex
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
        return VectorForColor([_colorMap colorForKey:key]);
    } else {
        vector_float4 color = VectorForColor([_colorMap colorForKey:key]);
        if (isFaint) {
            color.w = 0.5;
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
                case ALTSEM_REVERSED_DEFAULT:
                    isBackgroundForDefault = !isBackgroundForDefault;
                    // Fall through.
                case ALTSEM_DEFAULT:
                    if (isBackgroundForDefault) {
                        return kColorMapBackground;
                    } else {
                        if (isBold && _useBrightBold) {
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
                _useBrightBold &&
                (theIndex < 8) &&
                !isBackground) { // Only colors 0-7 can be made "bright".
                theIndex |= 8;  // set "bright" bit.
            }
            return static_cast<iTermColorMapKey>(kColorMap8bitBase + (theIndex & 0xff));

        case ColorModeInvalid:
            return kColorMapInvalid;
    }
    NSAssert(ok, @"Bogus color mode %d", (int)theMode);
    return kColorMapInvalid;
}

- (id)metalASCIICreationIdentifier {
    return @{ @"font": _asciiFont.font ?: [NSNull null],
              @"boldFont": _asciiFont.boldVersion ?: [NSNull null],
              @"boldItalicFont": _asciiFont.boldItalicVersion ?: [NSNull null],
              @"useBold": @(_useBoldFont),
              @"useItalic": @(_useItalicFont),
              @"asciiAntialiased": @(_asciiAntialias),
              @"nonasciiAntialiased": @(_nonasciiAntialias) };
}

- (NSDictionary<NSNumber *, iTermCharacterBitmap *> *)metalImagesForGlyphKey:(iTermMetalGlyphKey *)glyphKey
                                                                        size:(CGSize)size
                                                                       scale:(CGFloat)scale
                                                                       emoji:(nonnull BOOL *)emoji {
    if (glyphKey->boxDrawing) {
        *emoji = NO;
        iTermCharacterBitmap *bitmap = [self bitmapForBoxDrawingCode:glyphKey->code size:size scale:scale];
        return @{ @(iTermTextureMapMiddleCharacterPart): bitmap };
    }

    // Normal path
    BOOL fakeBold = !!(glyphKey->typeface & iTermMetalGlyphKeyTypefaceBold);
    BOOL fakeItalic = !!(glyphKey->typeface & iTermMetalGlyphKeyTypefaceItalic);
    const BOOL isAscii = !glyphKey->isComplex && (glyphKey->code < 128);
    PTYFontInfo *fontInfo = [PTYFontInfo fontForAsciiCharacter:isAscii
                                                     asciiFont:_asciiFont
                                                  nonAsciiFont:_nonAsciiFont
                                                   useBoldFont:_useBoldFont
                                                 useItalicFont:_useItalicFont
                                              usesNonAsciiFont:_useNonAsciiFont
                                                    renderBold:&fakeBold
                                                  renderItalic:&fakeItalic];
    NSFont *font = fontInfo.font;
    assert(font);

    iTermCharacterSource *characterSource =
        [[iTermCharacterSource alloc] initWithCharacter:CharToStr(glyphKey->code, glyphKey->isComplex)
                                                   font:font
                                                   size:size
                                         baselineOffset:fontInfo.baselineOffset
                                                  scale:scale
                                         useThinStrokes:glyphKey->thinStrokes
                                               fakeBold:fakeBold
                                             fakeItalic:fakeItalic
                                            antialiased:isAscii ? _asciiAntialias : _nonasciiAntialias];
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

- (void)metalGetUnderlineDescriptorsForASCII:(out iTermMetalUnderlineDescriptor *)ascii
                                    nonASCII:(out iTermMetalUnderlineDescriptor *)nonAscii {
    *ascii = _asciiUnderlineDescriptor;
    *nonAscii = _nonAsciiUnderlineDescriptor;
}

- (NSData *)colorMap {
    return _serializedColorMap;
}

- (vector_float4)textColorForCharacter:(screen_char_t *)c
                                  line:(int)line
                       backgroundColor:(vector_float4)backgroundColor
                              selected:(BOOL)selected
                             findMatch:(BOOL)findMatch
                     inUnderlinedRange:(BOOL)inUnderlinedRange
                                 index:(int)index {
    vector_float4 rawColor = { 0, 0, 0, 0 };
    iTermColorMap *colorMap = _colorMap;
    const BOOL needsProcessing = (colorMap.minimumContrast > 0.001 ||
                                  colorMap.dimmingAmount > 0.001 ||
                                  colorMap.mutingAmount > 0.001 ||
                                  c->faint);  // faint implies alpha<1 and is faster than getting the alpha component


    if (findMatch) {
        // Black-on-yellow search result.
        rawColor = (vector_float4){ 0, 0, 0, 1 };
        _havePreviousCharacterAttributes = NO;
    } else if (inUnderlinedRange) {
        // Blue link text.
        rawColor = VectorForColor([_colorMap colorForKey:kColorMapLink]);
        _havePreviousCharacterAttributes = NO;
    } else if (selected) {
        // Selected text.
        rawColor = VectorForColor([colorMap colorForKey:kColorMapSelectedText]);
        _havePreviousCharacterAttributes = NO;
    } else if (_reverseVideo &&
               ((c->foregroundColor == ALTSEM_DEFAULT && c->foregroundColorMode == ColorModeAlternate) ||
                (c->foregroundColor == ALTSEM_CURSOR && c->foregroundColorMode == ColorModeAlternate))) {
           // Reverse video is on. Either is cursor or has default foreground color. Use
           // background color.
           rawColor = VectorForColor([colorMap colorForKey:kColorMapBackground]);
           _havePreviousCharacterAttributes = NO;
    } else if (!_havePreviousCharacterAttributes ||
               c->foregroundColor != _previousCharacterAttributes.foregroundColor ||
               c->fgGreen != _previousCharacterAttributes.fgGreen ||
               c->fgBlue != _previousCharacterAttributes.fgBlue ||
               c->foregroundColorMode != _previousCharacterAttributes.foregroundColorMode ||
               c->bold != _previousCharacterAttributes.bold ||
               c->faint != _previousCharacterAttributes.faint ||
               !_havePreviousForegroundColor) {
        // "Normal" case for uncached text color. Recompute the unprocessed color from the character.
        _previousCharacterAttributes = *c;
        _havePreviousCharacterAttributes = YES;
        rawColor = [self colorForCode:c->foregroundColor
                                green:c->fgGreen
                                 blue:c->fgBlue
                            colorMode:static_cast<ColorMode>(c->foregroundColorMode)
                                 bold:c->bold
                                faint:c->faint
                         isBackground:NO];
    } else {
        // Foreground attributes are just like the last character. There is a cached foreground color.
        if (needsProcessing) {
            // Process the text color for the current background color, which has changed since
            // the last cell.
            rawColor = _lastUnprocessedColor;
        } else {
            // Text color is unchanged. Either it's independent of the background color or the
            // background color has not changed.
            return _previousForegroundColor;
        }
    }

    _lastUnprocessedColor = rawColor;

    vector_float4 result;
    if (needsProcessing) {
        result = VectorForColor([_colorMap processedTextColorForTextColor:ColorForVector(rawColor)
                                                      overBackgroundColor:ColorForVector(backgroundColor)]);
    } else {
        result = rawColor;
    }
    _previousForegroundColor = result;
    _havePreviousForegroundColor = YES;
    return result;
}

#pragma mark - Color

- (NSColor *)backgroundColorForCursor {
    NSColor *color;
    if (_reverseVideo) {
        color = [[_colorMap colorForKey:kColorMapCursorText] colorWithAlphaComponent:1.0];
    } else {
        color = [[_colorMap colorForKey:kColorMapCursor] colorWithAlphaComponent:1.0];
    }
    return [_colorMap colorByDimmingTextColor:color];
}

- (iTermData *)dataForIndexSetArray:(NSArray<NSIndexSet *> *)indexSetArray {
    const int bitsPerLine = _gridSize.width;
    iTermData *data = [iTermData dataOfLength:(bitsPerLine * _gridSize.height + 8) / 8];
    bzero(data.mutableBytes, data.length);
    [indexSetArray enumerateObjectsUsingBlock:^(NSIndexSet * _Nonnull indexSet, NSUInteger y, BOOL * _Nonnull stop) {
        const int offset = y * bitsPerLine;
        [indexSet enumerateIndexesUsingBlock:^(NSUInteger x, BOOL * _Nonnull stop) {
            iTermSetBit(data.mutableBytes, x + offset);
        }];
    }];
    return data;
}

- (iTermData *)dataForIndexSetDictionary:(NSDictionary<NSNumber *, NSIndexSet *> *)indexSetDictionary {
    int stride = (_gridSize.width + 8) / 8;
    iTermData *data = [iTermData dataOfLength:stride * _gridSize.height];
    bzero(data.mutableBytes, data.length);
    [indexSetDictionary enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull yNumber, NSIndexSet * _Nonnull indexSet, BOOL * _Nonnull stop) {
        unsigned char *line = data.mutableBytes + yNumber.integerValue * stride;
        [indexSet enumerateIndexesUsingBlock:^(NSUInteger x, BOOL * _Nonnull stop) {
            iTermSetBit(line, x);
        }];
    }];
    return data;
}

- (iTermData *)dataForDataDictionary:(NSDictionary<NSNumber *, NSData *> *)dataDictionary {
    int stride = (_gridSize.width + 8) / 8;
    iTermData *data = [iTermData dataOfLength:stride * _gridSize.height];
    bzero(data.mutableBytes, data.length);
    [dataDictionary enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull yNumber, NSData * _Nonnull source, BOOL * _Nonnull stop) {
        ITBetaAssert(source.length == stride, @"Length/stride mismatch");
        unsigned char *line = data.mutableBytes + yNumber.integerValue * stride;
        memmove(line, source.bytes, source.length);
    }];
    return data;
}

- (iTermData *)dataForRangeDictionary:(NSDictionary<NSNumber *, NSValue *> *)rangeDictionary {
    int stride = (_gridSize.width + 8) / 8;
    iTermData *data = [iTermData dataOfLength:stride * _gridSize.height];
    bzero(data.mutableBytes, data.length);
    [rangeDictionary enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull yNumber, NSValue * _Nonnull rangeValue, BOOL * _Nonnull stop) {
        unsigned char *line = data.mutableBytes + yNumber.integerValue * stride;
        NSRange range = rangeValue.rangeValue;
        for (NSUInteger i = 0; i < range.length; i++) {
            iTermSetBit(line, i + range.location);
        }
    }];
    return data;
}

- (iTermData *)concatenatedLines {
    return _concatenatedLines;
}

- (iTermData *)selectedIndices {
    return [self dataForIndexSetArray:_selectedIndexes];
}

- (iTermData *)findMatches {
    return [self dataForDataDictionary:_matches];
}

- (iTermData *)annotatedIndices {
    return [self dataForIndexSetDictionary:_rowToAnnotationRanges];
}

- (iTermData *)markedIndices {
    NSMutableArray<NSIndexSet *> *indexSetArray = [NSMutableArray array];
    for (int i = 0; i < _gridSize.height; i++) {
        NSRange range = _imeInfo ? [_imeInfo markedRangeOnLine:i width:_gridSize.width] : NSMakeRange(NSNotFound, 0);
        NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:range];
        [indexSetArray addObject:indexSet];
    }
    return [self dataForIndexSetArray:indexSetArray];
}

- (iTermData *)underlinedIndices {
    return [self dataForRangeDictionary:_underlinedRanges];
}

#pragma mark - Box Drawing

- (iTermCharacterBitmap *)bitmapForBoxDrawingCode:(unichar)code
                                             size:(CGSize)size
                                            scale:(CGFloat)scale {
    NSColor *backgroundColor = [NSColor whiteColor];
    NSColor *foregroundColor = [NSColor blackColor];
    NSMutableData *data = [NSImage argbDataForImageOfSize:size drawBlock:^(CGContextRef context) {
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform concat];

        for (NSBezierPath *path in [iTermBoxDrawingBezierCurveFactory bezierPathsForBoxDrawingCode:code
                                                                                          cellSize:size
                                                                                             scale:scale]) {
            [backgroundColor set];
            NSRectFill(NSMakeRect(0, 0, size.width, size.height));

            [foregroundColor set];
            [path setLineWidth:scale];
            [path stroke];
        }
    }];

    iTermCharacterBitmap *bitmap = [[iTermCharacterBitmap alloc] init];
    bitmap.data = data;
    bitmap.size = size;
    return bitmap;
}

#pragma mark - iTermSmartCursorColorDelegate

- (iTermCursorNeighbors)cursorNeighbors {
    return [iTermSmartCursorColor neighborsForCursorAtCoord:_cursorInfo.coord
                                                   gridSize:_gridSize
                                                 lineSource:^screen_char_t *(int y) {
                                                     const int i = y + _numberOfScrollbackLines - _visibleRange.start.y;
                                                     if (i >= 0 && i < _lines.count) {
                                                         return (screen_char_t *)_lines[i].mutableBytes;
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
                                                                          reverseVideo:_reverseVideo];

    vector_float4 color;
    if (wantBackgroundColor) {
        color = [self colorForCode:screenChar.backgroundColor
                             green:screenChar.bgGreen
                              blue:screenChar.bgBlue
                         colorMode:static_cast<ColorMode>(screenChar.backgroundColorMode)
                              bold:screenChar.bold
                             faint:screenChar.faint
                      isBackground:isBackground];
    } else {
        color = [self colorForCode:screenChar.foregroundColor
                             green:screenChar.fgGreen
                              blue:screenChar.fgBlue
                         colorMode:static_cast<ColorMode>(screenChar.foregroundColorMode)
                              bold:screenChar.bold
                             faint:screenChar.faint
                      isBackground:isBackground];
    }
    if (muted) {
        color = [_colorMap fastColorByMutingColor:color];
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
    return [_colorMap colorByDimmingTextColor:color];
}

- (NSColor *)cursorWhiteColor {
    NSColor *whiteColor = [NSColor colorWithCalibratedRed:1
                                                    green:1
                                                     blue:1
                                                    alpha:1];
    return [_colorMap colorByDimmingTextColor:whiteColor];
}

- (NSColor *)cursorBlackColor {
    NSColor *blackColor = [NSColor colorWithCalibratedRed:0
                                                    green:0
                                                     blue:0
                                                    alpha:1];
    return [_colorMap colorByDimmingTextColor:blackColor];
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
        _isInKeyWindow &&
        _textViewIsActiveSession &&
        _timeSinceCursorMoved > 0.5) {
        // Allow the cursor to blink if it is configured, the window is key, this session is active
        // in the tab, and the cursor has not moved for half a second.
        return !_blinkingItemsVisible;
    } else {
        return NO;
    }
}

- (BOOL)hasMarkedText {
    return _inputMethodMarkedRange.length > 0;
}


@end

NS_ASSUME_NONNULL_END
