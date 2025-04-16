//
//  iTermTextDrawingHelper.m
//  iTerm2
//
//  Created by George Nachman on 3/9/15.
//
//

#import "iTermTextDrawingHelper.h"

#import "charmaps.h"
#import "CVector.h"
#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAttributedStringBuilder.h"
#import "iTermAttributedStringProxy.h"
#import "iTermBackgroundColorRun.h"
#import "iTermBoxDrawingBezierCurveFactory.h"
#import "iTermColorMap.h"
#import "iTermController.h"
#import "iTermCoreTextLineRenderingHelper.h"
#import "iTermFindCursorView.h"
#import "iTermGraphicsUtilities.h"
#import "iTermImageInfo.h"
#import "iTermIndicatorsHelper.h"
#import "iTermMutableAttributedStringBuilder.h"
#import "iTermPreciseTimer.h"
#import "iTermPreferences.h"
#import "iTermSelection.h"
#import "iTermTextExtractor.h"
#import "iTermTimestampDrawHelper.h"
#import "iTermVirtualOffset.h"
#import "MovingAverage.h"
#import "NSArray+iTerm.h"
#import "NSCharacterSet+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSStringITerm.h"
#import "NSView+iTerm.h"
#import "PTYFontInfo.h"
#import "RegexKitLite.h"
#import "ScreenCharArray.h"
#import "VT100ScreenMark.h"
#import "VT100Terminal.h"  // TODO: Remove this dependency

#define MEDIAN(min_, mid_, max_) MAX(MIN(mid_, max_), min_)

typedef struct {
    NSInteger minValue;
    NSInteger halfOpenUpperBound;
} iTermSignedRange;

static BOOL iTermSignedRangeContainsValue(iTermSignedRange range, NSInteger value) {
    return value >= range.minValue && value < range.halfOpenUpperBound;
}

// Not inclusive of maxValue
static iTermSignedRange iTermSignedRangeWithBounds(NSInteger minValue, NSInteger halfOpenUpperBound) {
    return (iTermSignedRange) { .minValue = minValue, .halfOpenUpperBound = halfOpenUpperBound };
}

static const int kBadgeMargin = 4;
const CGFloat iTermOffscreenCommandLineVerticalPadding = 8.0;

extern void CGContextSetFontSmoothingStyle(CGContextRef, int);
extern int CGContextGetFontSmoothingStyle(CGContextRef);
const int iTermTextDrawingHelperLineStyleMarkRightInsetCells = 15;

typedef struct {
    CGContextRef maskGraphicsContext;
    CGImageRef alphaMask;
} iTermUnderlineContext;

BOOL CheckFindMatchAtIndex(NSData *findMatches, int index) {
    int theIndex = index / 8;
    int mask = 1 << (index & 7);
    const char *matchBytes = findMatches.bytes;
    return !!(theIndex < [findMatches length] && (matchBytes[theIndex] & mask));
}

@interface iTermTextDrawingHelper() <iTermCursorDelegate, iTermAttributedStringBuilderDelegate>
@end

enum {
    TIMER_TOTAL_DRAW_RECT,
    TIMER_CONSTRUCT_BACKGROUND_RUNS,
    TIMER_DRAW_BACKGROUND,

    TIMER_STAT_CONSTRUCTION,
    TIMER_STAT_BUILD_MUTABLE_ATTRIBUTED_STRING,
    TIMER_ATTRS_FOR_CHAR,
    TIMER_SHOULD_SEGMENT,
    TIMER_ADVANCES,
    TIMER_COMBINE_ATTRIBUTES,
    TIMER_UPDATE_BUILDER,
    TIMER_STAT_DRAW,
    TIMER_BETWEEN_CALLS_TO_DRAW_RECT,


    TIMER_STAT_MAX
};

typedef NS_ENUM(NSUInteger, iTermBackgroundDrawingMode) {
    iTermBackgroundDrawingModeDefault,
    iTermBackgroundDrawingModeOmitTransparent,
    iTermBackgroundDrawingModeOnlyTransparent,
};

static CGFloat iTermTextDrawingHelperAlphaValueForDefaultBackgroundColor(BOOL hasBackgroundImage,
                                                                         BOOL enableBlending,
                                                                         BOOL reverseVideo,
                                                                         CGFloat transparencyAlpha,
                                                                         CGFloat blend);
@implementation iTermTextDrawingHelper {
    NSFont *_cachedFont;
    CGFontRef _cgFont;

    // Last position of blinking cursor
    VT100GridCoord _oldCursorPosition;

    // Used by drawCursor: to remember the last time the cursor moved to avoid drawing a blinked-out
    // cursor while it's moving.
    NSTimeInterval _lastTimeCursorMoved;

    BOOL _blinkingFound;

    // Frame of the view we're drawing into.
    NSRect _frame;

    // The -visibleRect of the view we're drawing into.
    NSRect _visibleRectExcludingTopMargin;
    NSRect _visibleRectIncludingTopMargin;

    NSSize _scrollViewContentSize;
    NSRect _scrollViewDocumentVisibleRect;

    // Pattern for background stripes
    NSImage *_backgroundStripesImage;

    NSMutableSet<NSString *> *_missingImages;

    iTermPreciseTimerStats _stats[TIMER_STAT_MAX];
    CGFloat _baselineOffset;

    // The cache we're using now.
    NSMutableDictionary<iTermAttributedStringProxy *, id> *_lineRefCache;

    // The cache we'll use next time.
    NSMutableDictionary<iTermAttributedStringProxy *, id> *_replacementLineRefCache;

    BOOL _preferSpeedToFullLigatureSupport;
    NSMutableDictionary<NSNumber *, NSImage *> *_cachedMarks;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        iTermPreciseTimerSetEnabled(YES);
        iTermPreciseTimerStatsInit(&_stats[TIMER_TOTAL_DRAW_RECT], "Total drawRect");
        iTermPreciseTimerStatsInit(&_stats[TIMER_CONSTRUCT_BACKGROUND_RUNS], "Construct BG runs");
        iTermPreciseTimerStatsInit(&_stats[TIMER_DRAW_BACKGROUND], "Draw BG");

        iTermPreciseTimerStatsInit(&_stats[TIMER_STAT_CONSTRUCTION], "Construction");
        iTermPreciseTimerStatsInit(&_stats[TIMER_STAT_BUILD_MUTABLE_ATTRIBUTED_STRING], "Build attr strings");
        iTermPreciseTimerStatsInit(&_stats[TIMER_STAT_DRAW], "Drawing");

        iTermPreciseTimerStatsInit(&_stats[TIMER_ATTRS_FOR_CHAR], "Compute Attrs");
        iTermPreciseTimerStatsInit(&_stats[TIMER_SHOULD_SEGMENT], "Segment");
        iTermPreciseTimerStatsInit(&_stats[TIMER_UPDATE_BUILDER], "Update Builder");
        iTermPreciseTimerStatsInit(&_stats[TIMER_COMBINE_ATTRIBUTES], "Combine Attrs");
        iTermPreciseTimerStatsInit(&_stats[TIMER_ADVANCES], "Advances");
        iTermPreciseTimerStatsInit(&_stats[TIMER_BETWEEN_CALLS_TO_DRAW_RECT], "Between calls");

        _missingImages = [[NSMutableSet alloc] init];
        _lineRefCache = [[NSMutableDictionary alloc] init];
        _replacementLineRefCache = [[NSMutableDictionary alloc] init];
        _cachedMarks = [[NSMutableDictionary alloc] init];

        iTermAttributedStringBuilderStatsPointers pointers = {
            .attrsForChar = &_stats[TIMER_ATTRS_FOR_CHAR],
            .shouldSegment = &_stats[TIMER_SHOULD_SEGMENT],
            .buildMutableAttributedString = &_stats[TIMER_STAT_BUILD_MUTABLE_ATTRIBUTED_STRING],
            .combineAttributes = &_stats[TIMER_COMBINE_ATTRIBUTES],
            .updateBuilder = &_stats[TIMER_UPDATE_BUILDER],
            .advances = &_stats[TIMER_ADVANCES],
        };
        _attributedStringBuilder = [[iTermAttributedStringBuilder alloc] initWithStats:pointers];
    }
    return self;
}

- (void)dealloc {
    if (_cgFont) {
        CFRelease(_cgFont);
    }
}

#pragma mark - Accessors

- (void)setUnderlinedRange:(VT100GridAbsWindowedRange)underlinedRange {
    if (VT100GridAbsWindowedRangeEquals(underlinedRange, _underlinedRange)) {
        return;
    }
    DLog(@"Update underlined range of %@ to %@", self.delegate, VT100GridAbsWindowedRangeDescription(underlinedRange));
    _underlinedRange = underlinedRange;
}

#pragma mark - Drawing: General

- (void)didFinishSetup {
    [_attributedStringBuilder setColorMap:_colorMap
                             reverseVideo:_reverseVideo
                          minimumContrast:_minimumContrast
                                    zippy:self.zippy
                  asciiLigaturesAvailable:_asciiLigaturesAvailable
                           asciiLigatures:_asciiLigatures
         preferSpeedToFullLigatureSupport:_preferSpeedToFullLigatureSupport
                                 cellSize:_cellSize
                     blinkingItemsVisible:_blinkingItemsVisible
                             blinkAllowed:_blinkAllowed
                          useNonAsciiFont:_useNonAsciiFont
                           asciiAntiAlias:_asciiAntiAlias
                        nonAsciiAntiAlias:_nonAsciiAntiAlias
                                 isRetina:_isRetina
                forceAntialiasingOnRetina:_forceAntialiasingOnRetina
                              boldAllowed:_boldAllowed
                            italicAllowed:_italicAllowed
                        nonAsciiLigatures:_nonAsciiLigatures
                 useNativePowerlineGlyphs:_useNativePowerlineGlyphs
                             fontProvider:_fontProvider
                                fontTable:_fontTable
                                 delegate:self];
}

- (void)drawTextViewContentInRect:(NSRect)rect
                         rectsPtr:(const NSRect *)rectArray
                        rectCount:(NSInteger)rectCount
                    virtualOffset:(CGFloat)virtualOffset {
    DLog(@"begin drawRect:%@ in view %@", [NSValue valueWithRect:rect], _delegate);
    iTermPreciseTimerSetEnabled(YES);
    if (_debug) {
        [[NSColor redColor] set];
        iTermRectFill(rect, virtualOffset);
    }
    // If there are two or more rects that need display, the OS will pass in |rect| as the smallest
    // bounding rect that contains them all. Luckily, we can get the list of the "real" dirty rects
    // and they're guaranteed to be disjoint. So draw each of them individually.
    [self startTiming];

    if (![NSView iterm_takingSnapshot]) {
        // Issue 9352 - you have to clear the surface or else you can get artifacts. However, doing
        // so breaks taking a snapshot! FB9025520
        [[NSColor clearColor] set];
        iTermRectFillUsingOperation(rect, NSCompositingOperationCopy, virtualOffset);
    }

    const int haloWidth = 4;
    NSInteger yLimit = _numberOfLines;

    VT100GridCoordRange boundingCoordRange = [self visualCoordRangeForRect:rect];
    DLog(@"BEFORE: boundingCoordRange=%@", VT100GridCoordRangeDescription(boundingCoordRange));
    NSRange visibleLines = [self rangeOfVisibleRows];

    // Start at 0 because ligatures can draw incorrectly otherwise. When a font has a ligature for
    // -> and >-, then a line like ->->-> needs to start at the beginning since drawing only a
    // suffix of it could draw a >- ligature at the start of the range being drawn. Issue 5030.
    boundingCoordRange.start.x = 0;
    boundingCoordRange.start.y = MAX(MAX(0, boundingCoordRange.start.y - 1), visibleLines.location);
    boundingCoordRange.end.x = MIN(_gridSize.width, boundingCoordRange.end.x + haloWidth);
    boundingCoordRange.end.y = MIN(yLimit, boundingCoordRange.end.y + 1);
    DLog(@"AFTER: boundingCoordRange=%@", VT100GridCoordRangeDescription(boundingCoordRange));

    int numRowsInRect = MAX(0, boundingCoordRange.end.y - boundingCoordRange.start.y);
    if (numRowsInRect == 0) {
        DLog(@"No rows in rect given bounding coord range %@", VT100GridCoordRangeDescription(boundingCoordRange));
        return;
    }
    // X ranges to draw for each line.
    NSMutableData *store = [NSMutableData dataWithLength:numRowsInRect * sizeof(NSRange)];
    NSRange *ranges = (NSRange *)store.mutableBytes;
    for (int i = 0; i < rectCount; i++) {
        VT100GridCoordRange coordRange = [self visualCoordRangeForRect:rectArray[i]];
        DLog(@"Have to draw rect %@ (%@)", NSStringFromRect(rectArray[i]), VT100GridCoordRangeDescription(coordRange));
        int coordRangeMinX = 0;
        int coordRangeMaxX = MIN(_gridSize.width, coordRange.end.x + haloWidth);

        for (int j = 0; j < numRowsInRect; j++) {
            NSRange gridRange = ranges[j];
            if (gridRange.location == 0 && gridRange.length == 0) {
                ranges[j].location = coordRangeMinX;
                ranges[j].length = coordRangeMaxX - coordRangeMinX;
            } else {
                const int min = MIN(gridRange.location, coordRangeMinX);
                const int max = MAX(gridRange.location + gridRange.length, coordRangeMaxX);
                ranges[j].location = min;
                ranges[j].length = max - min;
            }
//            NSLog(@"Set range on line %d to %@", j + boundingCoordRange.start.y, NSStringFromRange(ranges[j]));
        }
    }

    [NSGraphicsContext saveGraphicsState];
    [self drawRanges:ranges
               count:numRowsInRect
              origin:boundingCoordRange.start
        boundingRect:_scrollViewDocumentVisibleRect
        visibleLines:visibleLines
       virtualOffset:virtualOffset];

    if (_selectedCommandRegion.length > 0) {
        [self drawOutlineAroundSelectedCommand:virtualOffset];
        [self drawShadeOverNonSelectedCommands:virtualOffset];
    }

    if (_showDropTargets) {
        [self drawDropTargetsWithVirtualOffset:virtualOffset];
    }
    [NSGraphicsContext restoreGraphicsState];

    [self stopTiming];

    iTermPreciseTimerPeriodicLog(@"drawRect", _stats, sizeof(_stats) / sizeof(*_stats), 5, [iTermAdvancedSettingsModel logDrawingPerformance], nil, nil);

    if (_debug) {
        NSColor *c = [NSColor colorWithCalibratedRed:(rand() % 255) / 255.0
                                               green:(rand() % 255) / 255.0
                                                blue:(rand() % 255) / 255.0
                                               alpha:1];
        [c set];
        iTermFrameRect(rect, virtualOffset);
    }

    // Release cached CTLineRefs from the last set of drawings and update them with the new ones.
    // This keeps us from having too many lines cached at once.
    _lineRefCache = _replacementLineRefCache;
    _replacementLineRefCache = [[NSMutableDictionary alloc] init];

    DLog(@"end drawRect:%@ in view %@", [NSValue valueWithRect:rect], _delegate);
}

- (NSInteger)numberOfEquivalentBackgroundColorLinesInRunArrays:(NSArray<iTermBackgroundColorRunsInLine *> *)backgroundRunArrays
                                                     fromIndex:(NSInteger)startIndex {
    NSInteger count = 1;
    iTermBackgroundColorRunsInLine *reference = backgroundRunArrays[startIndex];
    for (NSInteger i = startIndex + 1; i < backgroundRunArrays.count; i++) {
        if (![backgroundRunArrays[i].array isEqualToArray:reference.array]) {
            break;
        }
        ++count;
    }
    return count;
}

// NOTE: This will set a clip rect on the graphics state if pointsOnBottomToSuppressDrawing is positive.
// The caller must restoreGraphicsState after this returns in that case.
- (void)drawRanges:(NSRange *)ranges
             count:(NSInteger)numRanges
            origin:(VT100GridCoord)origin
      boundingRect:(NSRect)boundingRect
      visibleLines:(NSRange)visibleLines
     virtualOffset:(CGFloat)virtualOffset {
    // Configure graphics
    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositingOperationCopy];

    _blinkingFound = NO;

    NSMutableArray<iTermBackgroundColorRunsInLine *> *backgroundRunArrays = [NSMutableArray array];

    for (NSInteger i = 0; i < numRanges; i++) {
        const int line = origin.y + i;
        if (line >= NSMaxRange(visibleLines)) {
            continue;
        }
        iTermPreciseTimerStatsStartTimer(&_stats[TIMER_CONSTRUCT_BACKGROUND_RUNS]);
        NSRange charRange = ranges[i];
        // We work hard to paint all the backgrounds first and then all the foregrounds. The reason this
        // is necessary is because sometimes a glyph is larger than its cell. Some fonts draw narrow-
        // width characters as full-width, some combining marks (e.g., combining enclosing circle) are
        // necessarily larger than a cell, etc. For example, see issue 3446.
        //
        // By drawing characters after backgrounds and also drawing an extra "ring" of characters just
        // outside the clipping region, we allow oversize characters to draw outside their bounds
        // without getting painted-over by a background color. Of course if a glyph extends more than
        // one full cell outside its bounds, it will still get overwritten by a background sometimes.

        // First, find all the background runs. The outer array (backgroundRunArrays) will have one
        // element per line. That element (a PTYTextViewBackgroundRunArray) contains the line number,
        // y origin, and an array of PTYTextViewBackgroundRunBox objects.
        const double y = line * _cellSize.height;
        // An array of PTYTextViewBackgroundRunArray objects (one element per line).

//        NSLog(@"Draw line %d at %f", line, y);
        NSData *matches = [_delegate drawingHelperMatchesOnLine:line];
        BOOL first;
        const screen_char_t *theLine = [self lineAtIndex:line isFirst:&first];
        NSIndexSet *selectedIndexes =
            [_selection selectedIndexesIncludingTabFillersInAbsoluteLine:line + _totalScrollbackOverflow];

        if ([self canDrawLine:line]) {
            iTermImmutableMetadata metadata = [self.delegate drawingHelperMetadataOnLine:line];
            const BOOL rtlFound = metadata.rtlFound;
            iTermBackgroundColorRunsInLine *runsInLine =
            [iTermBackgroundColorRunsInLine backgroundRunsInLine:theLine
                                                      lineLength:_gridSize.width
                                                sourceLineNumber:line
                                               displayLineNumber:line
                                                 selectedIndexes:selectedIndexes
                                                     withinRange:charRange
                                                         matches:matches
                                                        anyBlink:&_blinkingFound
                                                               y:y
                                                            bidi:rtlFound ? [self.delegate drawingHelperBidiInfoForLine:line] : nil];
            [backgroundRunArrays addObject:runsInLine];
        } else {
            [backgroundRunArrays addObject:[iTermBackgroundColorRunsInLine defaultRunOfLength:_gridSize.width
                                                                                          row:line
                                                                                            y:y]];
        }
        iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_CONSTRUCT_BACKGROUND_RUNS]);
    }

    iTermPreciseTimerStatsStartTimer(&_stats[TIMER_DRAW_BACKGROUND]);
    // If a background image is in use, draw the whole rect at once.
    const BOOL enableBlending = !iTermTextIsMonochrome() || [NSView iterm_takingSnapshot];
    if (_hasBackgroundImage && enableBlending) {
        [self.delegate drawingHelperDrawBackgroundImageInRect:boundingRect
                                       blendDefaultBackground:NO
                                                virtualOffset:virtualOffset];
    }

    [NSGraphicsContext saveGraphicsState];
    [self clipOutSuppressedBottomIfNeeded:virtualOffset];

    const int cursorY = self.cursorCoord.y + origin.y;

    NSColor *cursorBackgroundColor;
    if ([self haveAnyImagesUnderText]) {
        if ([self blendManually]) {
            [self drawBackgroundRunArrays:backgroundRunArrays
                                  cursorY:-1
                              drawingMode:iTermBackgroundDrawingModeOnlyTransparent
                            virtualOffset:virtualOffset];
        }
        // Negative z-index values below INT32_MIN/2 (-1,073,741,824) will be drawn under cells with
        // non-default background colors
        // Kitty has an insane bug where it treats ansi colors that happen to have the same rgb value
        // as the default background color the same as the default background color.
        [self drawKittyImagesInRange:iTermSignedRangeWithBounds(NSIntegerMin, -1073741824)
                       virtualOffset:virtualOffset];
        cursorBackgroundColor = [self drawBackgroundRunArrays:backgroundRunArrays
                                                      cursorY:cursorY
                                                  drawingMode:iTermBackgroundDrawingModeOmitTransparent
                                                virtualOffset:virtualOffset];
    } else {
        cursorBackgroundColor = [self drawBackgroundRunArrays:backgroundRunArrays
                                                      cursorY:cursorY
                                                  drawingMode:iTermBackgroundDrawingModeDefault
                                                virtualOffset:virtualOffset];
    }
    // Negative z-index values mean that the images will be drawn under the text. This allows
    // rendering of text on top of images.
    // NOTE: The spec doesn't match Kitty, where z=0 is also drawn under the text.
    [self drawKittyImagesInRange:iTermSignedRangeWithBounds(-1073741824, 1)
                   virtualOffset:virtualOffset];


    iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_DRAW_BACKGROUND]);
    [NSGraphicsContext restoreGraphicsState];

    // Draw default background color over the line under the last drawn line so the tops of
    // characters aren't visible there. If there is an IME, that could be many lines tall.
    [self drawExcessWithVirtualOffset:virtualOffset];

    [NSGraphicsContext saveGraphicsState];
    [self clipOutSuppressedBottomIfNeeded:virtualOffset];

    // Draw other background-like stuff that goes behind text.
    [self drawAccessoriesInRect:boundingRect
                  virtualOffset:virtualOffset];

    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];

    const BOOL drawCursorBeforeText = (_cursorType == CURSOR_UNDERLINE || _cursorType == CURSOR_VERTICAL);
    iTermCursor *cursor = nil;
    if (drawCursorBeforeText) {
        cursor = [self drawCursor:NO
            cursorBackgroundColor:cursorBackgroundColor
                    virtualOffset:virtualOffset];
    }

    // Now iterate over the lines and paint the characters.
    if ([self textAppearanceDependsOnBackgroundColor]) {
        [self drawForegroundForBackgroundRunArrays:backgroundRunArrays
                          drawOffscreenCommandLine:NO
                                               ctx:ctx
                                     virtualOffset:virtualOffset];
    } else {
        [self drawUnprocessedForegroundForBackgroundRunArrays:backgroundRunArrays
                                     drawOffscreenCommandLine:NO
                                                          ctx:ctx
                                                virtualOffset:virtualOffset];
    }

    [NSGraphicsContext restoreGraphicsState];
    [self drawTopMarginWithVirtualOffset:virtualOffset];
    [self clipOutSuppressedBottomIfNeeded:virtualOffset];

    [self drawKittyImagesInRange:iTermSignedRangeWithBounds(1, NSIntegerMax)
                   virtualOffset:virtualOffset];
    [self drawMarksWithBackgroundRunArrays:backgroundRunArrays
                             virtualOffset:virtualOffset];

    // If the IME is in use, draw its contents over top of the "real" screen
    // contents.
    [self drawInputMethodEditorTextAt:_cursorCoord.x
                                    y:_cursorCoord.y
                                width:_gridSize.width
                               height:_gridSize.height
                         cursorHeight:_cellSizeWithoutSpacing.height
                                  ctx:ctx
                        virtualOffset:virtualOffset];
    _blinkingFound |= self.cursorBlinking;
    if (drawCursorBeforeText) {
        if ([iTermAdvancedSettingsModel drawOutlineAroundCursor]) {
            [self drawCursor:YES
       cursorBackgroundColor:cursorBackgroundColor
               virtualOffset:virtualOffset];
        }
    } else {
        cursor = [self drawCursor:NO
            cursorBackgroundColor:cursorBackgroundColor
                    virtualOffset:virtualOffset];
    }
    if (self.cursorShadow) {
        [cursor drawShadow];
    }

    if (self.copyMode) {
        [self drawCopyModeCursorWithBackgroundColor:cursorBackgroundColor
                                      virtualOffset:virtualOffset];
    }
    [self drawButtons:virtualOffset];
}

- (void)clipOutSuppressedBottomIfNeeded:(CGFloat)virtualOffset {
    if (_pointsOnBottomToSuppressDrawing > 0) {
        NSRect clipRect = NSMakeRect(0,
                                     _visibleRectIncludingTopMargin.origin.y,
                                     _visibleRectIncludingTopMargin.size.width,
                                     _visibleRectIncludingTopMargin.size.height - _pointsOnBottomToSuppressDrawing + _extraMargins.bottom);
        if (_debug) {
            [[NSColor redColor] set];
            iTermFrameRect(clipRect, virtualOffset);
        }
        iTermRectClip(clipRect, virtualOffset);
    }
}

- (BOOL)textAppearanceDependsOnBackgroundColor {
    if (self.minimumContrast > 0) {
        return YES;
    }
    if (self.colorMap.mutingAmount > 0) {
        return YES;
    }
    if (self.colorMap.dimmingAmount > 0) {
        return YES;
    }
    if (self.thinStrokes == iTermThinStrokesSettingDarkBackgroundsOnly) {
        return YES;
    }
    if (self.thinStrokes == iTermThinStrokesSettingRetinaDarkBackgroundsOnly && _isRetina) {
        return YES;
    }
    return NO;
}

#pragma mark - Drawing: Background

- (NSColor *)drawBackgroundRunArrays:(NSArray<iTermBackgroundColorRunsInLine *> *)backgroundRunArrays
                             cursorY:(int)cursorY
                         drawingMode:(iTermBackgroundDrawingMode)drawingMode
                       virtualOffset:(CGFloat)virtualOffset {
    NSColor *cursorBackgroundColor = nil;
    for (NSInteger i = 0; i < backgroundRunArrays.count; ) {
        iTermBackgroundColorRunsInLine *runArray = backgroundRunArrays[i];
        NSInteger rows = runArray.numberOfEquivalentRows;
        if (rows == 0) {
            rows = [self numberOfEquivalentBackgroundColorLinesInRunArrays:backgroundRunArrays fromIndex:i];
            runArray.numberOfEquivalentRows = rows;
        }
        if (cursorY >= runArray.line &&
            cursorY < runArray.line + runArray.numberOfEquivalentRows) {
            NSColor *color = [self unprocessedColorForBackgroundRun:[runArray runAtVisualIndex:self.cursorCoord.x] ?: runArray.lastRun
                                                     enableBlending:NO];
            cursorBackgroundColor = [_colorMap processedBackgroundColorForBackgroundColor:color];
        }
        [self drawBackgroundForLine:runArray.line
                                atY:runArray.y
                               runs:runArray.array
                     equivalentRows:rows
                        drawingMode:drawingMode
                      virtualOffset:virtualOffset];

        for (NSInteger j = i; j < i + rows; j++) {
            [self drawMarginsForLine:backgroundRunArrays[j].line
                                   y:backgroundRunArrays[j].y
                       virtualOffset:virtualOffset];
        }
        i += rows;
    }
    return cursorBackgroundColor;
}

- (void)drawBackgroundForLine:(int)line
                          atY:(CGFloat)yOrigin
                         runs:(NSArray<iTermBoxedBackgroundColorRun *> *)runs
               equivalentRows:(NSInteger)rows
                  drawingMode:(iTermBackgroundDrawingMode)drawingMode
                virtualOffset:(CGFloat)virtualOffset {
    BOOL pad = NO;
    NSSize padding = { 0 };
    if ([self.delegate drawingHelperShouldPadBackgrounds:&padding]) {
        pad = YES;
    }
    [self drawBackgroundForLine:line
                            atY:yOrigin
                           runs:runs
                 equivalentRows:rows
                  virtualOffset:virtualOffset
                            pad:pad
                        padding:padding
                    drawingMode:drawingMode];
}

- (BOOL)blendManually {
    return !iTermTextIsMonochrome() || [NSView iterm_takingSnapshot];
}

- (void)drawBackgroundForLine:(int)line
                          atY:(CGFloat)yOrigin
                         runs:(NSArray<iTermBoxedBackgroundColorRun *> *)runs
               equivalentRows:(NSInteger)rows
                virtualOffset:(CGFloat)virtualOffset
                          pad:(BOOL)pad
                      padding:(NSSize)padding
                  drawingMode:(iTermBackgroundDrawingMode)bgMode {
    const BOOL enableBlending = [self blendManually];
    for (iTermBoxedBackgroundColorRun *box in runs) {
        iTermBackgroundColorRun *run = box.valuePointer;

//        NSLog(@"Paint background row %d range %@", line, NSStringFromRange(run->range));

        NSRect rect = NSMakeRect(floor([iTermPreferences intForKey:kPreferenceKeySideMargins] + run->visualRange.location * _cellSize.width),
                                 yOrigin,
                                 ceil(run->visualRange.length * _cellSize.width),
                                 _cellSize.height * rows);
        // If subpixel AA is enabled, then we want to draw the default background color directly.
        // Otherwise, we'll disable blending and make it clear. Then the background color view can
        // do the job. We have to use blending when taking a snapshot in order to not have a clear
        // background color. I'm not sure why snapshots don't work right. My theory is that macOS
        // doesn't composiste multiple views correctly.
        NSColor *color = [self unprocessedColorForBackgroundRun:run
                                                 enableBlending:enableBlending];
        // The unprocessed color is needed for minimum contrast computation for text color.
        box.unprocessedBackgroundColor = color;
        color = [_colorMap processedBackgroundColorForBackgroundColor:color];
        box.backgroundColor = color;

        if (pad) {
            if (color.alphaComponent == 0) {
                continue;
            }
            NSRect temp = rect;
            temp.origin.x -= padding.width;
            temp.origin.y -= padding.height;
            temp.size.width += padding.width * 2;
            temp.size.height += padding.height * 2;

            rect = temp;
        }
        BOOL draw = YES;
        switch (bgMode) {
            case iTermBackgroundDrawingModeDefault:
                break;
            case iTermBackgroundDrawingModeOmitTransparent:
                draw = color.alphaComponent > 0;
                break;
            case iTermBackgroundDrawingModeOnlyTransparent:
                draw = color.alphaComponent == 0;
                break;
        }
        if (draw) {
            [self drawBackgroundColor:color
                               inRect:rect
                       enableBlending:enableBlending
                        virtualOffset:virtualOffset];
        }
        if (_debug) {
            [[NSColor yellowColor] set];
            NSBezierPath *path = [NSBezierPath bezierPath];
            [path it_moveToPoint:rect.origin virtualOffset:virtualOffset];
            [path it_lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect)) virtualOffset:virtualOffset];
            [path stroke];
        }
    }
}

- (void)drawBackgroundColor:(NSColor *)color
                     inRect:(NSRect)rect
             enableBlending:(BOOL)enableBlending
              virtualOffset:(CGFloat)virtualOffset {
    if (color.alphaComponent == 0 && !enableBlending) {
        return;
    }
    [color set];
    iTermRectFillUsingOperation(rect,
                                enableBlending ? NSCompositingOperationSourceOver : NSCompositingOperationCopy,
                                virtualOffset);
    if (_debug) {
        [[NSColor greenColor] set];
        iTermFrameRect(rect, virtualOffset);
    }
}

- (BOOL)lineIsInDeselectedRegion:(int)line {
    return _selectedCommandRegion.length > 0 && (line < 0 || !NSLocationInRange(line, _selectedCommandRegion));
}

- (NSColor *)unprocessedColorForBackgroundRun:(const iTermBackgroundColorRun *)run
                               enableBlending:(BOOL)enableBlending {
    NSColor *color;
    CGFloat alpha = _transparencyAlpha;
    if (run->selected) {
        color = [self selectionColorForCurrentFocus];
        if (_transparencyAffectsOnlyDefaultBackgroundColor) {
            alpha = 1;
        }
    } else if (run->isMatch) {
        color = [_colorMap colorForKey:kColorMapMatch];
    } else {
        const BOOL defaultBackground = (run->bgColor == ALTSEM_DEFAULT &&
                                        run->bgColorMode == ColorModeAlternate);
        // When set in preferences, applies alpha only to the defaultBackground
        // color, useful for keeping Powerline segments opacity(background)
        // consistent with their separator glyphs opacity(foreground).
        if (_transparencyAffectsOnlyDefaultBackgroundColor && !defaultBackground) {
            alpha = 1;
        }
        if (_reverseVideo && defaultBackground) {
            // Reverse video is only applied to default background-
            // color chars.
            color = [_delegate drawingHelperColorForCode:ALTSEM_DEFAULT
                                                   green:0
                                                    blue:0
                                               colorMode:ColorModeAlternate
                                                    bold:NO
                                                   faint:NO
                                            isBackground:NO];
        } else {
            // Use the regular background color.
            color = [_delegate drawingHelperColorForCode:run->bgColor
                                                   green:run->bgGreen
                                                    blue:run->bgBlue
                                               colorMode:run->bgColorMode
                                                    bold:NO
                                                   faint:NO
                                            isBackground:YES];
        }

        if (defaultBackground) {
            alpha = iTermTextDrawingHelperAlphaValueForDefaultBackgroundColor(_hasBackgroundImage,
                                                                              enableBlending,
                                                                              _reverseVideo,
                                                                              alpha,
                                                                              _blend);
        }
    }

    return [color colorWithAlphaComponent:alpha];
}

static CGFloat iTermTextDrawingHelperAlphaValueForDefaultBackgroundColor(BOOL hasBackgroundImage,
                                                                         BOOL enableBlending,
                                                                         BOOL reverseVideo,
                                                                         CGFloat transparencyAlpha,
                                                                         CGFloat blend) {
    // We can draw the default background color with a solid-color view under some circumstances.
    if (hasBackgroundImage) {
        if (enableBlending) {
            // Don't use the solid-color view to draw the default background color.
            return 1 - blend;
        } else {
            // Use the solid-color view to draw the default background color
            return 0;
        }
    } else if (!reverseVideo && !enableBlending) {
        // Use the solid-color view to draw the default background color
        return 0;
    }
    return transparencyAlpha;
}

- (NSRect)excessRect {
    VT100GridCoordRange drawableCoordRange = [self drawableCoordRangeForRect:_visibleRectExcludingTopMargin];
    const int line = drawableCoordRange.end.y;
    NSRect excessRect;
    if (_numberOfIMELines) {
        // Draw a default-color rectangle from below the last line of text to
        // the bottom of the frame to make sure that IME offset lines are
        // cleared when the screen is scrolled up.
        excessRect.origin.x = 0;
        excessRect.origin.y = line * _cellSize.height;
        excessRect.size.width = _scrollViewContentSize.width;
        excessRect.size.height = _frame.size.height - excessRect.origin.y;
    } else  {
        // Draw the excess bar at the bottom of the visible rect the in case
        // that some other tab has a larger font and these lines don't fit
        // evenly in the available space.
        NSRect visibleRect = _visibleRectExcludingTopMargin;
        excessRect.origin.x = 0;
        excessRect.origin.y = NSMaxY(visibleRect) - _excess;
        excessRect.size.width = _scrollViewContentSize.width;
        excessRect.size.height = _excess;
    }
    return excessRect;
}

- (void)drawExcessWithVirtualOffset:(CGFloat)virtualOffset {
    NSRect excessRect = [self excessRect];

    NSColor *color = [self marginColor];
    const BOOL enableBlending = !iTermTextIsMonochrome() || [NSView iterm_takingSnapshot];

    [self drawBackgroundColor:color inRect:excessRect enableBlending:enableBlending virtualOffset:virtualOffset];

    if (_debug) {
        [[NSColor blueColor] set];
        NSBezierPath *path = [NSBezierPath bezierPath];
        [path moveToPoint:excessRect.origin];
        [path lineToPoint:NSMakePoint(NSMaxX(excessRect), NSMaxY(excessRect))];
        [path stroke];

        iTermFrameRect(excessRect, virtualOffset);
    }

    if (_showStripes) {
        [self drawStripesInRect:excessRect virtualOffset:virtualOffset];
    }
}

- (void)drawTopMarginWithVirtualOffset:(CGFloat)virtualOffset {
    // Draw a margin at the top of the visible area.
    NSRect topMarginRect = _visibleRectExcludingTopMargin;
    topMarginRect.origin.y -= [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];

    topMarginRect.size.height = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];

    NSColor *color = [self marginColor];
    const BOOL enableBlending = !iTermTextIsMonochrome() || [NSView iterm_takingSnapshot];

    [self drawBackgroundColor:color inRect:topMarginRect enableBlending:enableBlending virtualOffset:virtualOffset];

    if (_showStripes) {
        [self drawStripesInRect:topMarginRect virtualOffset:virtualOffset];
    }
}

- (NSColor *)marginColor {
    const BOOL enableBlending = !iTermTextIsMonochrome() || [NSView iterm_takingSnapshot];
    iTermBackgroundColorRun run = { 0 };
    NSColor *color = [self unprocessedColorForBackgroundRun:&run
                                             enableBlending:enableBlending];
    color = [_colorMap processedBackgroundColorForBackgroundColor:color];
    return color;
}

- (NSRect)leftMarginRectAt:(CGFloat)y {
    return NSMakeRect(0, y, MAX(0, [iTermPreferences intForKey:kPreferenceKeySideMargins]), _cellSize.height);
}

- (void)drawMarginsForLine:(int)line
                         y:(CGFloat)y
             virtualOffset:(CGFloat)virtualOffset {
    NSRect leftMargin = [self leftMarginRectAt:y];
    NSRect rightMargin;
    NSRect visibleRect = _visibleRectExcludingTopMargin;
    rightMargin.origin.x = _cellSize.width * _gridSize.width + [iTermPreferences intForKey:kPreferenceKeySideMargins];
    rightMargin.origin.y = y;
    rightMargin.size.width = visibleRect.size.width - rightMargin.origin.x;
    rightMargin.size.height = _cellSize.height;

    // Draw background in margins
    NSColor *color = [self marginColor];
    const BOOL enableBlending = !iTermTextIsMonochrome() || [NSView iterm_takingSnapshot];

    [self drawBackgroundColor:color inRect:leftMargin enableBlending:enableBlending virtualOffset:virtualOffset];
    [self drawBackgroundColor:color inRect:rightMargin enableBlending:enableBlending virtualOffset:virtualOffset];
}

- (void)drawMarkForLine:(int)line
                      y:(CGFloat)y
          virtualOffset:(CGFloat)virtualOffset {
    NSRect leftMargin = [self leftMarginRectAt:y];

    id<iTermExternalAttributeIndexReading> eaIndex = [self.delegate drawingHelperExternalAttributesOnLine:line];

    if (eaIndex.attributes[@0].blockIDList) {
        if ([self canDrawLine:line]) {
            // Draw block indicator. This takes precedence over other marks because we don't want a
            // fold mark drawn over a folded block.
            if (NSLocationInRange(line, _highlightedBlockLineRange)) {
                [self.blockHoverColor set];
            } else {
                [[self.delegate drawingHelperColorForCode:ALTSEM_DEFAULT
                                                    green:0
                                                     blue:0
                                                colorMode:ColorModeAlternate
                                                     bold:NO
                                                    faint:NO
                                             isBackground:NO] set];
            }
            const NSRect rect = NSMakeRect(1,
                                           y,
                                           MAX(1, leftMargin.size.width - 2),
                                           _cellSize.height);
            if ([_folds containsIndex:line]) {
                iTermFrameRect(rect, virtualOffset);
            } else {
                iTermRectFillUsingOperation(rect, NSCompositingOperationSourceOver, virtualOffset);
            }
        }
    } else {
        [self drawMarkIfNeededOnLine:line
                      leftMarginRect:leftMargin
                       virtualOffset:virtualOffset];
    }
}

- (NSArray<NSColor *> *)selectedCommandOutlineColors {
    NSColor *selectedColor = [self.delegate drawingHelperColorForCode:ALTSEM_SELECTED
                                                                green:0
                                                                 blue:0
                                                            colorMode:ColorModeAlternate
                                                                 bold:NO
                                                                faint:NO
                                                         isBackground:YES];
    if (!selectedColor) {
        selectedColor = [NSColor colorWithDisplayP3Red:0.2 green:0.2 blue:1 alpha:1];
    }
    NSColor *bg = [[self defaultBackgroundColor] colorWithAlphaComponent:1.0];
    return @[
        selectedColor,
        [selectedColor blendedWithColor:bg weight:0.25],
    ];
}

const CGFloat commandRegionOutlineThickness = 2.0;

- (NSColor *)shadeColor {
    const CGFloat alpha = [iTermAdvancedSettingsModel alphaForDeselectedCommandShade];
    if ([[self defaultBackgroundColor] isDark]) {
        return [NSColor colorWithDisplayP3Red:1 green:1 blue:1 alpha:alpha];
    }
    return [NSColor colorWithDisplayP3Red:0 green:0 blue:0 alpha:alpha];
}

- (void)drawShadeOverNonSelectedCommands:(CGFloat)virtualOffset {
    const NSRange visibleRange = [self rangeOfVisibleRows];
    const NSRange visibleSelectedRange = NSIntersectionRange(visibleRange, _selectedCommandRegion);

    NSColor *color = self.shadeColor;
    [color set];

    const CGFloat topHeight = visibleSelectedRange.location * _cellSize.height - commandRegionOutlineThickness - _scrollViewDocumentVisibleRect.origin.y;
    CGFloat y = _scrollViewDocumentVisibleRect.origin.y;

    NSRect rect = NSMakeRect(0,
                             y,
                             _scrollViewDocumentVisibleRect.size.width,
                             MAX(0, topHeight));
    y += topHeight;
    iTermRectFillUsingOperation(rect, NSCompositingOperationSourceOver, virtualOffset);

    const CGFloat selectedHeight = MAX(0, visibleSelectedRange.length * _cellSize.height + commandRegionOutlineThickness * 2);
    y += selectedHeight;

    CGFloat savedBottom = 0;
    if (_forceRegularBottomMargin) {
        savedBottom = self.excessRect.size.height;
    }
    rect = NSMakeRect(0,
                      y,
                      _scrollViewDocumentVisibleRect.size.width,
                      _scrollViewDocumentVisibleRect.size.height - topHeight - selectedHeight - savedBottom);
    iTermRectFillUsingOperation(rect, NSCompositingOperationSourceOver, virtualOffset);

    DLog(@"rect.origin.y=%@ because document origin=%@ + topHeight=%@ + selectedHeight=%@. Cell height is %@",
          @(rect.origin.y-virtualOffset), @(_scrollViewDocumentVisibleRect.origin.y-virtualOffset), @(topHeight), @(selectedHeight), @(self.cellSize.height));
}

- (void)drawOutlineAroundSelectedCommand:(CGFloat)virtualOffset {
    const CGFloat y = _selectedCommandRegion.location * _cellSize.height;

    NSRect rect = NSMakeRect(0,
                             y - commandRegionOutlineThickness,
                             _scrollViewDocumentVisibleRect.size.width,
                             _selectedCommandRegion.length * _cellSize.height + commandRegionOutlineThickness * 2);

    NSArray<NSColor *> *colors = self.selectedCommandOutlineColors;
    for (NSColor * color in colors) {
        [color set];
        iTermFrameRect(rect, virtualOffset);
        rect = NSInsetRect(rect, 1, 1);
    }
}

- (void)drawStripesInRect:(NSRect)rect
            virtualOffset:(CGFloat)virtualOffset {
    if (!_backgroundStripesImage) {
        _backgroundStripesImage = [NSImage it_imageNamed:@"BackgroundStripes" forClass:self.class];
    }
    NSColor *color = [NSColor colorWithPatternImage:_backgroundStripesImage];
    [color set];

    [NSGraphicsContext saveGraphicsState];
    [[NSGraphicsContext currentContext] setPatternPhase:NSMakePoint([iTermPreferences intForKey:kPreferenceKeySideMargins], 0)];
    iTermRectFillUsingOperation(rect, NSCompositingOperationSourceOver, virtualOffset);
    [NSGraphicsContext restoreGraphicsState];
}

#pragma mark - Drawing: Accessories

- (NSEdgeInsets)badgeMargins {
    return NSEdgeInsetsMake(self.badgeTopMargin, 0, 0, self.badgeRightMargin);
}

- (VT100GridCoordRange)safeCoordRange:(VT100GridCoordRange)range {
    const int width = _gridSize.width;
    const int height = _numberOfLines;
    return VT100GridCoordRangeMake(MEDIAN(0, range.start.x, width),
                                   MEDIAN(0, range.start.y, height),
                                   MEDIAN(0, range.end.x, width),
                                   MEDIAN(0, range.end.y, height));
}

- (void)drawAccessoriesInRect:(NSRect)bgRect virtualOffset:(CGFloat)virtualOffset {
    const VT100GridCoordRange coordRange = [self safeCoordRange:[self coordRangeForRect:bgRect]];
    [self drawBadgeInRect:bgRect
                  margins:self.badgeMargins
            virtualOffset:virtualOffset];

    // Draw red stripes in the background if sending input to all sessions
    if (_showStripes) {
        [self drawStripesInRect:bgRect virtualOffset:virtualOffset];
    }

    // Highlight cursor line if the cursor is on this line and it's on.
    int cursorLine = _cursorCoord.y + _numberOfScrollbackLines;
    const BOOL drawCursorGuide = (self.highlightCursorLine &&
                                  cursorLine >= coordRange.start.y &&
                                  cursorLine <= coordRange.end.y);
    if (drawCursorGuide) {
        CGFloat y = cursorLine * _cellSize.height;
        [self drawCursorGuideForColumns:NSMakeRange(coordRange.start.x,
                                                    coordRange.end.x - coordRange.start.x)
                                      y:y
                          virtualOffset:virtualOffset];
    }
}

- (void)drawCursorGuideForColumns:(NSRange)range
                                y:(CGFloat)yOrigin
                    virtualOffset:(CGFloat)virtualOffset {
    if (!_isCursorVisible) {
        return;
    }
    [_cursorGuideColor set];
    NSPoint textOrigin = NSMakePoint([iTermPreferences intForKey:kPreferenceKeySideMargins] + range.location * _cellSize.width, yOrigin);
    NSRect rect = NSMakeRect(0,
                             textOrigin.y,
                             _scrollViewDocumentVisibleRect.size.width,
                             _cellSize.height);
    iTermRectFillUsingOperation(rect, NSCompositingOperationSourceOver, virtualOffset);

    rect.size.height = 1;
    iTermRectFillUsingOperation(rect, NSCompositingOperationSourceOver, virtualOffset);

    rect.origin.y += _cellSize.height - 1;
    iTermRectFillUsingOperation(rect, NSCompositingOperationSourceOver, virtualOffset);
}

+ (NSRect)frameForMarkContainedInRect:(NSRect)container
                             cellSize:(CGSize)cellSize
               cellSizeWithoutSpacing:(CGSize)cellSizeWithoutSpacing
                                scale:(CGFloat)scale {
    const CGFloat verticalSpacing = MAX(0, scale * round((cellSize.height / scale - cellSizeWithoutSpacing.height / scale) / 2.0));
    DLog(@"verticalSpacing=%@", @(verticalSpacing));
    CGRect rect = NSMakeRect(container.origin.x,
                             container.origin.y + verticalSpacing,
                             container.size.width,
                             cellSizeWithoutSpacing.height);
    DLog(@"container=%@ rect=%@", NSStringFromRect(container), NSStringFromRect(rect));
    const CGFloat kMaxHeight = 15 * scale;
    const CGFloat kMinMargin = 3 * scale;
    const CGFloat kMargin = MAX(kMinMargin, (cellSizeWithoutSpacing.height - kMaxHeight) / 2.0);
    const CGFloat kMaxMargin = 4 * scale;
    DLog(@"kMargin=%@, kMaxMargin=%@", @(kMargin), @(kMaxMargin));

    const CGFloat overage = rect.size.width - rect.size.height + 2 * kMargin;
    DLog(@"overage=%@", @(overage));
    if (overage > 0) {
        rect.origin.x += MAX(0, overage - kMaxMargin);
        rect.size.width -= overage;
        DLog(@"Subtract overage, leaving rect of %@", NSStringFromRect(rect));
    }

    rect.origin.y += kMargin;
    rect.size.height -= kMargin;

    DLog(@"Adjust origin and height giving %@", NSStringFromRect(rect));

    // Bump the bottom up by as much as 3 points.
    rect.size.height -= MAX(3 * scale, (cellSizeWithoutSpacing.height - 15 * scale) / 2.0);
    DLog(@"Bump bottom leaving %@", NSStringFromRect(rect));
    rect.size.width = MAX(scale, rect.size.width);
    rect.size.height = MAX(scale, rect.size.height);
    DLog(@"Clamp size leaving %@", NSStringFromRect(rect));
    return rect;
}

+ (NSColor *)successMarkColor {
    return [[NSColor colorWithSRGBRed:0.53846
                                green:0.757301
                                 blue:1
                                alpha:1] colorUsingColorSpace:[NSColorSpace it_defaultColorSpace]];
}

+ (NSColor *)errorMarkColor {
    return [[NSColor colorWithSRGBRed:0.987265
                                green:0.447845
                                 blue:0.426244
                                alpha:1] colorUsingColorSpace:[NSColorSpace it_defaultColorSpace]];
}

+ (NSColor *)otherMarkColor {
    return [[NSColor colorWithSRGBRed:0.856645
                                green:0.847289
                                 blue:0.425771
                                alpha:1]  colorUsingColorSpace:[NSColorSpace it_defaultColorSpace]];
}

+ (NSImage *)newImageWithMarkOfColor:(NSColor *)color
                           pixelSize:(CGSize)pixelSize
                              folded:(BOOL)folded {
    NSSize pointSize = [NSImage pointSizeOfGeneratedImageWithPixelSize:pixelSize];
    return [self newImageWithMarkOfColor:color size:pointSize folded:folded];
}

+ (NSImage *)newImageWithMarkOfColor:(NSColor *)color
                                size:(CGSize)size
                              folded:(BOOL)folded {
    if (size.width < 1 || size.height < 1) {
        return [self newImageWithMarkOfColor:color
                                        size:CGSizeMake(MAX(1, size.width),
                                                        MAX(1, size.height))
                                      folded:folded];
    }
    NSImage *img = [NSImage imageOfSize:size drawBlock:^{
        CGRect rect = CGRectMake(0, 0, MAX(1, size.width), size.height);

        const NSPoint bottomLeft = NSMakePoint(NSMinX(rect), NSMinY(rect));
        const NSPoint midRight = NSMakePoint(NSMaxX(rect), NSMidY(rect));
        const NSPoint topLeft = NSMakePoint(NSMinX(rect), NSMaxY(rect));

        if (size.width < 2) {
            NSRect rect = NSMakeRect(0, 0, size.width, size.height);
            rect = NSInsetRect(rect, 0, rect.size.height * 0.25);
            [[color colorWithAlphaComponent:0.75] set];
            NSRectFill(rect);
        } else {
            if (folded) {
                NSBezierPath *path = [NSBezierPath bezierPath];
                [path moveToPoint:topLeft];
                [path lineToPoint:midRight];
                [path lineToPoint:bottomLeft];

                [[NSColor blackColor] set];
                [path fill];

                [color set];
                [path setLineWidth:1.0];
                [path stroke];
            } else {
                NSBezierPath *path = [NSBezierPath bezierPath];
                [path moveToPoint:topLeft];
                [path lineToPoint:midRight];
                [path lineToPoint:bottomLeft];
                [path lineToPoint:topLeft];
                [color set];
                [path fill];

                path = [NSBezierPath bezierPath];
                [path moveToPoint:NSMakePoint(bottomLeft.x, bottomLeft.y)];
                [path lineToPoint:NSMakePoint(midRight.x, midRight.y)];
                [path setLineWidth:1.0];
                [[NSColor blackColor] set];
                [path stroke];
            }
        }
    }];

    return img;
}

+ (iTermMarkIndicatorType)markIndicatorTypeForMark:(id<iTermMark>)genericMark
                                            folded:(BOOL)folded {
    id<VT100ScreenMarkReading> mark = (id<VT100ScreenMarkReading>)genericMark;
    if (mark.code == 0) {
        return folded ? iTermMarkIndicatorTypeFoldedSuccess : iTermMarkIndicatorTypeSuccess;
    }
    if ([iTermAdvancedSettingsModel showYellowMarkForJobStoppedBySignal] &&
        mark.code >= 128 && mark.code <= 128 + 32) {
        // Stopped by a signal (or an error, but we can't tell which)
        return folded ? iTermMarkIndicatorTypeFoldedOther : iTermMarkIndicatorTypeOther;
    }
    return folded ? iTermMarkIndicatorTypeFoldedError : iTermMarkIndicatorTypeError;
}

+ (NSColor *)colorForMark:(id<iTermMark>)mark {
    return [self colorForMarkType:[iTermTextDrawingHelper markIndicatorTypeForMark:mark folded:NO]];
}

+ (NSColor *)colorForMarkType:(iTermMarkIndicatorType)type {
    switch (type) {
        case iTermMarkIndicatorTypeSuccess:
        case iTermMarkIndicatorTypeFoldedSuccess:
            return [iTermTextDrawingHelper successMarkColor];
        case iTermMarkIndicatorTypeOther:
        case iTermMarkIndicatorTypeFoldedOther:
            return [iTermTextDrawingHelper otherMarkColor];
        case iTermMarkIndicatorTypeError:
        case iTermMarkIndicatorTypeFoldedError:
            return [iTermTextDrawingHelper errorMarkColor];
    }
}

- (BOOL)canDrawLine:(int)line {
    return (line < _linesToSuppress.location ||
            line >= _linesToSuppress.location + _linesToSuppress.length);
}

- (void)drawMarksWithBackgroundRunArrays:(NSArray<iTermBackgroundColorRunsInLine *> *)backgroundRunArrays
                           virtualOffset:(CGFloat)virtualOffset {
    for (NSInteger i = 0; i < backgroundRunArrays.count; i += 1) {
        [self drawMarkForLine:backgroundRunArrays[i].line
                            y:backgroundRunArrays[i].y
                virtualOffset:virtualOffset];
    }
}

- (void)drawMarkIfNeededOnLine:(int)line
                leftMarginRect:(NSRect)leftMargin
                 virtualOffset:(CGFloat)virtualOffset {
    if (![self canDrawLine:line]) {
        return;
    }
    id<VT100ScreenMarkReading> mark = [self.delegate drawingHelperMarkOnLine:line];
    const BOOL folded = [_folds containsIndex:line];
    BOOL shouldDrawRegularMark = folded;
    if (mark != nil && (self.drawMarkIndicators || mark.name.length > 0)) {
        if (mark.lineStyle) {
            if (_selectedCommandRegion.length > 0 && NSLocationInRange(line, _selectedCommandRegion)) {
                // Don't draw line-style mark in selected command region.
                return;
            }
            if (_selectedCommandRegion.length > 0 && line == NSMaxRange(_selectedCommandRegion) + 1) {
                // Don't draw line-style mark immediately after selected command region.
                return;
            }
            NSColor *bgColor = [self defaultBackgroundColor];
            NSColor *merged = [iTermTextDrawingHelper colorForLineStyleMark:[iTermTextDrawingHelper markIndicatorTypeForMark:mark
                                                                                                                      folded:folded]
                                                            backgroundColor:bgColor];
            [merged set];
            NSRect rect;
            rect.origin.x = 0;
            int buttonCells = iTermTextDrawingHelperLineStyleMarkRightInsetCells;
            if (!mark.command.length) {
                buttonCells = 0;
            }
            rect.size.width = leftMargin.size.width + self.cellSize.width * (self.gridSize.width - buttonCells);
            rect.size.height = 1;
            const CGFloat y = (((CGFloat)line) - 0.5) * _cellSize.height;
            rect.origin.y = round(y);
            iTermRectFill(rect, virtualOffset);
        }
        if (!mark.lineStyle || folded) {
            shouldDrawRegularMark = YES;
        }
    }

    if (shouldDrawRegularMark) {
        NSRect insetLeftMargin = leftMargin;
        insetLeftMargin.origin.x += 1;
        insetLeftMargin.size.width -= 1;
        NSRect rect = [iTermTextDrawingHelper frameForMarkContainedInRect:insetLeftMargin
                                                                 cellSize:_cellSize
                                                   cellSizeWithoutSpacing:_cellSizeWithoutSpacing
                                                                    scale:1];
        const iTermMarkIndicatorType type = [iTermTextDrawingHelper markIndicatorTypeForMark:mark
                                                                                      folded:folded];
        NSImage *image = _cachedMarks[@(type)];
        if (!image || !NSEqualSizes(image.size, rect.size)) {
            NSColor *markColor = [iTermTextDrawingHelper colorForMark:mark];
            image = [iTermTextDrawingHelper newImageWithMarkOfColor:markColor
                                                               size:rect.size
                                                             folded:folded];
            _cachedMarks[@(type)] = image;
        }
        [image it_drawInRect:rect virtualOffset:virtualOffset];
    }
}

+ (NSColor *)colorForLineStyleMark:(iTermMarkIndicatorType)type backgroundColor:(NSColor *)bgColor {
    NSColor *markColor = [iTermTextDrawingHelper colorForMarkType:type];
    NSColor *merged = [bgColor blendedWithColor:markColor weight:0.5];
    return merged;
}

- (void)drawNoteRangesOnLine:(int)line
               virtualOffset:(CGFloat)virtualOffset {
    if (![self canDrawLine:line]) {
        return;
    }
    NSArray *noteRanges = [self.delegate drawingHelperCharactersWithNotesOnLine:line];
    if (noteRanges.count) {
        for (NSValue *value in noteRanges) {
            VT100GridRange range = [value gridRangeValue];
            CGFloat x = range.location * _cellSize.width + [iTermPreferences intForKey:kPreferenceKeySideMargins];
            CGFloat y = line * _cellSize.height;
            [[NSColor yellowColor] set];

            CGFloat maxX = MIN(_frame.size.width - [iTermPreferences intForKey:kPreferenceKeySideMargins], range.length * _cellSize.width + x);
            CGFloat w = maxX - x;
            iTermRectFill(NSMakeRect(x, y + _cellSize.height - 1.5, w, 1), virtualOffset);
            [[NSColor orangeColor] set];
            iTermRectFill(NSMakeRect(x, y + _cellSize.height - 1, w, 1), virtualOffset);
        }

    }
}

- (void)createTimestampDrawingHelperWithFont:(NSFont *)font {
    [self updateCachedMetrics];
    CGFloat obscured = 0;
    if (_offscreenCommandLine) {
        obscured = _cellSize.height + iTermOffscreenCommandLineVerticalPadding * 2;
    }
    _timestampDrawHelper =
        [[iTermTimestampDrawHelper alloc] initWithBackgroundColor:[self defaultBackgroundColor]
                                                        textColor:[_colorMap colorForKey:kColorMapForeground]
                                                              now:self.now
                                               useTestingTimezone:self.useTestingTimezone
                                                        rowHeight:_cellSize.height
                                                           retina:self.isRetina
                                                             font:font
                                                         obscured:obscured];
    for (int y = _scrollViewDocumentVisibleRect.origin.y / _cellSize.height;
         y < NSMaxY(_scrollViewDocumentVisibleRect) / _cellSize.height && y < _numberOfLines;
         y++) {
        [_timestampDrawHelper setDate:[_delegate drawingHelperTimestampForLine:y] forLine:y];
    }
}

- (void)drawTimestampsWithVirtualOffset:(CGFloat)virtualOffset {
    if (!self.shouldShowTimestamps) {
        return;
    }

    [self updateCachedMetrics];

    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] CGContext];
    if (!self.isRetina) {
        CGContextSetShouldSmoothFonts(ctx, NO);
    }
    // Note: for the foreground color, we don't use the dimmed version because it looks bad on
    // nonretina displays. That's why I go to the colormap instead of using -defaultForegroundColor.
    [_timestampDrawHelper drawInContext:[NSGraphicsContext currentContext]
                                  frame:_frame
                          virtualOffset:virtualOffset];
    if (!self.isRetina) {
        CGContextSetShouldSmoothFonts(ctx, YES);
    }
}

+ (NSRect)rectForBadgeImageOfSize:(NSSize)imageSize
             destinationFrameSize:(NSSize)textViewSize
                    sourceRectPtr:(NSRect *)sourceRectPtr
                          margins:(NSEdgeInsets)margins
                   verticalOffset:(CGFloat)verticalOffset{
    if (NSEqualSizes(NSZeroSize, imageSize)) {
        return NSZeroRect;
    }
    NSRect destination = NSMakeRect(textViewSize.width - imageSize.width - margins.right,
                                    kiTermIndicatorStandardHeight + margins.top + verticalOffset,
                                    imageSize.width,
                                    imageSize.height);
    NSRect source = destination;
    source.origin.x -= destination.origin.x;
    source.origin.y -= destination.origin.y;
    source.origin.y = imageSize.height - (source.origin.y + source.size.height);
    *sourceRectPtr = source;
    return destination;
}

- (NSSize)drawBadgeInRect:(NSRect)rect
                  margins:(NSEdgeInsets)margins
            virtualOffset:(CGFloat)virtualOffset {
    NSRect source = NSZeroRect;
    const NSRect intersection =
        [iTermTextDrawingHelper rectForBadgeImageOfSize:_badgeImage.size
                                   destinationFrameSize:_frame.size
                                          sourceRectPtr:&source
                                                margins:NSEdgeInsetsMake(self.badgeTopMargin, 0, 0, self.badgeRightMargin)
                                         verticalOffset:virtualOffset];
    if (NSEqualSizes(NSZeroSize, intersection.size)) {
        return NSZeroSize;
    }
    [_badgeImage it_drawInRect:intersection
                      fromRect:source
                     operation:NSCompositingOperationSourceOver
                      fraction:1
                respectFlipped:YES
                         hints:nil
                 virtualOffset:virtualOffset];

    NSSize imageSize = _badgeImage.size;
    imageSize.width += kBadgeMargin + margins.right;

    return imageSize;
}

// Assumes that updateButtonFrames was invoked by caller first.
- (void)drawButtons:(CGFloat)virtualOffset {
    NSColor *background = [[self.delegate drawingHelperColorForCode:ALTSEM_DEFAULT green:0 blue:0 colorMode:ColorModeAlternate bold:NO faint:NO isBackground:YES] colorWithAlphaComponent:_transparencyAlpha];
    NSColor *foreground = [self.delegate drawingHelperColorForCode:ALTSEM_DEFAULT green:0 blue:0 colorMode:ColorModeAlternate bold:NO faint:NO isBackground:NO];
    NSColor *selectedColor = [self.delegate drawingHelperColorForCode:ALTSEM_SELECTED green:0 blue:0 colorMode:ColorModeAlternate bold:NO faint:NO isBackground:YES];

    if (@available(macOS 11, *)) {
        iTermRectArray *rects = [self buttonsBackgroundRects];
        for (NSInteger i = 0; i < rects.count; i++) {
            const NSRect rect = [rects rectAtIndex:i];
            [background set];
            iTermRectFill(rect, virtualOffset);
            [foreground set];
            iTermFrameRect(rect, virtualOffset);
        }

        for (iTermTerminalButton *button in [self.delegate drawingHelperTerminalButtons]) {
            if (![self canDrawLine:button.absCoordForDesiredFrame.y - _totalScrollbackOverflow]) {
                continue;
            }
            [button drawWithBackgroundColor:background
                            foregroundColor:foreground
                              selectedColor:selectedColor
                                      frame:button.desiredFrame
                              virtualOffset:virtualOffset];
        }
    }
}

- (iTermRectArray *)buttonsBackgroundRects NS_AVAILABLE_MAC(11) {
    NSMutableDictionary<NSNumber *, NSValue *> *dict = [NSMutableDictionary dictionary];
    NSArray<iTermTerminalButton *> *buttons = [self.delegate drawingHelperTerminalButtons];
    for (iTermTerminalButton *button in buttons) {
        if (!button.wantsFrame) {
            continue;
        }
        VT100GridAbsCoord absCoord = [_delegate absCoordForButton:button];
        NSValue *value = dict[@(absCoord.y)];
        if (!value) {
            value = [NSValue valueWithRect:button.desiredFrame];
        } else {
            NSRect rect = value.rectValue;
            rect = NSUnionRect(rect, button.desiredFrame);
            value = [NSValue valueWithRect:rect];
        }
        dict[@(absCoord.y)] = value;
    }
    iTermMutableRectArray *result = [[iTermMutableRectArray alloc] init];
    [dict enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, NSValue *value, BOOL * _Nonnull stop) {
        const NSRect rect = value.rectValue;
        [result append:NSInsetRect(rect, -4, -2)];
    }];
    return result;
}

- (void)updateButtonFrames NS_AVAILABLE_MAC(11) {
    const VT100GridCoordRange drawableCoordRange = [self drawableCoordRangeForRect:_visibleRectExcludingTopMargin];
    const long long minAbsY = drawableCoordRange.start.y + _totalScrollbackOverflow;
    const CGFloat margin = [iTermPreferences intForKey:kPreferenceKeySideMargins];
    int floatingCount = 0;
    NSMutableDictionary<NSNumber *, NSMutableIndexSet *> *usedDict = [NSMutableDictionary dictionary];
    for (iTermTerminalButton *button in [self.delegate drawingHelperTerminalButtons]) {
        CGFloat x;
        button.enclosingSessionWidth = _gridSize.width;
        VT100GridAbsCoord absCoord = [_delegate absCoordForButton:button];
        int proposedX;
        int widthInCells = ceil([button sizeWithCellSize:_cellSize].width / self.cellSize.width) + 1;
        if (absCoord.x < 0) {
            // Floating button
            proposedX = self.gridSize.width - 2 - floatingCount * widthInCells;
            floatingCount += 1;
        } else {
            // Absolutely positioned button
            proposedX = absCoord.x;
        }
        long long effectiveAbsY = MAX(absCoord.y, minAbsY);
        NSMutableIndexSet *used = usedDict[@(effectiveAbsY)];
        if (!used) {
            used = [NSMutableIndexSet indexSet];
            usedDict[@(effectiveAbsY)] = used;
        }
        while (proposedX > 0 && [used intersectsIndexesInRange:NSMakeRange(proposedX, widthInCells)]) {
            proposedX -= 1;
        }
        if (proposedX >= 0) {
            x = margin + proposedX * self.cellSize.width;
            [used addIndexesInRange:NSMakeRange(proposedX, widthInCells)];
        } else {
            DLog(@"Out of space for %@", button);
            button.desiredFrame = NSZeroRect;
            continue;
        }
        button.desiredFrame = [button frameWithX:x
                                            absY:absCoord.y
                                      minAbsLine:minAbsY
                                cumulativeOffset:_totalScrollbackOverflow
                                        cellSize:_cellSize];
        DLog(@"Set desired frame of %@ to %@", button, NSStringFromRect(button.desiredFrame));
        if (_selectedCommandRegion.length > 0 && absCoord.y - self.totalScrollbackOverflow == NSMaxRange(_selectedCommandRegion)) {
            NSRect frame = button.desiredFrame;
            button.shift = 2;
            frame.origin.y += button.shift;
            button.desiredFrame = frame;
        } else {
            button.shift = 0;
        }
        absCoord.x = proposedX;
        absCoord.y = effectiveAbsY;
        button.absCoordForDesiredFrame = absCoord;
        DLog(@"Set desired frame of %@ to %@ from minAbsLine:%@ = (%@ + %@) visibleRect:%@ cumulativeOffset:%@ cellSize.height:%@",
             button,
             NSStringFromRect(button.desiredFrame),
             @(drawableCoordRange.start.y + _totalScrollbackOverflow),
             @(drawableCoordRange.start.y),
             @(_totalScrollbackOverflow),
             NSStringFromRect(_visibleRectExcludingTopMargin),
             @(_totalScrollbackOverflow),
             @(_cellSize.height));
    }
}

#pragma mark - Drawing: Drop targets

- (void)drawDropTargetsWithVirtualOffset:(CGFloat)virtualOffset {
    NSColor *scrimColor;
    NSColor *borderColor;
    NSColor *labelColor;
    NSColor *outlineColor;

    if ([[self defaultBackgroundColor] isDark]) {
        outlineColor = [NSColor whiteColor];
        scrimColor = [NSColor whiteColor];
        borderColor = [NSColor lightGrayColor];
        labelColor = [NSColor blackColor];
    } else {
        outlineColor = [NSColor blackColor];
        scrimColor = [NSColor blackColor];
        borderColor = [NSColor darkGrayColor];
        labelColor = [NSColor whiteColor];
    }
    scrimColor = [scrimColor colorWithAlphaComponent:0.6];

    NSDictionary *attributes = @{ NSForegroundColorAttributeName: labelColor,
                                  NSStrokeWidthAttributeName: @-4,
                                  NSStrokeColorAttributeName: outlineColor };

    [self enumerateDropTargets:^(NSString *label, NSRange range) {
        NSRect rect = NSMakeRect(0,
                                 range.location * _cellSize.height,
                                 _scrollViewDocumentVisibleRect.size.width,
                                 _cellSize.height * range.length);

        if (NSLocationInRange(_dropLine, range)) {
            [[[NSColor selectedControlColor] colorWithAlphaComponent:0.7] set];
        } else {
            [scrimColor set];
        }
        iTermRectFillUsingOperation(rect, NSCompositingOperationSourceOver, virtualOffset);

        [borderColor set];
        iTermFrameRect(rect, virtualOffset);

        [label it_drawInRect:rect
              withAttributes:[label attributesUsingFont:[NSFont boldSystemFontOfSize:8]
                                            fittingSize:rect.size
                                             attributes:attributes]
               virtualOffset:virtualOffset];
    }];
}

- (void)enumerateDropTargets:(void (^NS_NOESCAPE)(NSString *, NSRange))block {
    NSRect rect = _scrollViewDocumentVisibleRect;
    VT100GridCoordRange coordRange = [self drawableCoordRangeForRect:rect];
    CGFloat y = coordRange.start.y * _cellSize.height;
    NSMutableArray *labels = [NSMutableArray array];
    NSMutableArray *lineRanges = [NSMutableArray array];
    int firstLine = coordRange.start.y;
    for (int line = coordRange.start.y; line <= coordRange.end.y; line++, y += _cellSize.height) {
        NSString *label = [_delegate drawingHelperLabelForDropTargetOnLine:line];
        if (!label) {
            continue;
        }
        NSString *previousLabel = labels.lastObject;
        if ([label isEqualToString:previousLabel]) {
            [labels removeLastObject];
            [lineRanges removeLastObject];
        } else {
            firstLine = line;
        }
        [labels addObject:label];
        [lineRanges addObject:[NSValue valueWithRange:NSMakeRange(firstLine, line - firstLine + 1)]];
    }
    for (NSInteger i = 0; i < labels.count; i++) {
        block(labels[i], [lineRanges[i] rangeValue]);
    }
}

#pragma mark - Drawing: Foreground

static BOOL NSRangesAdjacent(NSRange lhs, NSRange rhs) {
    if (lhs.location == NSNotFound || rhs.location == NSNotFound) {
        return NO;
    }

    return NSMaxRange(lhs) == rhs.location || NSMaxRange(rhs) == lhs.location;
}

// Draw assuming no foreground color processing. Keeps glyphs together in a single background color run across different background colors.
- (void)drawUnprocessedForegroundForBackgroundRunArrays:(NSArray<iTermBackgroundColorRunsInLine *> *)backgroundRunArrays
                               drawOffscreenCommandLine:(BOOL)drawOffscreenCommandLine
                                                    ctx:(CGContextRef)ctx
                                          virtualOffset:(CGFloat)virtualOffset {
    // Combine runs on each line, except those with different values of
    // `selected` or `match`, or when faint text is present.
    // Those properties affect foreground color and must split ligatures up and process foreground
    // color separately.
    NSArray<iTermBackgroundColorRunsInLine *> *fakeRunArrays = [backgroundRunArrays mapWithBlock:^id(iTermBackgroundColorRunsInLine *runs) {
        NSMutableArray<iTermBoxedBackgroundColorRun *> *combinedRuns = [NSMutableArray array];
        iTermBackgroundColorRun previousRun = { {0} };
        BOOL havePreviousRun = NO;
        for (iTermBoxedBackgroundColorRun *run in runs.array) {
            if (!havePreviousRun) {
                havePreviousRun = YES;
                previousRun = *run.valuePointer;
            } else if (run.valuePointer->selected == previousRun.selected &&
                       run.valuePointer->isMatch == previousRun.isMatch &&
                       !run.valuePointer->beneathFaintText &&
                       !previousRun.beneathFaintText &&
                       NSRangesAdjacent(previousRun.modelRange, run.valuePointer->modelRange)) {
                // Combine with preceding run.
                previousRun.visualRange = NSUnionRange(previousRun.visualRange, run.valuePointer->visualRange);
                previousRun.modelRange = NSUnionRange(previousRun.modelRange, run.valuePointer->modelRange);
            } else {
                // Allow this run to remain.
                [combinedRuns addObject:[iTermBoxedBackgroundColorRun boxedBackgroundColorRunWithValue:previousRun]];
                previousRun = *run.valuePointer;
            }
        }
        if (havePreviousRun) {
            [combinedRuns addObject:[iTermBoxedBackgroundColorRun boxedBackgroundColorRunWithValue:previousRun]];
        }

        iTermBackgroundColorRunsInLine *fakeRuns = [[iTermBackgroundColorRunsInLine alloc] init];
        fakeRuns.line = runs.line;
        fakeRuns.sourceLine = runs.sourceLine;
        fakeRuns.y = runs.y;
        fakeRuns.numberOfEquivalentRows = runs.numberOfEquivalentRows;
        fakeRuns.array = combinedRuns;
        return fakeRuns;
    }];
    [self drawForegroundForBackgroundRunArrays:fakeRunArrays
                      drawOffscreenCommandLine:drawOffscreenCommandLine
                                           ctx:ctx
                                 virtualOffset:virtualOffset];
}

// Draws
- (void)drawForegroundForBackgroundRunArrays:(NSArray<iTermBackgroundColorRunsInLine *> *)backgroundRunArrays
                    drawOffscreenCommandLine:(BOOL)drawOffscreenCommandLine
                                         ctx:(CGContextRef)ctx
                               virtualOffset:(CGFloat)virtualOffset {
    iTermBackgroundColorRunsInLine *representativeRunArray = nil;
    NSInteger count = 0;
    const int firstLine = [self rangeOfVisibleRows].location;
    const CGFloat vmargin = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    for (iTermBackgroundColorRunsInLine *runArray in backgroundRunArrays) {
        if (count == 0) {
            representativeRunArray = runArray;
            count = runArray.numberOfEquivalentRows;
        }
        count--;
        const BOOL isOffscreenCommandLine = (_offscreenCommandLine && runArray.line == firstLine);
        CGFloat y = runArray.y;
        if (isOffscreenCommandLine && !drawOffscreenCommandLine) {
            continue;
        } else if (!isOffscreenCommandLine && drawOffscreenCommandLine) {
            continue;
        } else if (isOffscreenCommandLine && drawOffscreenCommandLine) {
            y -= vmargin + 1;
        }
        [self drawForegroundForSourceLineNumber:runArray.sourceLine
                              displayLineNumber:runArray.line
                                              y:y
                                 backgroundRuns:representativeRunArray.array
                                        context:ctx
                                  virtualOffset:virtualOffset];
    }
}

- (void)drawForegroundForSourceLineNumber:(int)sourceLineNumber
                        displayLineNumber:(int)displayLineNumber
                                  y:(CGFloat)y
                     backgroundRuns:(NSArray<iTermBoxedBackgroundColorRun *> *)backgroundRuns
                            context:(CGContextRef)ctx
                      virtualOffset:(CGFloat)virtualOffset {
    if (![self canDrawLine:displayLineNumber]) {
        return;
    }
    [self drawCharactersForDisplayLine:displayLineNumber
                            sourceLine:sourceLineNumber
                                   atY:y
                        backgroundRuns:backgroundRuns
                               context:ctx
                         virtualOffset:virtualOffset];
    if (sourceLineNumber == displayLineNumber) {
        [self drawNoteRangesOnLine:sourceLineNumber
                     virtualOffset:virtualOffset];
    }

    if (_debug) {
        NSString *s = [NSString stringWithFormat:@"%d", displayLineNumber];
        [s it_drawAtPoint:NSMakePoint(0, y)
           withAttributes:@{ NSForegroundColorAttributeName: [NSColor blackColor],
                             NSBackgroundColorAttributeName: [NSColor whiteColor],
                             NSFontAttributeName: [NSFont systemFontOfSize:8] }
            virtualOffset:virtualOffset];
    }
}

#pragma mark - Drawing: Text

- (void)drawCharactersForDisplayLine:(int)displayLine
                          sourceLine:(int)sourceLine
                          atY:(CGFloat)y
               backgroundRuns:(NSArray<iTermBoxedBackgroundColorRun *> *)backgroundRuns
                      context:(CGContextRef)ctx
                virtualOffset:(CGFloat)virtualOffset {
    const screen_char_t *theLine = [self lineAtIndex:sourceLine isFirst:nil];
    iTermImmutableMetadata metadata = [self.delegate drawingHelperMetadataOnLine:sourceLine];
    id<iTermExternalAttributeIndexReading> eaIndex = iTermImmutableMetadataGetExternalAttributesIndex(metadata);
    const BOOL rtlFound = metadata.rtlFound;
    NSData *matches = [_delegate drawingHelperMatchesOnLine:sourceLine];
    if (sourceLine != displayLine) {
        matches = nil;
    }
    for (iTermBoxedBackgroundColorRun *box in backgroundRuns) {
        iTermBackgroundColorRun *run = box.valuePointer;
        NSPoint textOrigin = NSMakePoint([iTermPreferences intForKey:kPreferenceKeySideMargins],
                                         y);
        [self constructAndDrawRunsForLine:theLine
                                 bidiInfo:rtlFound ? [self.delegate drawingHelperBidiInfoForLine:sourceLine] : nil
                       externalAttributes:eaIndex
                          sourceLineNumer:sourceLine
                        displayLineNumber:displayLine
                                  inRange:run->modelRange
                          startingAtPoint:textOrigin
                               bgselected:run->selected
                                  bgColor:box.unprocessedBackgroundColor
                 processedBackgroundColor:box.backgroundColor
                                 colorRun:box.valuePointer
                                  matches:matches
                           forceTextColor:nil
                                  context:ctx
                            virtualOffset:virtualOffset];
    }
}

- (void)constructAndDrawRunsForLine:(const screen_char_t *)theLine
                           bidiInfo:(iTermBidiDisplayInfo *)bidiInfo
                 externalAttributes:(id<iTermExternalAttributeIndexReading>)eaIndex
                    sourceLineNumer:(int)sourceLineNumber
                  displayLineNumber:(int)displayLineNumber
                            inRange:(NSRange)indexRange
                    startingAtPoint:(NSPoint)initialPoint
                         bgselected:(BOOL)bgselected
                            bgColor:(NSColor *)bgColor
           processedBackgroundColor:(NSColor *)processedBackgroundColor
                           colorRun:(iTermBackgroundColorRun *)colorRun
                            matches:(NSData *)matches
                     forceTextColor:(NSColor *)forceTextColor  // optional
                            context:(CGContextRef)ctx
                      virtualOffset:(CGFloat)virtualOffset {
    CTVector(CGFloat) positions;
    CTVectorCreate(&positions, _gridSize.width);

    if (indexRange.location > 0) {
        screen_char_t firstCharacter = theLine[indexRange.location];
        if (ScreenCharIsDWC_RIGHT(firstCharacter)) {
            // Don't try to start drawing in the middle of a double-width character.
            indexRange.location -= 1;
            indexRange.length += 1;
            initialPoint.x -= _cellSize.width;
        }
    }

    DLog(@"row %f: %@", (initialPoint.y - virtualOffset) / self.cellSize.height, ScreenCharArrayToStringDebug(theLine, _gridSize.width));

    iTermPreciseTimerStatsStartTimer(&_stats[TIMER_STAT_CONSTRUCTION]);
    NSArray<id<iTermAttributedString>> *attributedStrings =
    [_attributedStringBuilder attributedStringsForLine:theLine
                                              bidiInfo:bidiInfo
                                    externalAttributes:eaIndex
                                                 range:indexRange
                                       hasSelectedText:bgselected
                                       backgroundColor:bgColor
                                        forceTextColor:forceTextColor
                                              colorRun:colorRun
                                           findMatches:matches
                                       underlinedRange:[self underlinedRangeOnLine:sourceLineNumber + _totalScrollbackOverflow]
                                             positions:&positions];
    iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_STAT_CONSTRUCTION]);

    iTermPreciseTimerStatsStartTimer(&_stats[TIMER_STAT_DRAW]);
    NSPoint adjustedPoint = initialPoint;
    if (_offscreenCommandLine && displayLineNumber == [self rangeOfVisibleRows].location) {
        adjustedPoint.y += iTermOffscreenCommandLineVerticalPadding;
    }
    [self drawMultipartAttributedString:attributedStrings
                                atPoint:adjustedPoint
                                 origin:VT100GridCoordMake(indexRange.location, displayLineNumber)
                              positions:&positions
                              inContext:ctx
                        backgroundColor:processedBackgroundColor
                          virtualOffset:virtualOffset];

    CTVectorDestroy(&positions);
    iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_STAT_DRAW]);
}

- (void)drawMultipartAttributedString:(NSArray<id<iTermAttributedString>> *)attributedStrings
                              atPoint:(NSPoint)initialPoint
                               origin:(VT100GridCoord)initialOrigin
                            positions:(CTVector(CGFloat) *)positions
                            inContext:(CGContextRef)ctx
                      backgroundColor:(NSColor *)backgroundColor
                        virtualOffset:(CGFloat)virtualOffset {
    const NSPoint point = initialPoint;
    VT100GridCoord origin = initialOrigin;
    NSInteger start = 0;
    for (id<iTermAttributedString> singlePartAttributedString in attributedStrings) {
        CGFloat *subpositions = CTVectorElementsFromIndex(positions, start);
        start += singlePartAttributedString.length;
        int numCellsDrawn;
        if ([singlePartAttributedString isKindOfClass:[NSAttributedString class]]) {
            numCellsDrawn = [self drawSinglePartAttributedString:(NSAttributedString *)singlePartAttributedString
                                                         atPoint:point
                                                          origin:origin
                                                       positions:subpositions
                                                       inContext:ctx
                                                 backgroundColor:backgroundColor
                                                   virtualOffset:virtualOffset];
        } else {
            NSPoint offsetPoint = point;
            offsetPoint.y -= round((_cellSize.height - _cellSizeWithoutSpacing.height) / 2.0);
            numCellsDrawn = [self drawFastPathString:(iTermCheapAttributedString *)singlePartAttributedString
                                             atPoint:offsetPoint
                                     unadjustedPoint:point
                                              origin:origin
                                           positions:subpositions
                                           inContext:ctx
                                     backgroundColor:backgroundColor
                                       virtualOffset:virtualOffset];
        }
//        [[NSColor colorWithRed:arc4random_uniform(255) / 255.0
//                         green:arc4random_uniform(255) / 255.0
//                          blue:arc4random_uniform(255) / 255.0
//                         alpha:1] set];
//        iTermFrameRect(NSMakeRect(point.x + subpositions[0], point.y, numCellsDrawn * _cellSize.width, _cellSize.height), virtualOffset);

        origin.x += numCellsDrawn;

    }
}

- (void)drawBoxDrawingCharacter:(unichar)theCharacter
                 withAttributes:(NSDictionary *)attributes
                             at:(NSPoint)pos
                  virtualOffset:(CGFloat)virtualOffset {
    NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
    [ctx saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:pos.x yBy:pos.y - virtualOffset];
    [transform concat];

    CGColorRef color = (__bridge CGColorRef)attributes[(__bridge NSString *)kCTForegroundColorAttributeName];
    [iTermBoxDrawingBezierCurveFactory drawCodeInCurrentContext:theCharacter
                                                       cellSize:_cellSize
                                                          scale:self.isRetina ? 2.0 : 1.0
                                                       isPoints:YES
                                                         offset:CGPointZero
                                                          color:color
                                       useNativePowerlineGlyphs:self.useNativePowerlineGlyphs];
    [ctx restoreGraphicsState];
}

- (void)selectFont:(NSFont *)font inContext:(CGContextRef)ctx {
    if (font != _cachedFont) {
        _cachedFont = font;
        if (_cgFont) {
            CFRelease(_cgFont);
        }
        _cgFont = CTFontCopyGraphicsFont((__bridge CTFontRef)font, NULL);
    }
    CGContextSetFont(ctx, _cgFont);
    CGContextSetFontSize(ctx, font.pointSize);
}

- (int)setSmoothingWithContext:(CGContextRef)ctx
       savedFontSmoothingStyle:(int *)savedFontSmoothingStyle
                useThinStrokes:(BOOL)useThinStrokes
                    antialised:(BOOL)antialiased {
    return iTermSetSmoothing(ctx, savedFontSmoothingStyle, useThinStrokes, antialiased);
}

// Just like drawTextOnlyAttributedString but 2-3x faster. Uses
// CGContextShowGlyphsAtPositions instead of CTFontDrawGlyphs.
// NOTE: point is adjusted when vertical spacing is not 100% to vertically center the text box.
// unadjustedPoint gives the bottom of the line.
- (int)drawFastPathString:(iTermCheapAttributedString *)cheapString
                  atPoint:(NSPoint)point
          unadjustedPoint:(NSPoint)unadjustedPoint
                   origin:(VT100GridCoord)origin
                positions:(CGFloat *)positions
                inContext:(CGContextRef)ctx
          backgroundColor:(NSColor *)backgroundColor
            virtualOffset:(CGFloat)virtualOffset {
    if ([cheapString.attributes[iTermIsBoxDrawingAttribute] boolValue]) {
        // Special box-drawing cells don't use the font so they look prettier.
        unichar *chars = (unichar *)cheapString.characters;
        for (NSUInteger i = 0; i < cheapString.length; i++) {
            unichar c = chars[i];
            NSPoint p = NSMakePoint(unadjustedPoint.x + positions[i], unadjustedPoint.y);
            [self drawBoxDrawingCharacter:c
                           withAttributes:cheapString.attributes
                                       at:p
                            virtualOffset:virtualOffset];
        }
        return cheapString.length;
    }
    int result = [self drawFastPathStringWithoutUnderlineOrStrikethrough:cheapString
                                                                 atPoint:point
                                                                  origin:origin
                                                               positions:positions
                                                               inContext:ctx
                                                         backgroundColor:backgroundColor
                                                                   smear:NO
                                                           virtualOffset:virtualOffset];
    [self drawUnderlineOrStrikethroughForFastPathString:cheapString
                                          wantUnderline:YES
                                                atPoint:point
                                              positions:positions
                                        backgroundColor:backgroundColor
                                          virtualOffset:virtualOffset];

    [self drawUnderlineOrStrikethroughForFastPathString:cheapString
                                          wantUnderline:NO
                                                atPoint:point
                                              positions:positions
                                        backgroundColor:backgroundColor
                                          virtualOffset:virtualOffset];
    return result;
}

- (int)drawFastPathStringWithoutUnderlineOrStrikethrough:(iTermCheapAttributedString *)cheapString
                                                 atPoint:(NSPoint)point
                                                  origin:(VT100GridCoord)origin
                                               positions:(CGFloat *)positions
                                               inContext:(CGContextRef)ctx
                                         backgroundColor:(NSColor *)backgroundColor
                                                   smear:(BOOL)smear
                                           virtualOffset:(CGFloat)virtualOffset {
    if (cheapString.length == 0) {
        return 0;
    }
    NSDictionary *attributes = cheapString.attributes;
    if (attributes[iTermImageCodeAttribute]) {
        // Handle cells that are part of an image.
        VT100GridCoord originInImage = VT100GridCoordMake([attributes[iTermImageColumnAttribute] intValue],
                                                          [attributes[iTermImageLineAttribute] intValue]);
        const int displayColumn = [attributes[iTermImageDisplayColumnAttribute] intValue];
        [self drawImageWithCode:[attributes[iTermImageCodeAttribute] shortValue]
                         origin:VT100GridCoordMake(displayColumn, origin.y)
                         length:cheapString.length
                        atPoint:NSMakePoint(positions[0] + point.x, point.y)
                  originInImage:originInImage
                  virtualOffset:virtualOffset];
        return cheapString.length;
    } else if (attributes[iTermKittyImageIDAttribute]) {
        // Handle cells that are part of a Kitty image.
        const VT100GridCoord coord = VT100GridCoordMake([attributes[iTermKittyImageColumnAttribute] intValue],
                                                          [attributes[iTermKittyImageRowAttribute] intValue]);
        const int displayColumn = [attributes[iTermImageDisplayColumnAttribute] intValue];
        [self drawKittyImageInPlaceholderWithCoord:coord
                                            origin:VT100GridCoordMake(displayColumn, origin.y)
                                           atPoint:NSMakePoint(positions[0] + point.x, point.y)
                                           imageID:[attributes[iTermKittyImageIDAttribute] unsignedIntegerValue]
                                       placementID:[attributes[iTermKittyImagePlacementIDAttribute] unsignedIntegerValue]
                                     virtualOffset:virtualOffset];
        return 1;
    }

    CGGlyph glyphs[cheapString.length];
    NSFont *const font = cheapString.attributes[NSFontAttributeName];
    BOOL ok = CTFontGetGlyphsForCharacters((CTFontRef)font,
                                           cheapString.characters,
                                           glyphs,
                                           cheapString.length);
    if (!ok) {
        NSString *string = [NSString stringWithCharacters:cheapString.characters
                                                   length:cheapString.length];
        [self drawTextOnlyAttributedStringWithoutUnderlineOrStrikethrough:[NSAttributedString attributedStringWithString:string
                                                                                                              attributes:cheapString.attributes]
                                                                  atPoint:point
                                                                positions:positions
                                                          backgroundColor:backgroundColor
                                                          graphicsContext:[NSGraphicsContext currentContext]
                                                                    smear:NO
                                                            virtualOffset:virtualOffset];
        return cheapString.length;
    }
    CGColorRef const color = (__bridge CGColorRef)cheapString.attributes[(__bridge NSString *)kCTForegroundColorAttributeName];
    const BOOL fakeItalic = [cheapString.attributes[iTermFakeItalicAttribute] boolValue];
    const BOOL fakeBold = [cheapString.attributes[iTermFakeBoldAttribute] boolValue];
    const BOOL antiAlias = !smear && [cheapString.attributes[iTermAntiAliasAttribute] boolValue];

    CGContextSetShouldAntialias(ctx, antiAlias);

    const CGFloat *components = CGColorGetComponents(color);
    const BOOL useThinStrokes = [self useThinStrokesAgainstBackgroundColor:backgroundColor
                                                           foregroundColor:color];
    int savedFontSmoothingStyle = 0;
    int style = [self setSmoothingWithContext:ctx
                      savedFontSmoothingStyle:&savedFontSmoothingStyle
                               useThinStrokes:useThinStrokes
                                   antialised:antiAlias];

    size_t numCodes = cheapString.length;
    size_t length = numCodes;
    [self selectFont:font inContext:ctx];
    CGContextSetFillColorSpace(ctx, CGColorGetColorSpace(color));
    if (CGColorGetAlpha(color) < 1) {
        CGContextSetBlendMode(ctx, kCGBlendModeSourceAtop);
    }
    CGContextSetFillColor(ctx, components);
    double y = point.y + _cellSize.height + _baselineOffset - virtualOffset;
    int x = point.x + positions[0];
    // Flip vertically and translate to (x, y).
    CGFloat m21 = 0.0;
    if (fakeItalic) {
        m21 = 0.2;
    }
    CGContextSetTextMatrix(ctx, CGAffineTransformMake(1.0,  0.0,
                                                      m21, -1.0,
                                                      x, y));

    CGPoint points[length];
    for (int i = 0; i < length; i++) {
        points[i].x = positions[i] - positions[0];
        points[i].y = 0;
    }

    if (smear) {
        const int radius = 1;
        CGContextTranslateCTM(ctx, -radius, 0);
        for (int i = 0; i <= radius * 4; i++) {
            CGContextShowGlyphsAtPositions(ctx, glyphs, points, length);
            CGContextTranslateCTM(ctx, 0, 1);
            CGContextShowGlyphsAtPositions(ctx, glyphs, points, length);
            CGContextTranslateCTM(ctx, 0, -2);
            CGContextShowGlyphsAtPositions(ctx, glyphs, points, length);
            CGContextTranslateCTM(ctx, 0.5, 1);
        }
        CGContextTranslateCTM(ctx, -radius - 0.5, 0);
    } else {
        CGContextShowGlyphsAtPositions(ctx, glyphs, points, length);

        if (fakeBold) {
            // If anti-aliased, drawing twice at the same position makes the strokes thicker.
            // If not anti-alised, draw one pixel to the right.
            CGContextSetTextMatrix(ctx, CGAffineTransformMake(1.0,  0.0,
                                                              m21, -1.0,
                                                              x + (antiAlias ? _antiAliasedShift : 1),
                                                              y));

            CGContextShowGlyphsAtPositions(ctx, glyphs, points, length);
        }
    }
#if 0
    // Indicates which regions were drawn with the fastpath
    [[NSColor yellowColor] set];
    NSFrameRect(NSMakeRect(point.x + positions[0], point.y, positions[length - 1] - positions[0] + _cellSize.width, _cellSize.height));
#endif

    if (style >= 0) {
        CGContextSetFontSmoothingStyle(ctx, savedFontSmoothingStyle);
    }
    if (CGColorGetAlpha(color) < 1) {
        CGContextSetBlendMode(ctx, kCGBlendModeNormal);
    }

    return length;
}

- (NSColor *)underlineColorForAttributes:(NSDictionary *)attributes {
    // First, use value in attribute if it is present.
    const BOOL hasUnderlineColor = [attributes[iTermHasUnderlineColorAttribute] boolValue];
    if (hasUnderlineColor) {
        NSArray<NSNumber *> *components = attributes[iTermUnderlineColorAttribute];
        return [self.delegate drawingHelperColorForCode:components[0].intValue
                                                  green:components[1].intValue
                                                   blue:components[2].intValue
                                              colorMode:components[3].intValue
                                                   bold:[attributes[iTermBoldAttribute] boolValue]
                                                  faint:[attributes[iTermFaintAttribute] boolValue]
                                           isBackground:NO];
    }

    // Use the optional profile setting, if any.
    NSColor *underline = [self.colorMap colorForKey:kColorMapUnderline];
    if (underline) {
        return underline;
    }

    // Fall back to text color.
    CGColorRef cgColor = (__bridge CGColorRef)attributes[(NSString *)kCTForegroundColorAttributeName];
    return [NSColor colorWithCGColor:cgColor];
}

- (void)drawUnderlineOrStrikethroughForFastPathString:(iTermCheapAttributedString *)cheapString
                                        wantUnderline:(BOOL)wantUnderline
                                              atPoint:(NSPoint)origin
                                            positions:(CGFloat *)stringPositions
                                      backgroundColor:(NSColor *)backgroundColor
                                        virtualOffset:(CGFloat)virtualOffset {
    NSDictionary *const attributes = cheapString.attributes;
    NSNumber *value = attributes[wantUnderline ? NSUnderlineStyleAttributeName : NSStrikethroughStyleAttributeName];
    NSUnderlineStyle underlineStyle = value.integerValue;
    if (underlineStyle == NSUnderlineStyleNone) {
        return;
    }

    iTermUnderlineContext storage = {
        .maskGraphicsContext = nil,
        .alphaMask = nil,
    };
    iTermUnderlineContext *underlineContext = &storage;

    const NSRange range = NSMakeRange(0, cheapString.length);
    const NSSize size = NSMakeSize([attributes[iTermUnderlineLengthAttribute] intValue] * _cellSize.width,
                                   _cellSize.height * 2);
    const CGFloat xOrigin = origin.x + stringPositions[range.location];
    const NSRect rect = NSMakeRect(xOrigin,
                                   origin.y,
                                   size.width,
                                   size.height);
    NSColor *underlineColor = [self underlineColorForAttributes:attributes];
    [self drawUnderlinedOrStruckthroughTextWithContext:underlineContext
                                         wantUnderline:wantUnderline
                                                inRect:rect
                                        underlineColor:underlineColor
                                                 style:underlineStyle
                                                  font:attributes[NSFontAttributeName]
                                         virtualOffset:virtualOffset
                                                 block:
     ^(CGContextRef ctx) {
        if (cheapString.length == 0) {
            return;
        }
        if (!wantUnderline) {
            return;
        }
        NSMutableDictionary *attrs = [cheapString.attributes mutableCopy];
        CGFloat components[4] = { 0, 0, 0, 1 };
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGColorRef black = CGColorCreate(colorSpace,
                                         components);
        attrs[(__bridge NSString *)kCTForegroundColorAttributeName] = (__bridge id)black;

        iTermCheapAttributedString *blackCopy = [cheapString copyWithAttributes:attrs];
        [self drawFastPathStringWithoutUnderlineOrStrikethrough:blackCopy
                                                        atPoint:NSMakePoint(-stringPositions[0], 0)
                                                         origin:VT100GridCoordMake(-1, -1)  // only needed by images
                                                      positions:stringPositions
                                                      inContext:[[NSGraphicsContext currentContext] CGContext]
                                                backgroundColor:backgroundColor
                                                          smear:YES
                                                  virtualOffset:0];
        CFRelease(colorSpace);
        CFRelease(black);
    }];

    if (underlineContext->maskGraphicsContext) {
        CGContextRelease(underlineContext->maskGraphicsContext);
    }
    if (underlineContext->alphaMask) {
        CGImageRelease(underlineContext->alphaMask);
    }
}

- (int)drawSinglePartAttributedString:(NSAttributedString *)attributedString
                              atPoint:(NSPoint)point
                               origin:(VT100GridCoord)origin
                            positions:(CGFloat *)positions
                            inContext:(CGContextRef)ctx
                      backgroundColor:(NSColor *)backgroundColor
                        virtualOffset:(CGFloat)virtualOffset {
    NSDictionary *attributes = [attributedString attributesAtIndex:0 effectiveRange:nil];
    NSPoint offsetPoint = point;
    offsetPoint.y -= round((_cellSize.height - _cellSizeWithoutSpacing.height) / 2.0);
    if (attributes[iTermImageCodeAttribute]) {
        // Handle cells that are part of an image.
        VT100GridCoord originInImage = VT100GridCoordMake([attributes[iTermImageColumnAttribute] intValue],
                                                          [attributes[iTermImageLineAttribute] intValue]);
        int displayColumn = [attributes[iTermImageDisplayColumnAttribute] intValue];
        [self drawImageWithCode:[attributes[iTermImageCodeAttribute] shortValue]
                         origin:VT100GridCoordMake(displayColumn, origin.y)
                         length:attributedString.length
                        atPoint:NSMakePoint(positions[0] + point.x, offsetPoint.y)
                  originInImage:originInImage
                  virtualOffset:virtualOffset];
        return attributedString.length;
    } else if ([attributes[iTermIsBoxDrawingAttribute] boolValue]) {
        // Special box-drawing cells don't use the font so they look prettier.
        [attributedString.string enumerateComposedCharacters:^(NSRange range, unichar simple, NSString *complexString, BOOL *stop) {
            NSPoint p = NSMakePoint(point.x + positions[range.location], point.y);
            [self drawBoxDrawingCharacter:simple
                           withAttributes:[attributedString attributesAtIndex:range.location
                                                               effectiveRange:nil]
                                       at:p
                            virtualOffset:virtualOffset];
        }];
        return attributedString.length;
    } else if (attributedString.length > 0) {
        [self drawTextOnlyAttributedString:attributedString
                                   atPoint:offsetPoint
                                 positions:positions
                           backgroundColor:backgroundColor
                             virtualOffset:virtualOffset];
        return attributedString.length;
    } else {
        // attributedString is empty
        return 0;
    }
}

- (void)drawTextOnlyAttributedStringWithoutUnderlineOrStrikethrough:(NSAttributedString *)attributedString
                                                            atPoint:(NSPoint)origin
                                                          positions:(CGFloat *)xOriginsForCharacters
                                                    backgroundColor:(NSColor *)backgroundColor
                                                    graphicsContext:(NSGraphicsContext *)ctx
                                                              smear:(BOOL)smear
                                                      virtualOffset:(CGFloat)virtualOffset {
    if (attributedString.length == 0) {
        return;
    }
    NSDictionary *attributes = [attributedString attributesAtIndex:0 effectiveRange:nil];
    CGColorRef cgColor = (__bridge CGColorRef)attributes[(NSString *)kCTForegroundColorAttributeName];

    BOOL bold = [attributes[iTermBoldAttribute] boolValue];
    __block BOOL fakeBold = [attributes[iTermFakeBoldAttribute] boolValue];
    BOOL fakeItalic = [attributes[iTermFakeItalicAttribute] boolValue];
    BOOL antiAlias = !smear && [attributes[iTermAntiAliasAttribute] boolValue];

    [ctx saveGraphicsState];
    [ctx setCompositingOperation:NSCompositingOperationSourceOver];

    // We used to use -[NSAttributedString drawWithRect:options] but
    // it does a lousy job rendering multiple combining marks. This is close
    // to what WebKit does and appears to be the highest quality text
    // rendering available.

    CTLineRef lineRef;
    iTermAttributedStringProxy *proxy = [iTermAttributedStringProxy withAttributedString:attributedString];
    lineRef = (__bridge CTLineRef)_lineRefCache[proxy];
    if (lineRef == nil) {
        lineRef = CTLineCreateWithAttributedString((CFAttributedStringRef)attributedString);
        _lineRefCache[proxy] = (__bridge id)lineRef;
        CFRelease(lineRef);
    }
    _replacementLineRefCache[proxy] = (__bridge id)lineRef;

    CGContextRef cgContext = (CGContextRef) [ctx CGContext];
    CGContextSetShouldAntialias(cgContext, antiAlias);
    CGContextSetFillColorWithColor(cgContext, cgColor);
    CGContextSetStrokeColorWithColor(cgContext, cgColor);

    CGFloat c = 0.0;
    if (fakeItalic) {
        c = 0.2;
    }

    BOOL useThinStrokes = [self useThinStrokesAgainstBackgroundColor:backgroundColor
                                                     foregroundColor:cgColor];
    int savedFontSmoothingStyle = 0;
    int style = [self setSmoothingWithContext:cgContext
                      savedFontSmoothingStyle:&savedFontSmoothingStyle
                               useThinStrokes:useThinStrokes
                                   antialised:antiAlias];

    const CGFloat ty = origin.y + _baselineOffset + _cellSize.height - virtualOffset;
    CGAffineTransform textMatrix = CGAffineTransformMake(1.0, 0.0,
                                                         c, -1.0,
                                                         origin.x, ty);
    CGContextSetTextMatrix(cgContext, textMatrix);
    const BOOL verbose = NO;  // turn this on to debug character position problems.
    if (verbose) {
        NSLog(@"Begin drawing string: %@", attributedString.string);
    }

    NSData *drawInCellIndex = attributes[iTermDrawInCellIndexAttribute];
    iTermCoreTextLineRenderingHelper *renderingHelper = [[iTermCoreTextLineRenderingHelper alloc] initWithLine:lineRef
                                                                                                        string:attributedString.string
                                                                                               drawInCellIndex:drawInCellIndex];
    [renderingHelper enumerateGridAlignedRunsWithColumnPositions:xOriginsForCharacters
                                                     alignToZero:NO
                                                         closure:^(CTRunRef run,
                                                                   CTFontRef runFont,
                                                                   const CGGlyph *buffer,
                                                                   const NSPoint *positions,
                                                                   const CFIndex *glyphIndexToCharacterIndex,
                                                                   size_t length,
                                                                   BOOL *stop) {
        if (!smear) {
            CTFontDrawGlyphs(runFont, buffer, (NSPoint *)positions, length, cgContext);

            if (bold && !fakeBold) {
                // If this text is supposed to be bold, but the font is not, use double-struck text. Issue 4956.
                CTFontSymbolicTraits traits = CTFontGetSymbolicTraits(runFont);
                fakeBold = !(traits & kCTFontTraitBold);
            }

            if (fakeBold && _boldAllowed) {
                CGContextTranslateCTM(cgContext, antiAlias ? _antiAliasedShift : 1, 0);
                CTFontDrawGlyphs(runFont, buffer, (NSPoint *)positions, length, cgContext);
                CGContextTranslateCTM(cgContext, antiAlias ? -_antiAliasedShift : -1, 0);
            }
        } else {
            const int radius = 1;

            CGContextTranslateCTM(cgContext, -radius, 0);
            for (int i = 0; i <= radius * 4; i++) {
                CTFontDrawGlyphs(runFont, buffer, (NSPoint *)positions, length, cgContext);
                CGContextTranslateCTM(cgContext, 0, 1);
                CTFontDrawGlyphs(runFont, buffer, (NSPoint *)positions, length, cgContext);
                CGContextTranslateCTM(cgContext, 0, -2);
                CTFontDrawGlyphs(runFont, buffer, (NSPoint *)positions, length, cgContext);
                CGContextTranslateCTM(cgContext, 0.5, 1);
            }
            CGContextTranslateCTM(cgContext, -radius - 0.5, 0);
        }
    }];

    if (verbose) {
        NSLog(@"");
    }

    if (style >= 0) {
        CGContextSetFontSmoothingStyle(cgContext, savedFontSmoothingStyle);
    }

    [ctx restoreGraphicsState];
}

- (void)drawTextOnlyAttributedString:(NSAttributedString *)attributedString
                             atPoint:(NSPoint)origin
                           positions:(CGFloat *)stringPositions
                     backgroundColor:(NSColor *)backgroundColor
                       virtualOffset:(CGFloat)virtualOffset {
    NSGraphicsContext *graphicsContext = [NSGraphicsContext currentContext];

    [self drawTextOnlyAttributedStringWithoutUnderlineOrStrikethrough:attributedString
                                                              atPoint:origin
                                                            positions:stringPositions
                                                      backgroundColor:backgroundColor
                                                      graphicsContext:graphicsContext
                                                                smear:NO
                                                        virtualOffset:virtualOffset];
    [self drawUnderlineAndStrikethroughForAttributedString:attributedString
                                                   atPoint:origin
                                                 positions:stringPositions
                                             wantUnderline:YES
                                             virtualOffset:virtualOffset];
    [self drawUnderlineAndStrikethroughForAttributedString:attributedString
                                                   atPoint:origin
                                                 positions:stringPositions
                                             wantUnderline:NO
                                             virtualOffset:virtualOffset];
}

- (void)drawUnderlineAndStrikethroughForAttributedString:(NSAttributedString *)attributedString
                                                 atPoint:(NSPoint)origin
                                               positions:(CGFloat *)stringPositions
                                           wantUnderline:(BOOL)wantUnderline
                                           virtualOffset:(CGFloat)virtualOffset {
    iTermUnderlineContext storage = {
        .maskGraphicsContext = nil,
        .alphaMask = nil,
    };
    iTermUnderlineContext *underlineContext = &storage;

    [attributedString enumerateAttribute:wantUnderline ? NSUnderlineStyleAttributeName : NSStrikethroughStyleAttributeName
                                 inRange:NSMakeRange(0, attributedString.length)
                                 options:0
                              usingBlock:
     ^(NSNumber * _Nullable value, NSRange range, BOOL * _Nonnull stop) {
        NSUnderlineStyle underlineStyle = value.integerValue;
        if (underlineStyle == NSUnderlineStyleNone) {
            return;
        }
        NSDictionary *const attributes = [attributedString attributesAtIndex:range.location
                                                              effectiveRange:nil];
        CGFloat minX = INFINITY;
        CGFloat maxX = -INFINITY;
        for (NSInteger i = 0; i < range.length; i++) {
            minX = MIN(minX, stringPositions[range.location + i]);
            maxX = MAX(maxX, stringPositions[range.location + i] + _cellSize.width);
        }
        const NSSize size = NSMakeSize(maxX - minX, _cellSize.height * 2);
        const CGFloat xOrigin = origin.x + minX;
        const NSRect rect = NSMakeRect(xOrigin,
                                       origin.y,
                                       size.width,
                                       size.height);
        NSColor *underlineColor = [self underlineColorForAttributes:attributes];
        [self drawUnderlinedOrStruckthroughTextWithContext:underlineContext
                                             wantUnderline:wantUnderline
                                                    inRect:rect
                                            underlineColor:underlineColor
                                                     style:underlineStyle
                                                      font:attributes[NSFontAttributeName]
                                             virtualOffset:virtualOffset
                                                     block:
         ^(CGContextRef ctx) {
            if (!wantUnderline) {
                // This is a shortcut to prefer simplicity over speed.
                // Underline and strikethrough are very similar except for
                // masking. For strikethrough, we draw an empty mask. If this
                // becomes a performance issue, we can skip drawing the empty
                // mask.
                return;
            }
            [self drawAttributedStringForMask:attributedString
                                       origin:NSMakePoint(-stringPositions[range.location], 0)
                              stringPositions:stringPositions];
        }];
    }];

    if (underlineContext->maskGraphicsContext) {
        CGContextRelease(underlineContext->maskGraphicsContext);
    }
    if (underlineContext->alphaMask) {
        CGImageRelease(underlineContext->alphaMask);
    }
}

// Block should draw text with origin of 0,0
- (void)drawUnderlinedOrStruckthroughTextWithContext:(iTermUnderlineContext *)underlineContext
                                       wantUnderline:(BOOL)wantUnderline
                                              inRect:(NSRect)rect
                                      underlineColor:(NSColor *)underlineColor
                                               style:(NSUnderlineStyle)underlineStyle
                                                font:(NSFont *)font
                                       virtualOffset:(CGFloat)virtualOffset
                                               block:(void (^)(CGContextRef))block {
    if ([iTermAdvancedSettingsModel solidUnderlines]) {
        [self drawUnderlineOrStrikethroughOfColor:underlineColor
                                    wantUnderline:wantUnderline
                                            style:underlineStyle
                                             font:font
                                             rect:rect
                                    virtualOffset:virtualOffset];
        return;
    }
    if (!underlineContext->maskGraphicsContext) {
        // Create a mask image.
        [self initializeUnderlineContext:underlineContext
                                  ofSize:rect.size
                                   block:block];
    }

    NSGraphicsContext *graphicsContext = [NSGraphicsContext currentContext];
    CGContextRef cgContext = (CGContextRef)[graphicsContext CGContext];
    [self drawInContext:cgContext
                 inRect:rect
              alphaMask:underlineContext->alphaMask
          virtualOffset:virtualOffset
                  block:^{
                      [self drawUnderlineOrStrikethroughOfColor:underlineColor
                                                  wantUnderline:wantUnderline
                                                          style:underlineStyle
                                                           font:font
                                                           rect:rect
                                                  virtualOffset:virtualOffset];
                  }];
}

- (NSAttributedString *)attributedString:(NSAttributedString *)attributedString
              bySettingForegroundColorTo:(CGColorRef)color {
    NSMutableAttributedString *modifiedAttributedString = [attributedString mutableCopy];
    NSRange fullRange = NSMakeRange(0, modifiedAttributedString.length);

    [modifiedAttributedString removeAttribute:(NSString *)kCTForegroundColorAttributeName range:fullRange];

    NSDictionary *maskingAttributes = @{ (__bridge NSString *)kCTForegroundColorAttributeName:(__bridge id)color };
    [modifiedAttributedString addAttributes:maskingAttributes range:fullRange];

    return modifiedAttributedString;
}

- (void)drawAttributedStringForMask:(NSAttributedString *)attributedString
                             origin:(NSPoint)origin
                    stringPositions:(CGFloat *)stringPositions {
    CGColorRef black = [[NSColor it_colorInDefaultColorSpaceWithRed:0 green:0 blue:0 alpha:1] CGColor];
    NSAttributedString *modifiedAttributedString = [self attributedString:attributedString
                                               bySettingForegroundColorTo:black];

    [self drawTextOnlyAttributedStringWithoutUnderlineOrStrikethrough:modifiedAttributedString
                                                              atPoint:origin
                                                            positions:stringPositions
                                                      backgroundColor:[NSColor it_colorInDefaultColorSpaceWithRed:1 green:1 blue:1 alpha:1]
                                                      graphicsContext:[NSGraphicsContext currentContext]
                                                                smear:YES
                                                        virtualOffset:0];
}

- (void)initializeUnderlineContext:(iTermUnderlineContext *)underlineContext
                            ofSize:(NSSize)size
                             block:(void (^)(CGContextRef))block {
    underlineContext->maskGraphicsContext = [self newGrayscaleContextOfSize:size];
    [NSGraphicsContext saveGraphicsState];

    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:underlineContext->maskGraphicsContext
                                                                                 flipped:NO]];

    // Draw the background
    [[NSColor whiteColor] setFill];
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    CGContextFillRect(ctx,
                      NSMakeRect(0, 0, size.width, size.height));


    // Draw smeared text into the alpha mask context.
    block(ctx);


    // Switch back to the window's context
    [NSGraphicsContext restoreGraphicsState];

    // Create an image mask from what we've drawn so far
    underlineContext->alphaMask = CGBitmapContextCreateImage(underlineContext->maskGraphicsContext);
}

- (void)drawInContext:(CGContextRef)cgContext
               inRect:(NSRect)rect
            alphaMask:(CGImageRef)alphaMask
        virtualOffset:(CGFloat)virtualOffset
                block:(void (^)(void))block {
    // Mask it
    CGContextSaveGState(cgContext);
    CGContextClipToMask(cgContext,
                        NSRectSubtractingVirtualOffset(rect, virtualOffset),
                        alphaMask);


    block();

    // Remove mask
    CGContextRestoreGState(cgContext);
}

- (CGContextRef)newGrayscaleContextOfSize:(NSSize)size {
    CGFloat scale = self.isRetina ? 2.0 : 1.0;
    CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceGray();
    CGContextRef maskContext = CGBitmapContextCreate(NULL,
                                                     size.width * scale,
                                                     size.height * scale,
                                                     8,  // bits per component
                                                     size.width * scale,
                                                     colorspace,
                                                     0);  // bitmap info
    CGContextScaleCTM(maskContext, scale, scale);
    CGColorSpaceRelease(colorspace);
    return maskContext;
}

NSColor *iTermTextDrawingHelperTextColorForMatch(NSColor *bgColor) {
    return bgColor.isDark ? [NSColor colorWithCalibratedRed:1 green:1 blue:1 alpha:1] : [NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:1];
}

static unsigned int VT100TerminalColorValueToKittyImageNumber(VT100TerminalColorValue colorValue,
                                                              int msb) {
    unsigned int shiftedMSB = ((unsigned int)msb) << 24;

    if (colorValue.mode == ColorModeNormal) {
        return shiftedMSB | (unsigned int)colorValue.red;
    }

    if (colorValue.mode == ColorMode24bit) {
        return (shiftedMSB |
                (((unsigned int)colorValue.red) << 16) |
                (((unsigned int)colorValue.green) << 8) |
                (((unsigned int)colorValue.blue) << 0));
    }

    // If the color mode is not valid, return the error code 0xffffffff
    return 0xffffffff;
}

void iTermKittyUnicodePlaceholderStateInit(iTermKittyUnicodePlaceholderState *state) {
    state->previousCoord = VT100GridCoordMake(-1, -1);
    state->previousImageMSB = -1;
    state->runLength = 0;
}

BOOL iTermDecodeKittyUnicodePlaceholder(const screen_char_t *c,
                                        iTermExternalAttribute *ea,
                                        iTermKittyUnicodePlaceholderState *state,
                                        iTermKittyUnicodePlaceholderInfo *info) {
    NSString *s = ScreenCharToKittyPlaceholder(c);
    VT100GridCoord coord;
    int imageMSB = -1;
    if (![s parseKittyUnicodePlaceholder:&coord imageMSB:&imageMSB]) {
        return NO;
    }
    if (coord.x == -1 && state->previousCoord.x != -1) {
        coord.x = state->previousCoord.x + 1;
    }
    if (coord.y == -1 && state->previousCoord.y != -1) {
        coord.y = state->previousCoord.y;
    }
    state->previousCoord = coord;
    if (state->previousImageMSB != -1 && imageMSB == -1) {
        imageMSB = state->previousImageMSB;
    } else if (imageMSB != -1) {
        state->previousImageMSB = imageMSB;
    }
    if (coord.y != -1) {
        state->runLength = 1;
    } else {
        state->runLength += 1;
    }
    VT100TerminalColorValue colorValue = {
        .red = c->foregroundColor,
        .green = c->fgGreen,
        .blue = c->fgBlue,
        .mode = c->foregroundColorMode
    };
    unsigned int imageID = VT100TerminalColorValueToKittyImageNumber(colorValue, imageMSB);
    unsigned int placementID = ea.hasUnderlineColor ? VT100TerminalColorValueToKittyImageNumber(ea.underlineColor, 0) : 0;

    *info = (iTermKittyUnicodePlaceholderInfo) {
        .row = coord.y,
        .column = coord.x,
        .imageID = imageID,
        .placementID = placementID,
        .runLength = state->runLength
    };
    return YES;
}

- (BOOL)zippy {
    return (!(_asciiLigaturesAvailable && _asciiLigatures) &&
            !(_nonAsciiLigatures) &&
            [iTermAdvancedSettingsModel zippyTextDrawing]);
}

- (int)lengthOfRTLRunInLine:(const screen_char_t *)line length:(int)length {
    for (int i = 0; i < length; i++) {
        if (line[i].rtlStatus != RTLStatusRTL) {
            return i;
        }
    }
    return length;
}

- (BOOL)useThinStrokesAgainstBackgroundColor:(NSColor *)backgroundColor
                             foregroundColor:(CGColorRef)foregroundColor {
    const CGFloat *components = CGColorGetComponents(foregroundColor);

    switch (self.thinStrokes) {
        case iTermThinStrokesSettingAlways:
            return YES;

        case iTermThinStrokesSettingDarkBackgroundsOnly:
            break;

        case iTermThinStrokesSettingNever:
            return NO;

        case iTermThinStrokesSettingRetinaDarkBackgroundsOnly:
            if (!_isRetina) {
                return NO;
            }
            break;

        case iTermThinStrokesSettingRetinaOnly:
            return _isRetina;
    }
    return [backgroundColor brightnessComponent] < PerceivedBrightness(components[0], components[1], components[2]);
}

// Larger values are lower
- (CGFloat)yOriginForUnderlineForFont:(NSFont *)font yOffset:(CGFloat)yOffset cellHeight:(CGFloat)cellHeight {
    const CGFloat xHeight = font.xHeight;
    // Keep the underline a reasonable distance from the baseline.
    CGFloat underlineOffset = _underlineOffset;
    CGFloat distanceFromBaseline = underlineOffset - _baselineOffset;
    const CGFloat minimumDistance = [self retinaRound:xHeight * 0.4];
    if (distanceFromBaseline < minimumDistance) {
        underlineOffset = _baselineOffset + minimumDistance;
    } else if (distanceFromBaseline > xHeight / 2) {
        underlineOffset = _baselineOffset + xHeight / 2;
    }
    CGFloat scaleFactor = self.isRetina ? 2.0 : 1.0;
    CGFloat preferredOffset = [self retinaRound:yOffset + _cellSize.height + underlineOffset] - 1.0 / (2 * scaleFactor);

    const CGFloat thickness = [self underlineThicknessForFont:font];
    const CGFloat roundedPreferredOffset = [self retinaRound:preferredOffset];
    const CGFloat maximumOffset = [self retinaFloor:yOffset + cellHeight - thickness];
    return MIN(roundedPreferredOffset, maximumOffset);
}

// Larger values are lower
- (CGFloat)yOriginForStrikethroughForFont:(NSFont *)font yOffset:(CGFloat)yOffset cellHeight:(CGFloat)cellHeight {
    const CGFloat xHeight = font.xHeight;
    // Keep the underline a reasonable distance from the baseline.
    CGFloat underlineOffset = self.baselineOffset - xHeight / 2.0;
    return [self retinaRound:yOffset + _cellSize.height + underlineOffset];
}

- (CGFloat)underlineThicknessForFont:(NSFont *)font {
    return MAX(0.5, [self retinaRound:font.underlineThickness]);
}

- (CGFloat)strikethroughThicknessForFont:(NSFont *)font {
    return [self underlineThicknessForFont:font];
}

- (void)drawUnderlineOrStrikethroughOfColor:(NSColor *)color
                              wantUnderline:(BOOL)wantUnderline
                                      style:(NSUnderlineStyle)underlineStyle
                                       font:(NSFont *)font
                                       rect:(NSRect)rawRect
                              virtualOffset:(CGFloat)virtualOffset {
    const NSRect rect = NSRectSubtractingVirtualOffset(rawRect, virtualOffset);
    [color set];
    NSBezierPath *path = [NSBezierPath bezierPath];

    const CGFloat y = (wantUnderline ?
                       [self yOriginForUnderlineForFont:font yOffset:rect.origin.y cellHeight:_cellSize.height] :
                       [self yOriginForStrikethroughForFont:font yOffset:rect.origin.y cellHeight:_cellSize.height]);
    NSPoint origin = NSMakePoint(rect.origin.x,
                                 y);
    origin.y += self.isRetina ? 0.25 : 0.5;
    CGFloat dashPattern[] = { 4, 3 };
    CGFloat phase = fmod(rect.origin.x, dashPattern[0] + dashPattern[1]);

    const CGFloat lineWidth = wantUnderline ? [self underlineThicknessForFont:font] : [self strikethroughThicknessForFont:font];
    switch (underlineStyle) {
        case NSUnderlineStyleSingle:
            [path moveToPoint:origin];
            [path lineToPoint:NSMakePoint(origin.x + rect.size.width, origin.y)];
            [path setLineWidth:lineWidth];
            [path stroke];
            break;

        case NSUnderlineStylePatternDot: {  // Single underline with dash beneath
            origin.y = rect.origin.y + _cellSize.height - 1;
            origin.y -= self.isRetina ? 0.25 : 0.5;
            [path moveToPoint:origin];
            [path lineToPoint:NSMakePoint(origin.x + rect.size.width, origin.y)];
            [path setLineWidth:lineWidth];
            [path stroke];

            const CGFloat px = self.isRetina ? 0.5 : 1;
            path = [NSBezierPath bezierPath];
            [path moveToPoint:NSMakePoint(origin.x, origin.y + lineWidth + px)];
            [path lineToPoint:NSMakePoint(origin.x + rect.size.width, origin.y + lineWidth + px)];
            [path setLineWidth:lineWidth];
            [path setLineDash:dashPattern count:2 phase:phase];
            [path stroke];
            break;
        }
        case NSUnderlineStyleDouble: {  // Actual double underline
            origin.y = rect.origin.y + _cellSize.height - 1;
            origin.y -= self.isRetina ? 0.25 : 0.5;
            [path moveToPoint:origin];
            [path lineToPoint:NSMakePoint(origin.x + rect.size.width, origin.y)];
            [path setLineWidth:lineWidth];
            [path stroke];

            const CGFloat px = self.isRetina ? 0.5 : 1;
            path = [NSBezierPath bezierPath];
            [path moveToPoint:NSMakePoint(origin.x, origin.y + lineWidth + px)];
            [path lineToPoint:NSMakePoint(origin.x + rect.size.width, origin.y + lineWidth + px)];
            [path setLineWidth:lineWidth];
            [path stroke];
            break;
        }

        case NSUnderlineStyleThick: {  // We use this for curly. Cocoa doesn't have curly underlines, so we reprupose thick.
            const CGFloat offset = 0;
            origin.y = rect.origin.y + _cellSize.height - 1.5;
            CGContextRef cgContext = [[NSGraphicsContext currentContext] CGContext];
            CGContextSaveGState(cgContext);
            CGContextClipToRect(cgContext, NSMakeRect(origin.x, origin.y - 1, rect.size.width, 3));

            [color set];
            NSBezierPath *path = [NSBezierPath bezierPath];
            const CGFloat height = 1;
            const CGFloat width = 3;
            const CGFloat lowY = origin.y + offset;
            const CGFloat highY = origin.y + height + offset;
            for (CGFloat x = origin.x - fmod(origin.x, width * 2); x < NSMaxX(rect); x += width * 2) {
                [path moveToPoint:NSMakePoint(x + 0, highY)];
                [path lineToPoint:NSMakePoint(x + width, highY)];

                [path moveToPoint:NSMakePoint(x + width, lowY)];
                [path lineToPoint:NSMakePoint(x + width * 2, lowY)];
            }
            [path setLineWidth:1];
            [path stroke];
            CGContextRestoreGState(cgContext);
            break;
        }

        case NSUnderlinePatternDash: {
            if (![iTermAdvancedSettingsModel underlineHyperlinks]) {
                break;
            }
            [path moveToPoint:origin];
            [path lineToPoint:NSMakePoint(origin.x + rect.size.width, origin.y)];
            [path setLineWidth:lineWidth];
            [path setLineDash:dashPattern count:2 phase:phase];
            [path stroke];
            break;

        case NSUnderlineStyleNone:
            break;

        default:
            ITCriticalError(NO, @"Unexpected underline style %@", @(underlineStyle));
            break;
        }
    }
}

- (CGFloat)retinaRound:(CGFloat)value {
    CGFloat scaleFactor = self.isRetina ? 2.0 : 1.0;
    return round(scaleFactor * value) / scaleFactor;
}

- (CGFloat)retinaFloor:(CGFloat)value {
    CGFloat scaleFactor = self.isRetina ? 2.0 : 1.0;
    return floor(scaleFactor * value) / scaleFactor;
}

- (BOOL)haveAnyImagesUnderText {
    return [_kittyImageDraws anyWithBlock:^BOOL(iTermKittyImageDraw *draw) {
        return draw.zIndex <= 0;
    }];
}

- (void)drawKittyImagesInRange:(iTermSignedRange)zIndexRange virtualOffset:(CGFloat)virtualOffset {
    [_kittyImageDraws enumerateObjectsUsingBlock:^(iTermKittyImageDraw * _Nonnull draw, NSUInteger idx, BOOL * _Nonnull stop) {
        if (draw.virtual) {
            // These are drawn in unicode placeholders.
            return;
        }
        if (!iTermSignedRangeContainsValue(zIndexRange, draw.zIndex)) {
            return;
        }
        [self drawKittyImage:draw virtualOffset:virtualOffset];
    }];
}

- (void)drawKittyImage:(iTermKittyImageDraw *)draw virtualOffset:(CGFloat)virtualOffset {
    NSRect destination = draw.destinationFrame;
    if (self.isRetina) {
        destination.origin.x /= 2;
        destination.origin.y /= 2;
        destination.size.width /= 2;
        destination.size.height /= 2;
    }
    destination.origin.y -= self.cellSize.height * self.totalScrollbackOverflow;
    if (!NSIntersectsRect(destination, _scrollViewDocumentVisibleRect)) {
        return;
    }

    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:destination.origin.x yBy:NSMaxY(destination) - virtualOffset];
    [transform scaleXBy:1.0 yBy:-1.0];
    [transform concat];
    destination.origin = NSZeroPoint;

    NSImage *image = draw.image.images[draw.index];
    [image drawInRect:destination
             fromRect:draw.sourceFrame
            operation:NSCompositingOperationSourceOver
             fraction:1];

    [NSGraphicsContext restoreGraphicsState];
}

+ (NSSize)sizeForKittyImageCellInPlacementOfSize:(VT100GridSize)placementSize
                                        cellSize:(NSSize)cellSize
                                sourceImageSize:(NSSize)sourceImageSize {
    // Calculate the aspect ratios
    CGFloat imageAspectRatio = sourceImageSize.width / sourceImageSize.height;
    CGFloat gridAspectRatio = (placementSize.width * cellSize.width) / (placementSize.height * cellSize.height);

    // The size of the source rectangle in the image that will be drawn to a single cell
    NSSize sourceRectSize;

    if (imageAspectRatio > gridAspectRatio) {
        // Image is wider than the grid, scale based on width
        sourceRectSize.width = sourceImageSize.width / placementSize.width;
        sourceRectSize.height = sourceRectSize.width * (cellSize.height / cellSize.width);
    } else {
        // Image is taller than the grid, scale based on height
        sourceRectSize.height = sourceImageSize.height / placementSize.height;
        sourceRectSize.width = sourceRectSize.height * (cellSize.width / cellSize.height);
    }

    return sourceRectSize;
}

iTermKittyPlaceholderDrawInstructions iTermKittyPlaceholderDrawInstructionsCreate(iTermKittyImageDraw *draw,
                                                                                  NSSize cellSize,
                                                                                  VT100GridCoord sourceCoord,
                                                                                  VT100GridCoord destCoord,
                                                                                  NSPoint point,
                                                                                  unsigned int imageID,
                                                                                  unsigned int placementID,
                                                                                  CGFloat virtualOffset) {
    iTermKittyPlaceholderDrawInstructions result = { 0 };
    result.valid = NO;

    if (draw.placementSize.width <= 0 || draw.placementSize.height <= 0) {
        return result;
    }
    const NSSize sourceCellSize = [iTermTextDrawingHelper sizeForKittyImageCellInPlacementOfSize:draw.placementSize
                                                                                        cellSize:cellSize
                                                                                 sourceImageSize:draw.sourceFrame.size];
    const NSRect destRect = NSMakeRect(0, 0, cellSize.width, cellSize.height);
    const NSRect sourceRect = [iTermTextDrawingHelper sourceRectangleForKittyPlaceholderAtSourceCoord:sourceCoord
                                                                                       sourceCellSize:sourceCellSize
                                                                                        placementSize:draw.placementSize
                                                                                             cellSize:cellSize
                                                                                          sourceFrame:draw.sourceFrame];

    result.valid = YES;
    result.translation = NSMakePoint(point.x, point.y + cellSize.height - virtualOffset);
    result.destRect = destRect;
    result.sourceRect = sourceRect;
    return result;
}

iTermKittyImageDraw *iTermFindKittyImageDrawForVirtualPlaceholder(NSArray<iTermKittyImageDraw *> *draws,
                                                                  unsigned int placementID,
                                                                  unsigned int imageID) {
    iTermKittyImageDraw *draw = [draws objectPassingTest:^BOOL(iTermKittyImageDraw *draw, NSUInteger index, BOOL *stop) {
        return draw.placementID == placementID;
    }];
    if (!draw) {
        // Look up placement by image ID. Must include a size.
        draw = [draws objectPassingTest:^BOOL(iTermKittyImageDraw *element, NSUInteger index, BOOL *stop) {
            return draw.imageID == imageID && draw.placementSize.width > 0 && draw.placementSize.height > 0;
        }];
    }
    return draw;
}

- (void)drawKittyImageInPlaceholderWithCoord:(VT100GridCoord)sourceCoord
                                      origin:(VT100GridCoord)destCoord
                                     atPoint:(NSPoint)point
                                     imageID:(unsigned int)imageID
                                 placementID:(unsigned int)placementID
                               virtualOffset:(CGFloat)virtualOffset {
    // Look up the placement
    iTermKittyImageDraw *draw = iTermFindKittyImageDrawForVirtualPlaceholder(_kittyImageDraws,
                                                                             placementID,
                                                                             imageID);
    if (!draw) {
        return;
    }
    if (draw.placementSize.width <= 0 || draw.placementSize.height <= 0) {
        return;
    }
    NSImage *image = draw.image.images[0];
    iTermKittyPlaceholderDrawInstructions instructions =
        iTermKittyPlaceholderDrawInstructionsCreate(draw,
                                                    _cellSize,
                                                    sourceCoord,
                                                    destCoord,
                                                    point,
                                                    imageID,
                                                    placementID,
                                                    virtualOffset);
    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:instructions.translation.x yBy:instructions.translation.y];
    [transform scaleXBy:1.0 yBy:-1.0];
    [transform concat];

    [image drawInRect:instructions.destRect
             fromRect:instructions.sourceRect
            operation:NSCompositingOperationSourceOver
             fraction:1.0];

    [NSGraphicsContext restoreGraphicsState];
}

+ (NSRect)sourceRectangleForKittyPlaceholderAtSourceCoord:(VT100GridCoord)sourceCoord
                                           sourceCellSize:(NSSize)sourceCellSize
                                            placementSize:(VT100GridSize)placementSize
                                                 cellSize:(NSSize)cellSize
                                              sourceFrame:(NSRect)sourceFrame {
    const NSSize imageSize = sourceFrame.size;
    const CGFloat totalPlacementWidth = placementSize.width * cellSize.width;
    const CGFloat totalPlacementHeight = placementSize.height * cellSize.height;

    // Calculate the actual scaled size of the image to fit within the placement
    const CGFloat imageAspectRatio = imageSize.width / imageSize.height;
    const CGFloat placementAspectRatio = totalPlacementWidth / totalPlacementHeight;

    CGFloat scaledWidth;
    CGFloat scaledHeight;
    if (imageAspectRatio > placementAspectRatio) {
        // Image is wider than the placement grid, scale by width
        scaledWidth = totalPlacementWidth;
        scaledHeight = scaledWidth / imageAspectRatio;
    } else {
        // Image is taller than the placement grid, scale by height
        scaledHeight = totalPlacementHeight;
        scaledWidth = scaledHeight * imageAspectRatio;
    }

    // Calculate the padding to center the image within the placement grid
    CGFloat horizontalPadding = (totalPlacementWidth - scaledWidth) / 2.0;
    CGFloat verticalPadding = (totalPlacementHeight - scaledHeight) / 2.0;

    // Adjust the source rectangle to account for the padding
    CGFloat adjustedSourceX = sourceCoord.x * sourceCellSize.width - horizontalPadding * (sourceCellSize.width / cellSize.width);
    CGFloat adjustedSourceY = sourceCoord.y * sourceCellSize.height - verticalPadding * (sourceCellSize.height / cellSize.height);

    const NSRect sourceRect = NSMakeRect(adjustedSourceX + sourceFrame.origin.x,
                                         imageSize.height - (adjustedSourceY + sourceFrame.origin.y) - sourceCellSize.height,
                                         sourceCellSize.width,
                                         sourceCellSize.height);
    return sourceRect;
}

// origin is the first location onscreen
- (void)drawImageWithCode:(unichar)code
                   origin:(VT100GridCoord)origin
                   length:(NSInteger)length
                  atPoint:(NSPoint)point
            originInImage:(VT100GridCoord)originInImage
            virtualOffset:(CGFloat)virtualOffset {
    //DLog(@"Drawing image at %@ with code %@", VT100GridCoordDescription(origin), @(code));
    id<iTermImageInfoReading> imageInfo = GetImageInfo(code);
    NSImage *image = [imageInfo imageWithCellSize:_cellSize scale:self.isRetina ? 2 : 1];
    if (!image) {
        if (!imageInfo) {
            DLog(@"Image is missing (brown)");
            [[NSColor brownColor] set];
        } else {
            DLog(@"Image isn't loaded yet (gray)");
            [_missingImages addObject:imageInfo.uniqueIdentifier];

            [[NSColor grayColor] set];
        }
        iTermRectFill(NSMakeRect(point.x, point.y, _cellSize.width * length, _cellSize.height), virtualOffset);
        return;
    }
    [_missingImages removeObject:imageInfo.uniqueIdentifier];

    NSSize chunkSize = NSMakeSize(image.size.width / imageInfo.size.width,
                                  image.size.height / imageInfo.size.height);

    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:point.x yBy:point.y + _cellSize.height - virtualOffset];
    [transform scaleXBy:1.0 yBy:-1.0];
    [transform concat];

    if (imageInfo.animated) {
        [_delegate drawingHelperDidFindRunOfAnimatedCellsStartingAt:origin ofLength:length];
        _animated = YES;
    }
    const NSRect destRect = NSMakeRect(0, 0, _cellSize.width * length, _cellSize.height);
    const NSRect sourceRect = NSMakeRect(chunkSize.width * originInImage.x,
                                         image.size.height - _cellSize.height - chunkSize.height * originInImage.y,
                                         chunkSize.width * length,
                                         chunkSize.height);
    DLog(@"Draw %@ -> %@ with source image of size %@", NSStringFromRect(sourceRect), NSStringFromRect(destRect), NSStringFromSize(image.size));
    [image drawInRect:destRect
             fromRect:sourceRect
            operation:NSCompositingOperationSourceOver
             fraction:1];
    [NSGraphicsContext restoreGraphicsState];
}

+ (NSRect)offscreenCommandLineFrameForVisibleRect:(NSRect)visibleRect
                                         cellSize:(NSSize)cellSize
                                         gridSize:(VT100GridSize)gridSize {
    const CGFloat hmargin = [iTermPreferences intForKey:kPreferenceKeySideMargins];
    const CGFloat vmargin = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    NSRect rect = NSMakeRect(hmargin,
                             visibleRect.origin.y - vmargin - 1,
                             cellSize.width * gridSize.width,
                             cellSize.height + iTermOffscreenCommandLineVerticalPadding * 2);
    return rect;
}

- (NSRect)offscreenCommandLineFrame {
    return [iTermTextDrawingHelper offscreenCommandLineFrameForVisibleRect:_visibleRectExcludingTopMargin
                                                                  cellSize:_cellSize
                                                                  gridSize:_gridSize];
}

- (NSColor *)offscreenCommandLineBackgroundColor {
    if (!self.offscreenCommandLine) {
        return nil;
    }
    NSColor *color;
    if ([[self defaultBackgroundColor] isDark]) {
        color = [[self defaultBackgroundColor] it_colorByDimmingByAmount:0.7];
    } else {
        color = [[self defaultBackgroundColor] it_colorByDimmingByAmount:0.1];
    }
    return [color colorWithAlphaComponent:0.5];
}

- (NSColor *)offscreenCommandLineOutlineColor {
    if (!self.offscreenCommandLine) {
        return nil;
    }
    NSColor *textColor = self.defaultTextColor;
    NSColor *backgroundColor = self.defaultBackgroundColor;
    NSColor *blend = [textColor blendedWithColor:backgroundColor weight:0.5];
    return blend;
}

- (void)drawOffscreenCommandLineWithVirtualOffset:(CGFloat)virtualOffset {
    if (!_offscreenCommandLine) {
        return;
    }
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];

    BOOL blink = NO;
    const int row = [self rangeOfVisibleRows].location;

    const int line = _offscreenCommandLine.absoluteLineNumber - _totalScrollbackOverflow;
    iTermImmutableMetadata metadata = [self.delegate drawingHelperMetadataOnLine:line];
    const BOOL rtlFound = metadata.rtlFound;

    iTermBackgroundColorRunsInLine *backgroundRuns =
    [iTermBackgroundColorRunsInLine backgroundRunsInLine:_offscreenCommandLine.characters.line
                                              lineLength:_gridSize.width
                                        sourceLineNumber:line
                                       displayLineNumber:row
                                         selectedIndexes:[NSIndexSet indexSet]
                                             withinRange:NSMakeRange(0, _gridSize.width)
                                                 matches:nil
                                                anyBlink:&blink
                                                       y:row * _cellSize.height
                                                    bidi:rtlFound ? [self.delegate drawingHelperBidiInfoForLine:line] : nil];


    [self drawOffscreenCommandLineDecorationsInContext:ctx
                                         virtualOffset:virtualOffset];

    const CGFloat vmargin = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    // Use padding to disable drawing default background color
    [self drawBackgroundForLine:0
                            atY:row * _cellSize.height + iTermOffscreenCommandLineVerticalPadding - vmargin - 1
                           runs:backgroundRuns.array
                 equivalentRows:1
                  virtualOffset:virtualOffset
                            pad:YES
                        padding:NSZeroSize
                    drawingMode:iTermBackgroundDrawingModeDefault];

    if ([self textAppearanceDependsOnBackgroundColor]) {
        [self drawForegroundForBackgroundRunArrays:@[backgroundRuns]
                          drawOffscreenCommandLine:YES
                                               ctx:ctx
                                     virtualOffset:virtualOffset];
    } else {
        [self drawUnprocessedForegroundForBackgroundRunArrays:@[backgroundRuns]
                                     drawOffscreenCommandLine:YES
                                                          ctx:ctx
                                                virtualOffset:virtualOffset];
    }
}

- (void)drawOffscreenCommandLineDecorationsInContext:(CGContextRef)ctx
                                       virtualOffset:(CGFloat)virtualOffset {
    if (!self.offscreenCommandLine) {
        return;
    }

    const NSRect rect = self.offscreenCommandLineFrame;

    NSRect outline = rect;
    outline.origin.x = 0;
    outline.size.width = _visibleRectExcludingTopMargin.size.width;

    [[self offscreenCommandLineBackgroundColor] set];
    iTermRectFill(outline, virtualOffset);

    [[self offscreenCommandLineOutlineColor] set];

    const BOOL enableBlending = !iTermTextIsMonochrome() || [NSView iterm_takingSnapshot];
    const NSCompositingOperation operation = enableBlending ? NSCompositingOperationSourceOver : NSCompositingOperationCopy;

    iTermRectFillUsingOperation(NSMakeRect(outline.origin.x, outline.origin.y, outline.size.width, 1),
                                operation,
                                virtualOffset);
    iTermRectFillUsingOperation(NSMakeRect(outline.origin.x, NSMaxY(outline) - 1, outline.size.width, 1),
                                operation,
                                virtualOffset);
}

- (BOOL)drawInputMethodEditorTextAt:(int)xStart
                                  y:(int)yStart
                              width:(int)width
                             height:(int)height
                       cursorHeight:(double)cursorHeight
                                ctx:(CGContextRef)ctx
                      virtualOffset:(CGFloat)virtualOffset {
    iTermColorMap *colorMap = _colorMap;

    // draw any text for NSTextInput
    if ([self hasMarkedText]) {
        NSString* str = [_markedText string];
        const int maxLen = [str length] * kMaxParts;
        screen_char_t buf[maxLen];
        screen_char_t fg = {0}, bg = {0};
        int len;
        int cursorIndex = (int)_inputMethodSelectedRange.location;
        // If I can ever find a case that reproduces IME + RTL then this code should be updated to support bidi.
        StringToScreenChars(str,
                            buf,
                            fg,
                            bg,
                            &len,
                            _ambiguousIsDoubleWidth,
                            &cursorIndex,
                            NULL,
                            _normalization,
                            self.unicodeVersion,
                            self.softAlternateScreenMode,
                            NULL);
        int cursorX = 0;
        int baseX = floor(xStart * _cellSize.width + [iTermPreferences intForKey:kPreferenceKeySideMargins]);
        int i;
        int y = (yStart + _numberOfLines - height) * _cellSize.height;
        int cursorY = y;
        int x = baseX;
        int preWrapY = 0;
        BOOL justWrapped = NO;
        BOOL foundCursor = NO;
        for (i = 0; i < len; ) {
            const int remainingCharsInBuffer = len - i;
            const int remainingCharsInLine = width - xStart;
            int charsInLine = MIN(remainingCharsInLine,
                                  remainingCharsInBuffer);
            int skipped = 0;
            if (charsInLine + i < len &&
                ScreenCharIsDWC_RIGHT(buf[charsInLine + i])) {
                // If we actually drew 'charsInLine' chars then half of a
                // double-width char would be drawn. Skip it and draw it on the
                // next line.
                skipped = 1;
                --charsInLine;
            }
            // Draw the background.
            NSRect r = NSMakeRect(x,
                                  y,
                                  charsInLine * _cellSize.width,
                                  _cellSize.height);
            [[self defaultBackgroundColor] set];
            iTermRectFill(r, virtualOffset);
            [self drawAccessoriesInRect:r virtualOffset:virtualOffset];

            // Draw the characters.
            [self constructAndDrawRunsForLine:buf
                                     bidiInfo:nil
                           externalAttributes:nil
                              sourceLineNumer:y
                            displayLineNumber:y
                                      inRange:NSMakeRange(i, charsInLine)
                              startingAtPoint:NSMakePoint(x, y)
                                   bgselected:NO
                                      bgColor:nil
                     processedBackgroundColor:[self defaultBackgroundColor]
                                     colorRun:nil
                                      matches:nil
                               forceTextColor:[self defaultTextColor]
                                      context:ctx
                                virtualOffset:virtualOffset];
            // Draw an underline.
            BOOL unusedBold = NO;
            BOOL unusedItalic = NO;
            UTF32Char ignore = 0;
            PTYFontInfo *fontInfo = [_delegate drawingHelperFontForChar:128
                                                              isComplex:NO
                                                             renderBold:&unusedBold
                                                           renderItalic:&unusedItalic
                                                               remapped:&ignore];
            NSRect rect = NSMakeRect(x,
                                     y - round((_cellSize.height - _cellSizeWithoutSpacing.height) / 2.0),
                                     charsInLine * _cellSize.width,
                                     _cellSize.height);
            [self drawUnderlineOrStrikethroughOfColor:[self defaultTextColor]
                                        wantUnderline:YES
                                                style:NSUnderlineStyleSingle
                                                 font:fontInfo.font
                                                 rect:rect
                                        virtualOffset:virtualOffset];

            // Save the cursor's cell coords
            if (i <= cursorIndex && i + charsInLine > cursorIndex) {
                // The char the cursor is at was drawn in this line.
                const int cellsAfterStart = cursorIndex - i;
                cursorX = x + _cellSize.width * cellsAfterStart;
                cursorY = y;
                foundCursor = YES;
            }

            // Advance the cell and screen coords.
            xStart += charsInLine + skipped;
            if (xStart == width) {
                justWrapped = YES;
                preWrapY = y;
                xStart = 0;
                yStart++;
            } else {
                justWrapped = NO;
            }
            x = floor(xStart * _cellSize.width + [iTermPreferences intForKey:kPreferenceKeySideMargins]);
            y = (yStart + _numberOfLines - height) * _cellSize.height;
            i += charsInLine;
        }

        if (!foundCursor && i == cursorIndex) {
            if (justWrapped) {
                cursorX = [iTermPreferences intForKey:kPreferenceKeySideMargins] + width * _cellSize.width;
                cursorY = preWrapY;
            } else {
                cursorX = x;
                cursorY = y;
            }
        }
        const double kCursorWidth = 2.0;
        double rightMargin = [iTermPreferences intForKey:kPreferenceKeySideMargins] + _gridSize.width * _cellSize.width;
        if (cursorX + kCursorWidth >= rightMargin) {
            // Make sure the cursor doesn't draw in the margin. Shove it left
            // a little bit so it fits.
            cursorX = rightMargin - kCursorWidth;
        }
        NSRect cursorFrame = NSMakeRect(cursorX,
                                        cursorY + round((_cellSize.height - _cellSizeWithoutSpacing.height) / 2.0),
                                        2.0,
                                        cursorHeight);
        _imeCursorLastPos = cursorFrame.origin;
        [self.delegate drawingHelperUpdateFindCursorView];
        [[colorMap processedBackgroundColorForBackgroundColor:[NSColor colorWithCalibratedRed:1.0
                                                                                        green:1.0
                                                                                         blue:0
                                                                                        alpha:1.0]] set];
        iTermRectFill(cursorFrame, virtualOffset);

        return YES;
    }
    return NO;
}

#pragma mark - Drawing: Cursor

- (NSRect)dumbFrameForCursorAt:(VT100GridCoord)cursorCoord {
    const int rowNumber = cursorCoord.y + _numberOfLines - _gridSize.height;
    if ([iTermAdvancedSettingsModel fullHeightCursor]) {
        const CGFloat height = MAX(_cellSize.height, _cellSizeWithoutSpacing.height);
        return NSMakeRect(floor(cursorCoord.x * _cellSize.width + [iTermPreferences intForKey:kPreferenceKeySideMargins]),
                          rowNumber * _cellSize.height,
                          MIN(_cellSize.width, _cellSizeWithoutSpacing.width),
                          height);
    } else {
        const CGFloat height = MIN(_cellSize.height, _cellSizeWithoutSpacing.height);
        return NSMakeRect(floor(cursorCoord.x * _cellSize.width + [iTermPreferences intForKey:kPreferenceKeySideMargins]),
                          rowNumber * _cellSize.height + MAX(0, round((_cellSize.height - _cellSizeWithoutSpacing.height) / 2.0)),
                          MIN(_cellSize.width, _cellSizeWithoutSpacing.width),
                          height);
    }
}

- (NSRect)cursorFrameForSolidRectangle {
    const VT100GridCoord coord = [self coordinateByTransformingScreenCoordinateForRTL:_cursorCoord];
    const iTermCursorInfo cursorInfo = [self cursorInfoForCoord:coord];
    return [[iTermCursor cursorOfType:_cursorType] frameForSolidRectangle:cursorInfo.rect];
}

- (NSColor *)cursorColor {
    return [self cursorColorWithOutline:NO];
}

- (BOOL)cursorIsSolidRectangle {
    if (_passwordInput) {
        return NO;
    }
    BOOL saved = _blinkingItemsVisible;
    _blinkingItemsVisible = YES;
    const BOOL wouldDraw = [self shouldDrawCursor];
    _blinkingItemsVisible = saved;
    if (!wouldDraw) {
        return NO;
    }
    if (_showSearchingCursor) {
        return NO;
    }
    return [[iTermCursor cursorOfType:_cursorType] isSolidRectangleWithFocused:self.isFocused];
}

typedef struct {
    NSRect rect;
    BOOL isDoubleWidth;
    screen_char_t screenChar;
} iTermCursorInfo;

- (iTermCursorInfo)cursorInfoForCoord:(VT100GridCoord)cursorCoord {
    // Get the character that's under the cursor.
    const screen_char_t *theLine;
    if (cursorCoord.y >= 0) {
        theLine = [self lineAtScreenIndex:cursorCoord.y];
    } else {
        theLine = [self lineAtIndex:cursorCoord.y + _numberOfScrollbackLines isFirst:nil];
    }
    BOOL isDoubleWidth;
    screen_char_t screenChar = [self charForCursorAtColumn:cursorCoord.x
                                                    inLine:theLine
                                               doubleWidth:&isDoubleWidth];

    // Update the "find cursor" view.
    [self.delegate drawingHelperUpdateFindCursorView];

    // Get the color of the cursor.
    NSRect rect = [self dumbFrameForCursorAt:cursorCoord];
    if (isDoubleWidth) {
        rect.size.width *= 2;
    }
    return (iTermCursorInfo){
        .rect = rect,
        .isDoubleWidth = isDoubleWidth,
        .screenChar = screenChar
    };
}

- (NSColor *)cursorColorWithOutline:(BOOL)outline {
    if (outline) {
        return [_colorMap colorForKey:kColorMapBackground];
    } else {
        return [self backgroundColorForCursor];
    }
}

- (void)drawCopyModeCursorWithBackgroundColor:(NSColor *)cursorBackgroundColor
                                virtualOffset:(CGFloat)virtualOffset {
    iTermCursor *cursor = [iTermCursor itermCopyModeCursorInSelectionState:self.copyModeSelecting];
    cursor.delegate = self;

    [self reallyDrawCursor:cursor
           backgroundColor:cursorBackgroundColor
                        at:VT100GridCoordMake(_copyModeCursorCoord.x, _copyModeCursorCoord.y - _numberOfScrollbackLines)
            coordIsLogical:NO
                   outline:NO
             virtualOffset:virtualOffset];
}

- (iTermCursor *)drawCursor:(BOOL)outline
      cursorBackgroundColor:(NSColor *)cursorBackgroundColor
              virtualOffset:(CGFloat)virtualOffset {
    DLog(@"drawCursor:%@", @(outline));

    // Update the last time the cursor moved.
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!VT100GridCoordEquals(_cursorCoord, _oldCursorPosition)) {
        _lastTimeCursorMoved = now;
    }

    iTermCursor *cursor = nil;
    if ([self shouldDrawCursor]) {
        cursor = [iTermCursor cursorOfType:_cursorType];
        cursor.delegate = self;
        NSRect rect = [self reallyDrawCursor:cursor
                             backgroundColor:cursorBackgroundColor
                                          at:_cursorCoord
                              coordIsLogical:YES
                                     outline:outline
                               virtualOffset:virtualOffset];

        if (_showSearchingCursor) {
            NSImage *image = [NSImage it_imageNamed:@"SearchCursor" forClass:self.class];
            if (image) {
                NSRect imageRect = rect;
                CGFloat aspectRatio = image.size.height / image.size.width;
                imageRect.size.height = imageRect.size.width * aspectRatio;
                if (imageRect.size.height > rect.size.height) {
                    imageRect.size.height = rect.size.height;
                    imageRect.size.width = rect.size.height / aspectRatio;
                }
                imageRect.origin.y += (rect.size.height - imageRect.size.height) / 2;
                imageRect.origin.x += (rect.size.width - imageRect.size.width) / 2;

                [image it_drawInRect:imageRect
                            fromRect:NSZeroRect
                           operation:NSCompositingOperationSourceOver
                            fraction:1
                      respectFlipped:YES
                               hints:nil
                       virtualOffset:virtualOffset];
            }
        }
    }

    _oldCursorPosition = _cursorCoord;
    return cursor;
}

- (NSColor *)blockCursorFillColorRespectingSmartSelection {
    if (_useSmartCursorColor) {
        const screen_char_t *theLine;
        if (_cursorCoord.y >= 0) {
            theLine = [self lineAtScreenIndex:_cursorCoord.y];
        } else {
            theLine = [self lineAtIndex:_cursorCoord.y + _numberOfScrollbackLines isFirst:nil];
        }
        BOOL isDoubleWidth;
        screen_char_t screenChar = [self charForCursorAtColumn:_cursorCoord.x
                                                        inLine:theLine
                                                   doubleWidth:&isDoubleWidth];
        iTermSmartCursorColor *smartCursorColor = [[iTermSmartCursorColor alloc] init];
        smartCursorColor.delegate = self;
        return [smartCursorColor backgroundColorForCharacter:screenChar];
    } else {
        return self.backgroundColorForCursor;
    }
}

// This is intended to transform the cursor coordinate for bidi lines.
- (VT100GridCoord)coordinateByTransformingScreenCoordinateForRTL:(VT100GridCoord)screenCoord {
    iTermBidiDisplayInfo *bidiInfo = [self.delegate drawingHelperBidiInfoForLine:screenCoord.y + _numberOfScrollbackLines];
    if (!bidiInfo) {
        return screenCoord;
    }
    if (screenCoord.x < 0 || bidiInfo.numberOfCells == 0) {
        return screenCoord;
    }
    const int numberOfCells = bidiInfo.numberOfCells;
    if (screenCoord.x >= numberOfCells) {
        const int offset = 0;
        // Cursor is logically after the last non-space character.
        if ([bidiInfo.rtlIndexes containsIndex:numberOfCells - 1]) {
            // Cursor follows an RTL run. Place it left of the last character.
            return VT100GridCoordMake(MAX(0, bidiInfo.lut[numberOfCells - 1] - offset), screenCoord.y);
        } else {
            // The line ends with LTR so place it right of last character.
            const int width = _gridSize.width;
            return VT100GridCoordMake(MIN(width, bidiInfo.lut[numberOfCells - 1] + offset + 1), screenCoord.y);
        }
    }
    // Cursor is somewhere in the bidi lookup table.
    return VT100GridCoordMake(bidiInfo.lut[screenCoord.x], screenCoord.y);
}

- (NSRect)reallyDrawCursor:(iTermCursor *)cursor
           backgroundColor:(NSColor *)backgroundColor
                        at:(VT100GridCoord)nominalCursorCoord
            coordIsLogical:(BOOL)coordIsLogical
                   outline:(BOOL)outline
             virtualOffset:(CGFloat)virtualOffset {
    const VT100GridCoord cursorCoord = coordIsLogical ? [self coordinateByTransformingScreenCoordinateForRTL:nominalCursorCoord] : nominalCursorCoord;
    const iTermCursorInfo cursorInfo = [self cursorInfoForCoord:cursorCoord];
    NSColor *cursorColor = [self cursorColorWithOutline:outline];

    if (_passwordInput) {
        NSImage *keyImage;
        if (backgroundColor.isDark) {
            keyImage = [NSImage it_imageNamed:@"key-light" forClass:self.class];
        } else {
            keyImage = [NSImage it_imageNamed:@"key-dark" forClass:self.class];
        }
        CGPoint point = cursorInfo.rect.origin;
        [keyImage it_drawInRect:NSMakeRect(point.x, point.y, _cellSize.width, _cellSize.height)
                       fromRect:NSZeroRect
                      operation:NSCompositingOperationSourceOver
                       fraction:1
                 respectFlipped:YES
                          hints:nil
                  virtualOffset:virtualOffset];
        return cursorInfo.rect;
    }


    NSColor *cursorTextColor;
    if (_reverseVideo) {
        cursorTextColor = [_colorMap colorForKey:kColorMapForeground];
    } else {
        cursorTextColor = [_delegate drawingHelperColorForCode:ALTSEM_CURSOR
                                                         green:0
                                                          blue:0
                                                     colorMode:ColorModeAlternate
                                                          bold:NO
                                                         faint:NO
                                                  isBackground:NO];
    }
    [cursor drawWithRect:cursorInfo.rect
             doubleWidth:cursorInfo.isDoubleWidth
              screenChar:cursorInfo.screenChar
         backgroundColor:cursorColor
         foregroundColor:cursorTextColor
                   smart:_useSmartCursorColor
                 focused:[self isFocused]
                   coord:cursorCoord
                 outline:outline
           virtualOffset:virtualOffset];
    return cursorInfo.rect;
}

- (BOOL)isFocused {
    return ((_isInKeyWindow && _textViewIsActiveSession) || _shouldDrawFilledInCursor);
}
#pragma mark - Text Run Construction

- (NSRange)underlinedRangeOnLine:(long long)row {
    if (_underlinedRange.coordRange.start.x < 0) {
        return NSMakeRange(0, 0);
    }

    if (row == _underlinedRange.coordRange.start.y && row == _underlinedRange.coordRange.end.y) {
        // Whole underline is on one line.
        const int start = VT100GridAbsWindowedRangeStart(_underlinedRange).x;
        const int end = VT100GridAbsWindowedRangeEnd(_underlinedRange).x;
        return NSMakeRange(start, end - start);
    } else if (row == _underlinedRange.coordRange.start.y) {
        // Underline spans multiple lines, starting at this one.
        const int start = VT100GridAbsWindowedRangeStart(_underlinedRange).x;
        const int end =
            _underlinedRange.columnWindow.length > 0 ? VT100GridRangeMax(_underlinedRange.columnWindow) + 1
            : _gridSize.width;
        return NSMakeRange(start, end - start);
    } else if (row == _underlinedRange.coordRange.end.y) {
        // Underline spans multiple lines, ending at this one.
        const int start =
            _underlinedRange.columnWindow.length > 0 ? _underlinedRange.columnWindow.location : 0;
        const int end = VT100GridAbsWindowedRangeEnd(_underlinedRange).x;
        return NSMakeRange(start, end - start);
    } else if (row > _underlinedRange.coordRange.start.y && row < _underlinedRange.coordRange.end.y) {
        // Underline spans multiple lines. This is not the first or last line, so all chars
        // in it are underlined.
        const int start =
            _underlinedRange.columnWindow.length > 0 ? _underlinedRange.columnWindow.location : 0;
        const int end =
            _underlinedRange.columnWindow.length > 0 ? VT100GridRangeMax(_underlinedRange.columnWindow) + 1
            : _gridSize.width;
        return NSMakeRange(start, end - start);
    } else {
        // No underline on this line.
        return NSMakeRange(0, 0);
    }
}

#pragma mark - Cursor Utilities

- (NSColor *)backgroundColorForCursor {
    NSColor *color;
    if (_reverseVideo) {
        color = [[_colorMap colorForKey:kColorMapCursorText] colorWithAlphaComponent:1.0];
    } else {
        color = [[_colorMap colorForKey:kColorMapCursor] colorWithAlphaComponent:1.0];
    }
    return [_colorMap colorByDimmingTextColor:color];
}

- (BOOL)shouldShowCursor {
    if (_cursorBlinking &&
        self.isInKeyWindow &&
        _textViewIsActiveSession &&
        _textViewIsFirstResponder &&
        [NSDate timeIntervalSinceReferenceDate] - _lastTimeCursorMoved > 0.5) {
        // Allow the cursor to blink if it is configured, the window is key, this session is active
        // in the tab, and the cursor has not moved for half a second.
        return _blinkingItemsVisible;
    } else {
        return YES;
    }
}

- (screen_char_t)charForCursorAtColumn:(int)column
                                inLine:(const screen_char_t *)theLine
                           doubleWidth:(BOOL *)doubleWidth {
    screen_char_t screenChar = theLine[column];
    int width = _gridSize.width;
    if (column == width) {
        screenChar = theLine[column - 1];
        screenChar.code = 0;
        screenChar.complexChar = NO;
    }
    if (screenChar.code) {
        if (ScreenCharIsDWC_RIGHT(screenChar)) {
            *doubleWidth = NO;
        } else {
            *doubleWidth = (column < width - 1) && ScreenCharIsDWC_RIGHT(theLine[column+1]);
        }
    } else {
        *doubleWidth = NO;
    }
    return screenChar;
}

- (BOOL)shouldDrawCursor {
    const BOOL shouldShowCursor = [self shouldShowCursor];
    const int column = _cursorCoord.x;
    const int row = _cursorCoord.y;
    const int width = _gridSize.width;
    const int height = _gridSize.height;
    const BOOL copyMode = self.copyMode;

    const int cursorRow = row + _numberOfScrollbackLines;
    if (!NSLocationInRange(cursorRow, [self rangeOfVisibleRows])) {
        // Don't draw a cursor that isn't in one of the rows that's being drawn (e.g., if it's on a
        // row that's just below the last visible row, don't draw it, or else the top of the cursor
        // will be visible at the bottom of the window).
        return NO;
    }
    // Draw the regular cursor only if there's not an IME open as it draws its
    // own cursor. Also, it must be not blinked-out, and it must be within the expected bounds of
    // the screen (which is just a sanity check, really).
    BOOL result = (![self hasMarkedText] &&
                   _isCursorVisible &&
                   shouldShowCursor &&
                   column <= width &&
                   column >= 0 &&
                   row >= 0 &&
                   row < height &&
                   !copyMode);
    DLog(@"shouldDrawCursor: hasMarkedText=%d, isCursorVisible=%d, showCursor=%d, column=%d, row=%d"
         @"width=%d, height=%d, copyMode=%@. Result=%@",
         (int)[self hasMarkedText], (int)_isCursorVisible, (int)shouldShowCursor, column, row,
         width, height, @(copyMode), @(result));
    return result;
}

#pragma mark - Coord/Rect Utilities

- (NSRange)rangeOfVisibleRows {
    int visibleRows = floor((_scrollViewContentSize.height - [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2) / _cellSize.height);
    CGFloat top = _scrollViewDocumentVisibleRect.origin.y;
    int firstVisibleRow = floor(top / _cellSize.height);
    if (firstVisibleRow < 0) {
        // I'm pretty sure this will never happen, but safety first when
        // dealing with unsigned integers.
        visibleRows += firstVisibleRow;
        firstVisibleRow = 0;
    }
    if (visibleRows >= 0) {
        return NSMakeRange(firstVisibleRow, visibleRows);
    } else {
        return NSMakeRange(0, 0);
    }
}

// Takes bidi into account
- (VT100GridCoordRange)visualCoordRangeForRect:(NSRect)rect {
    const VT100GridCoordRange naive = [self coordRangeForRect:rect];
    if (naive.start.x == 0 && naive.end.x >= self.gridSize.width - 1) {
        // The rect is the full width so no need to mess around with bidi stuff.
        return naive;
    }
    const int minY = floor(rect.origin.y / _cellSize.height);
    const int maxY = ceil(NSMaxY(rect) / _cellSize.height);

    VT100GridCoordRange convexHull = VT100GridCoordRangeInvalid;
    const CGFloat sideMargin = [iTermPreferences intForKey:kPreferenceKeySideMargins];
    for (int i = minY; i <= maxY; i++) {
        const VT100GridCoordRange logicalRect = VT100GridCoordRangeMake(MAX(0, floor((rect.origin.x - sideMargin) / _cellSize.width)),
                                                                        i,
                                                                        MAX(0, ceil((NSMaxX(rect) - sideMargin) / _cellSize.width)),
                                                                        i);
        VT100GridCoordRange visualRect;
        iTermBidiDisplayInfo *bidi = [self.delegate drawingHelperBidiInfoForLine:i];
        if (bidi) {
            NSRange visualRange = [bidi visualRangeForLogicalRange:NSMakeRange(logicalRect.start.x, logicalRect.end.x - logicalRect.start.x)];
            visualRect.start.x = visualRange.location;
            visualRect.end.x = NSMaxRange(visualRange);
            visualRect.start.y = logicalRect.start.y;
            visualRect.end.y = logicalRect.end.y;
        } else {
            visualRect = logicalRect;
        }
        convexHull = VT100GridCoordRangeUnionBoxes(convexHull, visualRect);
    }
    if (VT100GridCoordRangeEqualsCoordRange(convexHull, VT100GridCoordRangeInvalid)) {
        return naive;
    }
   return convexHull;
}

- (VT100GridCoordRange)coordRangeForRect:(NSRect)rect {
    return VT100GridCoordRangeMake(MAX(0, floor((rect.origin.x - [iTermPreferences intForKey:kPreferenceKeySideMargins]) / _cellSize.width)),
                                   floor(rect.origin.y / _cellSize.height),
                                   MAX(0, ceil((NSMaxX(rect) - [iTermPreferences intForKey:kPreferenceKeySideMargins]) / _cellSize.width)),
                                   ceil(NSMaxY(rect) / _cellSize.height));
}

- (NSRect)rectForCoordRange:(VT100GridCoordRange)coordRange {
    return NSMakeRect(coordRange.start.x * _cellSize.width + [iTermPreferences intForKey:kPreferenceKeySideMargins],
                      coordRange.start.y * _cellSize.height,
                      (coordRange.end.x - coordRange.start.x) * _cellSize.width,
                      (coordRange.end.y - coordRange.start.y) * _cellSize.height);
}

- (NSRect)rectByGrowingRect:(NSRect)innerRect {
    NSSize frameSize = _frame.size;
    const NSInteger extraWidth = 8;
    const NSInteger extraHeight = 1;
    NSPoint minPoint = NSMakePoint(MAX(0, innerRect.origin.x - extraWidth * _cellSize.width),
                                   MAX(0, innerRect.origin.y - extraHeight * _cellSize.height));
    NSPoint maxPoint = NSMakePoint(MIN(frameSize.width, NSMaxX(innerRect) + extraWidth * _cellSize.width),
                                   MIN(frameSize.height, NSMaxY(innerRect) + extraHeight * _cellSize.height));
    NSRect outerRect = NSMakeRect(minPoint.x,
                                  minPoint.y,
                                  maxPoint.x - minPoint.x,
                                  maxPoint.y - minPoint.y);
    return outerRect;
}

- (NSRange)rangeOfColumnsFrom:(CGFloat)x ofWidth:(CGFloat)width {
    NSRange charRange;
    charRange.location = MAX(0, (x - [iTermPreferences intForKey:kPreferenceKeySideMargins]) / _cellSize.width);
    charRange.length = ceil((x + width - [iTermPreferences intForKey:kPreferenceKeySideMargins]) / _cellSize.width) - charRange.location;
    if (charRange.location + charRange.length > _gridSize.width) {
        charRange.length = _gridSize.width - charRange.location;
    }
    return charRange;
}

// Not inclusive of end.x or end.y. Range of coords clipped to addressable lines.
- (VT100GridCoordRange)drawableCoordRangeForRect:(NSRect)rect {
    VT100GridCoordRange range;
    NSRange charRange = [self rangeOfColumnsFrom:rect.origin.x ofWidth:rect.size.width];
    range.start.x = charRange.location;
    range.end.x = charRange.location + charRange.length;

    // Where to start drawing?
    int lineStart = rect.origin.y / _cellSize.height;
    int lineEnd = ceil((rect.origin.y + rect.size.height) / _cellSize.height);

    // Ensure valid line ranges
    range.start.y = MAX(0, lineStart);
    range.end.y = MIN(lineEnd, _numberOfLines);

    return range;
}

#pragma mark - Text Utilities

- (BOOL)hasMarkedText {
    return _inputMethodMarkedRange.length > 0;
}

- (const screen_char_t *)lineAtIndex:(int)line isFirst:(BOOL *)isFirstPtr {
    if (_offscreenCommandLine && line == [self rangeOfVisibleRows].location) {
        if (isFirstPtr) {
            *isFirstPtr = YES;
        }
        return _offscreenCommandLine.characters.line;
    }
    if (isFirstPtr) {
        *isFirstPtr = NO;
    }
    return [self.delegate drawingHelperLineAtIndex:line];
}

- (const screen_char_t *)lineAtScreenIndex:(int)line {
    return [self lineAtIndex:line + _numberOfScrollbackLines isFirst:nil];
}

#pragma mark - Background Utilities

- (NSColor *)defaultBackgroundColor {
    NSColor *aColor = [_delegate drawingHelperColorForCode:ALTSEM_DEFAULT
                                                     green:0
                                                      blue:0
                                                 colorMode:ColorModeAlternate
                                                      bold:NO
                                                     faint:NO
                                              isBackground:YES];
    aColor = [_colorMap processedBackgroundColorForBackgroundColor:aColor];
    aColor = [aColor colorWithAlphaComponent:_transparencyAlpha];
    return aColor;
}

- (NSColor *)defaultTextColor {
    return [_colorMap processedTextColorForTextColor:[_colorMap colorForKey:kColorMapForeground]
                                 overBackgroundColor:[self defaultBackgroundColor]
                              disableMinimumContrast:NO];
}

- (NSColor *)blockHoverColor {
    return [self.delegate drawingHelperColorForCode:1  // red, equivalent to SGR 31
                                              green:0
                                               blue:0
                                          colorMode:ColorModeNormal
                                               bold:NO
                                              faint:NO
                                       isBackground:NO];
}

- (NSColor *)selectionColorForCurrentFocus {
    if (_isFrontTextView) {
        return [_colorMap processedBackgroundColorForBackgroundColor:[_colorMap colorForKey:kColorMapSelection]];
    } else {
        return _unfocusedSelectionColor;
    }
}

#pragma mark - Other Utility Methods

- (void)updateCachedMetrics {
    _frame = _delegate.frame;
    _visibleRectExcludingTopMargin = [_delegate textDrawingHelperVisibleRectExcludingTopMargin];
    _visibleRectIncludingTopMargin = [_delegate textDrawingHelperVisibleRectIncludingTopMargin];
    _scrollViewContentSize = _delegate.enclosingScrollView.contentSize;
    _scrollViewDocumentVisibleRect = _visibleRectExcludingTopMargin;
    _preferSpeedToFullLigatureSupport = [iTermAdvancedSettingsModel preferSpeedToFullLigatureSupport];

    BOOL ignore1 = NO, ignore2 = NO;
    UTF32Char ignore3;
    PTYFontInfo *fontInfo = [_delegate drawingHelperFontForChar:'a'
                                                      isComplex:NO
                                                     renderBold:&ignore1
                                                   renderItalic:&ignore2
                                                       remapped:&ignore3];
    _asciiLigaturesAvailable = (fontInfo.ligatureLevel > 0 || fontInfo.hasDefaultLigatures) && _asciiLigatures;
}

- (void)startTiming {
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[TIMER_BETWEEN_CALLS_TO_DRAW_RECT]);
    iTermPreciseTimerStatsStartTimer(&_stats[TIMER_TOTAL_DRAW_RECT]);
}

- (void)stopTiming {
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[TIMER_STAT_CONSTRUCTION]);
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[TIMER_STAT_DRAW]);

    iTermPreciseTimerStatsRecordTimer(&_stats[TIMER_CONSTRUCT_BACKGROUND_RUNS]);
    iTermPreciseTimerStatsRecordTimer(&_stats[TIMER_DRAW_BACKGROUND]);
    iTermPreciseTimerStatsRecordTimer(&_stats[TIMER_STAT_BUILD_MUTABLE_ATTRIBUTED_STRING]);
    iTermPreciseTimerStatsRecordTimer(&_stats[TIMER_ATTRS_FOR_CHAR]);
    iTermPreciseTimerStatsRecordTimer(&_stats[TIMER_SHOULD_SEGMENT]);
    iTermPreciseTimerStatsRecordTimer(&_stats[TIMER_ADVANCES]);
    iTermPreciseTimerStatsRecordTimer(&_stats[TIMER_UPDATE_BUILDER]);
    iTermPreciseTimerStatsRecordTimer(&_stats[TIMER_COMBINE_ATTRIBUTES]);

    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[TIMER_TOTAL_DRAW_RECT]);
    iTermPreciseTimerStatsStartTimer(&_stats[TIMER_BETWEEN_CALLS_TO_DRAW_RECT]);
}

#pragma mark - iTermCursorDelegate

- (iTermCursorNeighbors)cursorNeighbors {
    return [iTermSmartCursorColor neighborsForCursorAtCoord:_cursorCoord
                                                   gridSize:_gridSize
                                                 lineSource:^const screen_char_t *(int y) {
                                                     return [self lineAtScreenIndex:y];
                                                 }];
}

- (void)cursorDrawCharacterAt:(VT100GridCoord)coord
                  doubleWidth:(BOOL)doubleWidth
                overrideColor:(NSColor *)overrideColor
                      context:(CGContextRef)ctx
              backgroundColor:(NSColor *)backgroundColor
                virtualOffset:(CGFloat)virtualOffset {
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [context saveGraphicsState];

    int row = coord.y + _numberOfScrollbackLines;
    int width = doubleWidth ? 2 : 1;
    VT100GridCoordRange coordRange = VT100GridCoordRangeMake(coord.x, row, coord.x + width, row + 1);
    NSRect innerRect = [self rectForCoordRange:coordRange];
    iTermRectClip(innerRect, virtualOffset);

    const screen_char_t *line = [self lineAtIndex:row isFirst:nil];
    iTermImmutableMetadata metadata = [self.delegate drawingHelperMetadataOnLine:row];
    const BOOL rtlFound = metadata.rtlFound;
    id<iTermExternalAttributeIndexReading> eaIndex = iTermImmutableMetadataGetExternalAttributesIndex(metadata);

    [self constructAndDrawRunsForLine:line
                             bidiInfo:rtlFound ? [self.delegate drawingHelperBidiInfoForLine:row] : nil
                   externalAttributes:eaIndex
                      sourceLineNumer:row
                    displayLineNumber:row
                              inRange:NSMakeRange(0, _gridSize.width)
                      startingAtPoint:NSMakePoint([iTermPreferences intForKey:kPreferenceKeySideMargins], row * _cellSize.height)
                           bgselected:NO
                              bgColor:backgroundColor
             processedBackgroundColor:backgroundColor
                             colorRun:nil
                              matches:nil
                       forceTextColor:overrideColor
                              context:ctx
                        virtualOffset:virtualOffset];

    [context restoreGraphicsState];
}

+ (BOOL)cursorUsesBackgroundColorForScreenChar:(screen_char_t)screenChar
                                wantBackground:(BOOL)wantBackgroundColor
                                  reverseVideo:(BOOL)reverseVideo {
    if (reverseVideo) {
        if (wantBackgroundColor &&
            screenChar.backgroundColorMode == ColorModeAlternate &&
            screenChar.backgroundColor == ALTSEM_DEFAULT) {
            return NO;
        } else if (!wantBackgroundColor &&
                   screenChar.foregroundColorMode == ColorModeAlternate &&
                   screenChar.foregroundColor == ALTSEM_DEFAULT) {
            return YES;
        }
    }

    return wantBackgroundColor;
}

- (NSColor *)cursorColorForCharacter:(screen_char_t)screenChar
                      wantBackground:(BOOL)wantBackgroundColor
                               muted:(BOOL)muted {
    BOOL isBackground = [iTermTextDrawingHelper cursorUsesBackgroundColorForScreenChar:screenChar
                                                                        wantBackground:wantBackgroundColor
                                                                          reverseVideo:_reverseVideo];
    NSColor *color;
    if (wantBackgroundColor) {
        color = [_delegate drawingHelperColorForCode:screenChar.backgroundColor
                                               green:screenChar.bgGreen
                                                blue:screenChar.bgBlue
                                           colorMode:screenChar.backgroundColorMode
                                                bold:screenChar.bold
                                               faint:screenChar.faint
                                        isBackground:isBackground];
    } else {
        color = [_delegate drawingHelperColorForCode:screenChar.foregroundColor
                                               green:screenChar.fgGreen
                                                blue:screenChar.fgBlue
                                           colorMode:screenChar.foregroundColorMode
                                                bold:screenChar.bold
                                               faint:screenChar.faint
                                        isBackground:isBackground];
    }
    if (muted) {
        color = [_colorMap colorByMutingColor:color];
    }
    return color;
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

- (NSColor *)cursorColorByDimmingSmartColor:(NSColor *)color {
    return [_colorMap colorByDimmingTextColor:color];
}

#pragma mark - iTermAttributedStringBuilderDelegate

- (NSColor *)colorForCode:(int)theIndex
                    green:(int)green
                     blue:(int)blue
                colorMode:(ColorMode)theMode
                     bold:(BOOL)isBold
                    faint:(BOOL)isFaint
             isBackground:(BOOL)isBackground {
    return [self.delegate drawingHelperColorForCode:theIndex
                                              green:green
                                               blue:blue
                                          colorMode:theMode
                                               bold:isBold
                                              faint:isFaint
                                       isBackground:isBackground];
}

@end
