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
#import "iTermAttributedStringProxy.h"
#import "iTermBackgroundColorRun.h"
#import "iTermBoxDrawingBezierCurveFactory.h"
#import "iTermColorMap.h"
#import "iTermController.h"
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

#define likely(x) __builtin_expect(!!(x), 1)
#define unlikely(x) __builtin_expect(!!(x), 0)
#define MEDIAN(min_, mid_, max_) MAX(MIN(mid_, max_), min_)

static const int kBadgeMargin = 4;
const CGFloat iTermOffscreenCommandLineVerticalPadding = 8.0;

extern void CGContextSetFontSmoothingStyle(CGContextRef, int);
extern int CGContextGetFontSmoothingStyle(CGContextRef);

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

@interface iTermTextDrawingHelper() <iTermCursorDelegate>
@end

typedef NS_ENUM(unsigned char, iTermCharacterAttributesUnderline) {
    iTermCharacterAttributesUnderlineNone,
    iTermCharacterAttributesUnderlineRegular,  // Single unless isURL, then double.
    iTermCharacterAttributesUnderlineCurly,
    iTermCharacterAttributesUnderlineDouble
};

// IMPORTANT: If you add a field here also update the comparison function
// shouldSegmentWithAttributes:imageAttributes:previousAttributes:previousImageAttributes:combinedAttributesChanged:
typedef struct {
    BOOL initialized;
    BOOL shouldAntiAlias;
    NSColor *foregroundColor;
    BOOL boxDrawing;
    NSFont *font;
    BOOL bold;
    BOOL faint;
    BOOL fakeBold;
    BOOL fakeItalic;
    iTermCharacterAttributesUnderline underlineType;
    BOOL strikethrough;
    BOOL isURL;
    NSInteger ligatureLevel;
    BOOL drawable;
    BOOL hasUnderlineColor;
    VT100TerminalColorValue underlineColor;
} iTermCharacterAttributes;

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

static NSString *const iTermAntiAliasAttribute = @"iTermAntiAliasAttribute";
static NSString *const iTermBoldAttribute = @"iTermBoldAttribute";
static NSString *const iTermFaintAttribute = @"iTermFaintAttribute";
static NSString *const iTermFakeBoldAttribute = @"iTermFakeBoldAttribute";
static NSString *const iTermFakeItalicAttribute = @"iTermFakeItalicAttribute";
static NSString *const iTermImageCodeAttribute = @"iTermImageCodeAttribute";
static NSString *const iTermImageColumnAttribute = @"iTermImageColumnAttribute";
static NSString *const iTermImageLineAttribute = @"iTermImageLineAttribute";
static NSString *const iTermImageDisplayColumnAttribute = @"iTermImageDisplayColumnAttribute";
static NSString *const iTermIsBoxDrawingAttribute = @"iTermIsBoxDrawingAttribute";
static NSString *const iTermUnderlineLengthAttribute = @"iTermUnderlineLengthAttribute";
static NSString *const iTermHasUnderlineColorAttribute = @"iTermHasUnderlineColorAttribute";
static NSString *const iTermUnderlineColorAttribute = @"iTermUnderlineColorAttribute";  // @[r,g,b,mode]

typedef struct iTermTextColorContext {
    NSColor *lastUnprocessedColor;
    CGFloat dimmingAmount;
    CGFloat mutingAmount;
    BOOL hasSelectedText;
    iTermColorMap *colorMap;
    id<iTermTextDrawingHelperDelegate> delegate;
    NSData *findMatches;
    BOOL reverseVideo;
    screen_char_t previousCharacterAttributes;
    BOOL havePreviousCharacterAttributes;
    NSColor *backgroundColor;
    NSColor *previousBackgroundColor;
    CGFloat minimumContrast;
    NSColor *previousForegroundColor;
} iTermTextColorContext;

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
    NSRect _visibleRect;

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
    [self updateCachedMetrics];
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

    VT100GridCoordRange boundingCoordRange = [self coordRangeForRect:rect];
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
    NSMutableData *store = [NSMutableData dataWithLength:numRowsInRect * sizeof(NSRange)];
    NSRange *ranges = (NSRange *)store.mutableBytes;
    for (int i = 0; i < rectCount; i++) {
        VT100GridCoordRange coordRange = [self coordRangeForRect:rectArray[i]];
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

    [self drawRanges:ranges
               count:numRowsInRect
              origin:boundingCoordRange.start
        boundingRect:[self rectForCoordRange:boundingCoordRange]
        visibleLines:visibleLines
       virtualOffset:virtualOffset];

    if (_showDropTargets) {
        [self drawDropTargetsWithVirtualOffset:virtualOffset];
    }

    [self stopTiming];

    iTermPreciseTimerPeriodicLog(@"drawRect", _stats, sizeof(_stats) / sizeof(*_stats), 5, [iTermAdvancedSettingsModel logDrawingPerformance], nil);

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
            iTermBackgroundColorRunsInLine *runsInLine =
            [iTermBackgroundColorRunsInLine backgroundRunsInLine:theLine
                                                      lineLength:_gridSize.width
                                                             row:line
                                                 selectedIndexes:selectedIndexes
                                                     withinRange:charRange
                                                         matches:matches
                                                        anyBlink:&_blinkingFound
                                                               y:y];
            [backgroundRunArrays addObject:runsInLine];
        } else {
            [backgroundRunArrays addObject:[iTermBackgroundColorRunsInLine defaultRunOfLength:_gridSize.width row:line y:y]];
        }
        iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_CONSTRUCT_BACKGROUND_RUNS]);
    }

    iTermPreciseTimerStatsStartTimer(&_stats[TIMER_DRAW_BACKGROUND]);
    // If a background image is in use, draw the whole rect at once.
    if (_hasBackgroundImage) {
        [self.delegate drawingHelperDrawBackgroundImageInRect:boundingRect
                                       blendDefaultBackground:NO
                                                virtualOffset:virtualOffset];
    }

    NSColor *cursorBackgroundColor = nil;
    const int cursorY = self.cursorCoord.y + origin.y;
    // Now iterate over the lines and paint the backgrounds.
    for (NSInteger i = 0; i < backgroundRunArrays.count; ) {
        NSInteger rows = [self numberOfEquivalentBackgroundColorLinesInRunArrays:backgroundRunArrays fromIndex:i];
        iTermBackgroundColorRunsInLine *runArray = backgroundRunArrays[i];
        runArray.numberOfEquivalentRows = rows;
        if (cursorY >= runArray.line &&
            cursorY < runArray.line + runArray.numberOfEquivalentRows) {
            NSColor *color = [self unprocessedColorForBackgroundRun:[runArray runAtIndex:self.cursorCoord.x] ?: runArray.lastRun
                                                     enableBlending:NO];
            cursorBackgroundColor = [_colorMap processedBackgroundColorForBackgroundColor:color];
        }
        [self drawBackgroundForLine:runArray.line
                                atY:runArray.y
                               runs:runArray.array
                     equivalentRows:rows
                      virtualOffset:virtualOffset];
        for (NSInteger j = i; j < i + rows; j++) {
            [self drawMarginsAndMarkForLine:backgroundRunArrays[j].line
                                          y:backgroundRunArrays[j].y
                              virtualOffset:virtualOffset];
        }
        i += rows;
    }
    iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_DRAW_BACKGROUND]);

    // Draw default background color over the line under the last drawn line so the tops of
    // characters aren't visible there. If there is an IME, that could be many lines tall.
    VT100GridCoordRange drawableCoordRange = [self drawableCoordRangeForRect:_visibleRect];
    [self drawExcessAtLine:drawableCoordRange.end.y
             virtualOffset:virtualOffset];

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

    [self drawTopMarginWithVirtualOffset:virtualOffset];

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

- (void)drawBackgroundForLine:(int)line
                          atY:(CGFloat)yOrigin
                         runs:(NSArray<iTermBoxedBackgroundColorRun *> *)runs
               equivalentRows:(NSInteger)rows
                virtualOffset:(CGFloat)virtualOffset {
    BOOL pad = NO;
    NSSize padding = { 0 };
    if ([self.delegate drawingHelperShouldPadBackgrounds:&padding]) {
        pad = YES;
    }
    for (iTermBoxedBackgroundColorRun *box in runs) {
        iTermBackgroundColorRun *run = box.valuePointer;

//        NSLog(@"Paint background row %d range %@", line, NSStringFromRange(run->range));

        NSRect rect = NSMakeRect(floor([iTermPreferences intForKey:kPreferenceKeySideMargins] + run->range.location * _cellSize.width),
                                 yOrigin,
                                 ceil(run->range.length * _cellSize.width),
                                 _cellSize.height * rows);
        // If subpixel AA is enabled, then we want to draw the default background color directly.
        // Otherwise, we'll disable blending and make it clear. Then the background color view can
        // do the job. We have to use blending when taking a snapshot in order to not have a clear
        // background color. I'm not sure why snapshots don't work right. My theory is that macOS
        // doesn't composiste multiple views correctly.
        BOOL enableBlending = !iTermTextIsMonochrome() || [NSView iterm_takingSnapshot];
        NSColor *color = [self unprocessedColorForBackgroundRun:run
                                                 enableBlending:enableBlending];
        // The unprocessed color is needed for minimum contrast computation for text color.
        box.unprocessedBackgroundColor = color;
        color = [_colorMap processedBackgroundColorForBackgroundColor:color];
        box.backgroundColor = color;

        [box.backgroundColor set];

        if (pad) {
            if (color.alphaComponent == 0) {
                continue;
            }
            NSRect temp = rect;
            temp.origin.x -= padding.width;
            temp.origin.y -= padding.height;
            temp.size.width += padding.width * 2;
            temp.size.height += padding.height * 2;

            iTermRectFillUsingOperation(temp,
                                        enableBlending ? NSCompositingOperationSourceOver : NSCompositingOperationCopy,
                                        virtualOffset);
        } else {
            iTermRectFillUsingOperation(rect,
                                        enableBlending ? NSCompositingOperationSourceOver : NSCompositingOperationCopy,
                                        virtualOffset);
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

- (NSColor *)unprocessedColorForBackgroundRun:(iTermBackgroundColorRun *)run
                               enableBlending:(BOOL)enableBlending {
    NSColor *color;
    CGFloat alpha = _transparencyAlpha;
    if (run->selected) {
        color = [self selectionColorForCurrentFocus];
        if (_transparencyAffectsOnlyDefaultBackgroundColor) {
            alpha = 1;
        }
    } else if (run->isMatch) {
        color = [NSColor colorWithCalibratedRed:1 green:1 blue:0 alpha:1];
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

- (void)drawExcessAtLine:(int)line
           virtualOffset:(CGFloat)virtualOffset {
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
        NSRect visibleRect = _visibleRect;
        excessRect.origin.x = 0;
        excessRect.origin.y = NSMaxY(visibleRect) - _excess;
        excessRect.size.width = _scrollViewContentSize.width;
        excessRect.size.height = _excess;
    }

    [self.delegate drawingHelperDrawBackgroundImageInRect:excessRect
                                   blendDefaultBackground:YES
                                            virtualOffset:virtualOffset];

    if (_debug) {
        [[NSColor blueColor] set];
        NSBezierPath *path = [NSBezierPath bezierPath];
        [path moveToPoint:excessRect.origin];
        [path lineToPoint:NSMakePoint(NSMaxX(excessRect), NSMaxY(excessRect))];
        [path stroke];

        NSFrameRect(excessRect);
    }

    if (_showStripes) {
        [self drawStripesInRect:excessRect virtualOffset:virtualOffset];
    }
}

- (void)drawTopMarginWithVirtualOffset:(CGFloat)virtualOffset {
    // Draw a margin at the top of the visible area.
    NSRect topMarginRect = _visibleRect;
    topMarginRect.origin.y -= [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];

    topMarginRect.size.height = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    [self.delegate drawingHelperDrawBackgroundImageInRect:topMarginRect
                                   blendDefaultBackground:YES
                                            virtualOffset:virtualOffset];

    if (_showStripes) {
        [self drawStripesInRect:topMarginRect virtualOffset:virtualOffset];
    }
}

- (void)drawMarginsAndMarkForLine:(int)line
                                y:(CGFloat)y
                    virtualOffset:(CGFloat)virtualOffset {
    NSRect leftMargin = NSMakeRect(0, y, MAX(0, [iTermPreferences intForKey:kPreferenceKeySideMargins]), _cellSize.height);
    NSRect rightMargin;
    NSRect visibleRect = _visibleRect;
    rightMargin.origin.x = _cellSize.width * _gridSize.width + [iTermPreferences intForKey:kPreferenceKeySideMargins];
    rightMargin.origin.y = y;
    rightMargin.size.width = visibleRect.size.width - rightMargin.origin.x;
    rightMargin.size.height = _cellSize.height;

    // Draw background in margins
    [self.delegate drawingHelperDrawBackgroundImageInRect:leftMargin
                                   blendDefaultBackground:YES
                                            virtualOffset:virtualOffset];
    [self.delegate drawingHelperDrawBackgroundImageInRect:rightMargin
                                   blendDefaultBackground:YES
                                            virtualOffset:virtualOffset];

    [self drawMarkIfNeededOnLine:line
                  leftMarginRect:leftMargin
                   virtualOffset:virtualOffset];
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
    NSRect rect = NSMakeRect(textOrigin.x,
                             textOrigin.y,
                             range.length * _cellSize.width,
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
                           pixelSize:(CGSize)pixelSize {
    NSSize pointSize = [NSImage pointSizeOfGeneratedImageWithPixelSize:pixelSize];
    return [self newImageWithMarkOfColor:color size:pointSize];
}

+ (NSImage *)newImageWithMarkOfColor:(NSColor *)color
                                size:(CGSize)size {
    if (size.width < 1 || size.height < 1) {
        return [self newImageWithMarkOfColor:color
                                        size:CGSizeMake(MAX(1, size.width),
                                                        MAX(1, size.height))];
    }
    NSImage *img = [NSImage imageOfSize:size drawBlock:^{
        CGRect rect = CGRectMake(0, 0, MAX(1, size.width), size.height);

        NSPoint bottom = NSMakePoint(NSMinX(rect), NSMinY(rect));
        NSPoint right = NSMakePoint(NSMaxX(rect), NSMidY(rect));
        NSPoint top = NSMakePoint(NSMinX(rect), NSMaxY(rect));

        if (size.width < 2) {
            NSRect rect = NSMakeRect(0, 0, size.width, size.height);
            rect = NSInsetRect(rect, 0, rect.size.height * 0.25);
            [[color colorWithAlphaComponent:0.75] set];
            NSRectFill(rect);
        } else {
            NSBezierPath *path = [NSBezierPath bezierPath];
            [color set];
            [path moveToPoint:top];
            [path lineToPoint:right];
            [path lineToPoint:bottom];
            [path lineToPoint:top];
            [path fill];

            [[NSColor blackColor] set];
            path = [NSBezierPath bezierPath];
            [path moveToPoint:NSMakePoint(bottom.x, bottom.y)];
            [path lineToPoint:NSMakePoint(right.x, right.y)];
            [path setLineWidth:1.0];
            [path stroke];
        }
    }];

    return img;
}

+ (iTermMarkIndicatorType)markIndicatorTypeForMark:(id<VT100ScreenMarkReading>)mark {
    if (mark.code == 0) {
        return iTermMarkIndicatorTypeSuccess;
    }
    if ([iTermAdvancedSettingsModel showYellowMarkForJobStoppedBySignal] &&
        mark.code >= 128 && mark.code <= 128 + 32) {
        // Stopped by a signal (or an error, but we can't tell which)
        return iTermMarkIndicatorTypeOther;
    }
    return iTermMarkIndicatorTypeError;
}

+ (NSColor *)colorForMark:(id<VT100ScreenMarkReading>)mark {
    return [self colorForMarkType:[iTermTextDrawingHelper markIndicatorTypeForMark:mark]];
}

+ (NSColor *)colorForMarkType:(iTermMarkIndicatorType)type {
    switch (type) {
        case iTermMarkIndicatorTypeSuccess:
            return [iTermTextDrawingHelper successMarkColor];
        case iTermMarkIndicatorTypeOther:
            return [iTermTextDrawingHelper otherMarkColor];
        case iTermMarkIndicatorTypeError:
            return [iTermTextDrawingHelper errorMarkColor];
    }
}

- (BOOL)canDrawLine:(int)line {
    return (line < _linesToSuppress.location ||
            line >= _linesToSuppress.location + _linesToSuppress.length);
}

- (void)drawMarkIfNeededOnLine:(int)line
                leftMarginRect:(NSRect)leftMargin
                 virtualOffset:(CGFloat)virtualOffset {
    if (![self canDrawLine:line]) {
        return;
    }
    id<VT100ScreenMarkReading> mark = [self.delegate drawingHelperMarkOnLine:line];
    if (mark != nil && self.drawMarkIndicators) {
        if (mark.lineStyle) {
            NSColor *bgColor = [self defaultBackgroundColor];
            NSColor *merged = [iTermTextDrawingHelper colorForLineStyleMark:[iTermTextDrawingHelper markIndicatorTypeForMark:mark]
                                                            backgroundColor:bgColor];
            [merged set];
            NSRect rect;
            rect.origin.x = 0;
            rect.size.width = _visibleRect.size.width;
            rect.size.height = 1;
            const CGFloat y = (((CGFloat)line) - 0.5) * _cellSize.height;
            rect.origin.y = round(y);
            iTermRectFill(rect, virtualOffset);
        } else {
            NSRect insetLeftMargin = leftMargin;
            insetLeftMargin.origin.x += 1;
            insetLeftMargin.size.width -= 1;
            NSRect rect = [iTermTextDrawingHelper frameForMarkContainedInRect:insetLeftMargin
                                                                     cellSize:_cellSize
                                                       cellSizeWithoutSpacing:_cellSizeWithoutSpacing
                                                                        scale:1];
            const iTermMarkIndicatorType type = [iTermTextDrawingHelper markIndicatorTypeForMark:mark];
            NSImage *image = _cachedMarks[@(type)];
            if (!image || !NSEqualSizes(image.size, rect.size)) {
                NSColor *markColor = [iTermTextDrawingHelper colorForMark:mark];
                image = [iTermTextDrawingHelper newImageWithMarkOfColor:markColor
                                                                   size:rect.size];
                _cachedMarks[@(type)] = image;
            }
            [image it_drawInRect:rect virtualOffset:virtualOffset];
        }
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
                       !previousRun.beneathFaintText) {
                // Combine with preceding run.
                previousRun.range = NSUnionRange(previousRun.range, run.valuePointer->range);
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
        [self drawForegroundForLineNumber:runArray.line
                                        y:y
                           backgroundRuns:representativeRunArray.array
                                  context:ctx
                            virtualOffset:virtualOffset];
    }
}

- (void)drawForegroundForLineNumber:(int)line
                                  y:(CGFloat)y
                     backgroundRuns:(NSArray<iTermBoxedBackgroundColorRun *> *)backgroundRuns
                            context:(CGContextRef)ctx
                      virtualOffset:(CGFloat)virtualOffset {
    if (![self canDrawLine:line]) {
        return;
    }
    [self drawCharactersForLine:line
                            atY:y
                 backgroundRuns:backgroundRuns
                        context:ctx
                  virtualOffset:virtualOffset];
    [self drawNoteRangesOnLine:line
                 virtualOffset:virtualOffset];

    if (_debug) {
        NSString *s = [NSString stringWithFormat:@"%d", line];
        [s it_drawAtPoint:NSMakePoint(0, y)
           withAttributes:@{ NSForegroundColorAttributeName: [NSColor blackColor],
                             NSBackgroundColorAttributeName: [NSColor whiteColor],
                             NSFontAttributeName: [NSFont systemFontOfSize:8] }
            virtualOffset:virtualOffset];
    }
}

#pragma mark - Drawing: Text

- (void)drawCharactersForLine:(int)line
                          atY:(CGFloat)y
               backgroundRuns:(NSArray<iTermBoxedBackgroundColorRun *> *)backgroundRuns
                      context:(CGContextRef)ctx
                virtualOffset:(CGFloat)virtualOffset {
    const screen_char_t *theLine = [self lineAtIndex:line isFirst:nil];
    id<iTermExternalAttributeIndexReading> eaIndex = [self.delegate drawingHelperExternalAttributesOnLine:line];
    NSData *matches = [_delegate drawingHelperMatchesOnLine:line];
    for (iTermBoxedBackgroundColorRun *box in backgroundRuns) {
        iTermBackgroundColorRun *run = box.valuePointer;
        NSPoint textOrigin = NSMakePoint([iTermPreferences intForKey:kPreferenceKeySideMargins] + run->range.location * _cellSize.width,
                                         y);
        [self constructAndDrawRunsForLine:theLine
                       externalAttributes:eaIndex
                                      row:line
                                  inRange:run->range
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
                 externalAttributes:(id<iTermExternalAttributeIndexReading>)eaIndex
                                row:(int)row
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
    NSArray<id<iTermAttributedString>> *attributedStrings = [self attributedStringsForLine:theLine
                                                                        externalAttributes:eaIndex
                                                                                     range:indexRange
                                                                           hasSelectedText:bgselected
                                                                           backgroundColor:bgColor
                                                                            forceTextColor:forceTextColor
                                                                                  colorRun:colorRun
                                                                               findMatches:matches
                                                                           underlinedRange:[self underlinedRangeOnLine:row + _totalScrollbackOverflow]
                                                                                 positions:&positions];
    iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_STAT_CONSTRUCTION]);

    iTermPreciseTimerStatsStartTimer(&_stats[TIMER_STAT_DRAW]);
    NSPoint adjustedPoint = initialPoint;
    if (_offscreenCommandLine && row == [self rangeOfVisibleRows].location) {
        adjustedPoint.y += iTermOffscreenCommandLineVerticalPadding;
    }
    [self drawMultipartAttributedString:attributedStrings
                                atPoint:adjustedPoint
                                 origin:VT100GridCoordMake(indexRange.location, row)
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
        int displayColumn = [attributes[iTermImageDisplayColumnAttribute] intValue];
        [self drawImageWithCode:[attributes[iTermImageCodeAttribute] shortValue]
                         origin:VT100GridCoordMake(displayColumn, origin.y)
                         length:cheapString.length
                        atPoint:NSMakePoint(positions[0] + point.x, point.y)
                  originInImage:originInImage
                  virtualOffset:virtualOffset];
        return cheapString.length;
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
    NSColor *underlineColor;
    const BOOL hasUnderlineColor = [attributes[iTermHasUnderlineColorAttribute] boolValue];
    if (hasUnderlineColor) {
        NSArray<NSNumber *> *components = attributes[iTermUnderlineColorAttribute];
        underlineColor = [self.delegate drawingHelperColorForCode:components[0].intValue
                                                            green:components[1].intValue
                                                             blue:components[2].intValue
                                                        colorMode:components[3].intValue
                                                             bold:[attributes[iTermBoldAttribute] boolValue]
                                                            faint:[attributes[iTermFaintAttribute] boolValue]
                                                     isBackground:NO];
    } else {
        NSColor *underline = [self.colorMap colorForKey:kColorMapUnderline];
        if (underline) {
            underlineColor = underline;
        } else {
            CGColorRef cgColor = (__bridge CGColorRef)attributes[(NSString *)kCTForegroundColorAttributeName];
            underlineColor = [NSColor colorWithCGColor:cgColor];
        }
    }
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
    BOOL fakeBold = [attributes[iTermFakeBoldAttribute] boolValue];
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

    CFArrayRef runs = CTLineGetGlyphRuns(lineRef);
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
                                                         origin.x + xOriginsForCharacters[0], ty);
    CGContextSetTextMatrix(cgContext, textMatrix);

    // The x origin of the column for the current cell. Initialize to -1 to ensure it gets set on
    // the first pass through the position-adjusting loop.
    CGFloat xOriginForCurrentColumn = -1;
    CFIndex previousCharacterIndex = -1;
    CGFloat advanceAccumulator = 0;
    const BOOL verbose = NO;  // turn this on to debug character position problems.
    if (verbose) {
        NSLog(@"Begin drawing string: %@", attributedString.string);
    }
    for (CFIndex j = 0; j < CFArrayGetCount(runs); j++) {
        CTRunRef run = CFArrayGetValueAtIndex(runs, j);
        size_t length = CTRunGetGlyphCount(run);
        const CGGlyph *buffer = CTRunGetGlyphsPtr(run);
        if (!buffer) {
            NSMutableData *tempBuffer =
            [[NSMutableData alloc] initWithLength:sizeof(CGGlyph) * length];
            CTRunGetGlyphs(run, CFRangeMake(0, length), (CGGlyph *)tempBuffer.mutableBytes);
            buffer = tempBuffer.mutableBytes;
        }

        NSMutableData *positionsBuffer =
        [[NSMutableData alloc] initWithLength:sizeof(CGPoint) * length];
        CTRunGetPositions(run, CFRangeMake(0, length), (CGPoint *)positionsBuffer.mutableBytes);
        CGPoint *positions = positionsBuffer.mutableBytes;

        NSMutableData *advancesBuffer =
        [[NSMutableData alloc] initWithLength:sizeof(CGSize) * length];
        CTRunGetAdvances(run, CFRangeMake(0, length), advancesBuffer.mutableBytes);
        CGSize *advances = advancesBuffer.mutableBytes;

        const CFIndex *glyphIndexToCharacterIndex = CTRunGetStringIndicesPtr(run);
        if (!glyphIndexToCharacterIndex) {
            NSMutableData *tempBuffer =
            [[NSMutableData alloc] initWithLength:sizeof(CFIndex) * length];
            CTRunGetStringIndices(run, CFRangeMake(0, length), (CFIndex *)tempBuffer.mutableBytes);
            glyphIndexToCharacterIndex = (CFIndex *)tempBuffer.mutableBytes;
        }

        // Transform positions to put each grapheme cluster in its proper column.
        // positions[glyphIndex].x needs to be transformed to subtract whatever horizontal advance
        // was present earlier in the string.

        // xOffset gives the accumulated advances to subtract from the current character's x position
        CGFloat xOffset = 0;
        if (verbose) {
            NSLog(@"Begin run %@", @(j));
        }
        for (size_t glyphIndex = 0; glyphIndex < length; glyphIndex++) {
            // `characterIndex` indexes into the attributed string.
            const CFIndex characterIndex = glyphIndexToCharacterIndex[glyphIndex];
            const CGFloat xOriginForThisCharacter = xOriginsForCharacters[characterIndex] - xOriginsForCharacters[0];

            if (verbose) {
                NSLog(@"  begin glyph %@", @(glyphIndex));
            }
            if (characterIndex != previousCharacterIndex &&
                xOriginForThisCharacter != xOriginForCurrentColumn) {
                // Have advanced to the next character or column.
                xOffset = advanceAccumulator;
                xOriginForCurrentColumn = xOriginForThisCharacter;
                if (verbose) {
                    NSLog(@"  This glyph begins a new character or column. xOffset<-%@, xOriginForCurrentColumn<-%@", @(xOffset), @(xOriginForCurrentColumn));
                }
            }
            advanceAccumulator = advances[glyphIndex].width + positions[glyphIndex].x;
            if (verbose) {
                NSLog(@"  advance=%@, position=%@. advanceAccumulator<-%@", @(advances[glyphIndex].width), @(positions[glyphIndex].x), @(advanceAccumulator));
            }
            positions[glyphIndex].x += xOriginForCurrentColumn - xOffset;
            if (verbose) {
                NSLog(@"  position<-%@", @(positions[glyphIndex].x));
            }
        }

        CTFontRef runFont = CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);
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
    }
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
         const NSSize size = NSMakeSize([attributes[iTermUnderlineLengthAttribute] intValue] * _cellSize.width,
                                        _cellSize.height * 2);
         const CGFloat xOrigin = origin.x + stringPositions[range.location];
         const NSRect rect = NSMakeRect(xOrigin,
                                        origin.y,
                                        size.width,
                                        size.height);
         NSColor *underline = [self.colorMap colorForKey:kColorMapUnderline];
         NSColor *underlineColor;
         if (underline) {
             underlineColor = underline;
         } else {
             CGColorRef cgColor = (__bridge CGColorRef)attributes[(__bridge NSString *)kCTForegroundColorAttributeName];
             underlineColor = [NSColor colorWithCGColor:cgColor];
         }
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

NSColor *iTermTextDrawingHelperGetTextColor(iTermTextDrawingHelper *self,
                                            screen_char_t *c,
                                            BOOL inUnderlinedRange,
                                            int index,
                                            iTermTextColorContext *context,
                                            iTermBackgroundColorRun *colorRun,
                                            BOOL isBoxDrawingCharacter) {
    NSColor *rawColor = nil;
    BOOL isMatch = NO;
    if (c->faint && colorRun && !context->backgroundColor) {
        context->backgroundColor = [self unprocessedColorForBackgroundRun:colorRun
                                                           enableBlending:YES];
    }
    const BOOL needsProcessing = context->backgroundColor && (context->minimumContrast > 0.001 ||
                                                              context->dimmingAmount > 0.001 ||
                                                              context->mutingAmount > 0.001 ||
                                                              c->faint);  // faint implies alpha<1 and is faster than getting the alpha component

    if (context->findMatches && !context->hasSelectedText) {
        // Test if this is a highlighted match from a find.
        int theIndex = index / 8;
        int mask = 1 << (index & 7);
        const char *matchBytes = context->findMatches.bytes;
        if (theIndex < [context->findMatches length] && (matchBytes[theIndex] & mask)) {
            isMatch = YES;
        }
    }

    if (isMatch) {
        // Black-on-yellow search result.
        rawColor = [NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:1];
        assert(rawColor);
        context->havePreviousCharacterAttributes = NO;
    } else if (inUnderlinedRange) {
        // Blue link text.
        rawColor = [context->colorMap colorForKey:kColorMapLink];
        assert(rawColor);
        context->havePreviousCharacterAttributes = NO;
    } else if (context->hasSelectedText && self.useSelectedTextColor) {
        // Selected text.
        rawColor = [context->colorMap colorForKey:kColorMapSelectedText];
        assert(rawColor);
        context->havePreviousCharacterAttributes = NO;
    } else if (context->reverseVideo &&
               ((c->foregroundColor == ALTSEM_DEFAULT && c->foregroundColorMode == ColorModeAlternate) ||
                (c->foregroundColor == ALTSEM_CURSOR && c->foregroundColorMode == ColorModeAlternate))) {
        // Reverse video is on. Either is cursor or has default foreground color. Use
        // background color.
        rawColor = [context->colorMap colorForKey:kColorMapBackground];
        assert(rawColor);
        context->havePreviousCharacterAttributes = NO;
    } else if (!context->havePreviousCharacterAttributes ||
               c->foregroundColor != context->previousCharacterAttributes.foregroundColor ||
               c->fgGreen != context->previousCharacterAttributes.fgGreen ||
               c->fgBlue != context->previousCharacterAttributes.fgBlue ||
               c->foregroundColorMode != context->previousCharacterAttributes.foregroundColorMode ||
               c->bold != context->previousCharacterAttributes.bold ||
               c->faint != context->previousCharacterAttributes.faint ||
               !context->previousForegroundColor) {
        // "Normal" case for uncached text color. Recompute the unprocessed color from the character.
        context->previousCharacterAttributes = *c;
        context->havePreviousCharacterAttributes = YES;
        rawColor = [context->delegate drawingHelperColorForCode:c->foregroundColor
                                                          green:c->fgGreen
                                                           blue:c->fgBlue
                                                      colorMode:c->foregroundColorMode
                                                           bold:c->bold
                                                          faint:c->faint
                                                   isBackground:NO];
        assert(rawColor);
    } else {
        // Foreground attributes are just like the last character. There is a cached foreground color.
        if (needsProcessing && context->backgroundColor != context->previousBackgroundColor) {
            // Process the text color for the current background color, which has changed since
            // the last cell.
            rawColor = context->lastUnprocessedColor;
            assert(rawColor);
        } else {
            // Text color is unchanged. Either it's independent of the background color or the
            // background color has not changed.
            return context->previousForegroundColor;
        }
    }

    context->lastUnprocessedColor = rawColor;

    NSColor *result = nil;
    if (needsProcessing) {
        result = [context->colorMap processedTextColorForTextColor:rawColor
                                               overBackgroundColor:context->backgroundColor
                                            disableMinimumContrast:isBoxDrawingCharacter];
    } else {
        result = rawColor;
    }
    context->previousForegroundColor = result;
    assert(result);
    return result;
}

static BOOL iTermTextDrawingHelperShouldAntiAlias(screen_char_t *c,
                                                  BOOL useNonAsciiFont,
                                                  BOOL asciiAntiAlias,
                                                  BOOL nonAsciiAntiAlias,
                                                  BOOL isRetina,
                                                  BOOL forceAntialiasingOnRetina) {
    if (isRetina && forceAntialiasingOnRetina) {
        return YES;
    }
    if (!useNonAsciiFont || (c->code < 128 && !c->complexChar)) {
        return asciiAntiAlias;
    } else {
        return nonAsciiAntiAlias;
    }
}

static inline BOOL iTermCharacterAttributesUnderlineColorEqual(iTermCharacterAttributes *newAttributes,
                                                               iTermCharacterAttributes *previousAttributes) {
    if (newAttributes->hasUnderlineColor != previousAttributes->hasUnderlineColor) {
        return NO;
    }
    if (!newAttributes->hasUnderlineColor) {
        return YES;
    }
    return memcmp(&newAttributes->underlineColor,
                  &previousAttributes->underlineColor,
                  sizeof(newAttributes->underlineColor)) == 0;
}

- (BOOL)shouldSegmentWithAttributes:(iTermCharacterAttributes *)newAttributes
                    imageAttributes:(NSDictionary *)imageAttributes
                 previousAttributes:(iTermCharacterAttributes *)previousAttributes
            previousImageAttributes:(NSDictionary *)previousImageAttributes
           combinedAttributesChanged:(BOOL *)combinedAttributesChanged {
    if (unlikely(!previousAttributes->initialized)) {
        // First char of first segment
        *combinedAttributesChanged = YES;
        return NO;
    }

    if (likely(!imageAttributes && !previousImageAttributes)) {
        // Not an image cell. Try to quickly check if the attributes are the same, which is the normal case.
        if (likely(!memcmp(previousAttributes, newAttributes, sizeof(*previousAttributes)))) {
            // Identical, byte-for-byte
            *combinedAttributesChanged = NO;
        } else {
            // Properly compare object fields
            *combinedAttributesChanged = (newAttributes->shouldAntiAlias != previousAttributes->shouldAntiAlias ||
                                          ![newAttributes->foregroundColor isEqual:previousAttributes->foregroundColor] ||
                                          newAttributes->boxDrawing != previousAttributes->boxDrawing ||
                                          ![newAttributes->font isEqual:previousAttributes->font] ||
                                          newAttributes->ligatureLevel != previousAttributes->ligatureLevel ||
                                          newAttributes->bold != previousAttributes->bold ||
                                          newAttributes->faint != previousAttributes->faint ||
                                          newAttributes->fakeItalic != previousAttributes->fakeItalic ||
                                          newAttributes->underlineType != previousAttributes->underlineType ||
                                          newAttributes->strikethrough != previousAttributes->strikethrough ||
                                          newAttributes->isURL != previousAttributes->isURL ||
                                          newAttributes->drawable != previousAttributes->drawable ||
                                          !iTermCharacterAttributesUnderlineColorEqual(newAttributes, previousAttributes));
        }
        return *combinedAttributesChanged;
    } else if ((imageAttributes == nil) != (previousImageAttributes == nil)) {
        // Entering or exiting image
        *combinedAttributesChanged = YES;
        return YES;
    } else {
        // Going from image cell to image cell. Segment unless it's an adjacent image cell.
        *combinedAttributesChanged = YES;  // In theory an image cell should never repeat, so shortcut comparison.
        return ![self imageAttributes:imageAttributes followImageAttributes:previousImageAttributes];
    }
}

- (BOOL)imageAttributes:(NSDictionary *)imageAttributes
  followImageAttributes:(NSDictionary *)previousImageAttributes {
    if (![previousImageAttributes[iTermImageCodeAttribute] isEqual:imageAttributes[iTermImageCodeAttribute]]) {
        return NO;
    }
    if (![previousImageAttributes[iTermImageLineAttribute] isEqual:imageAttributes[iTermImageLineAttribute]]) {
        return NO;
    }
    if ((([previousImageAttributes[iTermImageColumnAttribute] integerValue] + 1) & 0xff) != ([imageAttributes[iTermImageColumnAttribute] integerValue] & 0xff)) {
        return NO;
    }

    return YES;
}

- (void)getAttributesForCharacter:(screen_char_t *)c
               externalAttributes:(iTermExternalAttribute *)ea
                          atIndex:(NSInteger)i
                   forceTextColor:(NSColor *)forceTextColor
                   forceUnderline:(BOOL)inUnderlinedRange
                         colorRun:(iTermBackgroundColorRun *)colorRun
                         drawable:(BOOL)drawable
                 textColorContext:(iTermTextColorContext *)textColorContext
                       attributes:(iTermCharacterAttributes *)attributes
                         remapped:(UTF32Char *)remapped {
    attributes->initialized = YES;
    attributes->shouldAntiAlias = iTermTextDrawingHelperShouldAntiAlias(c,
                                                                        _useNonAsciiFont,
                                                                        _asciiAntiAlias,
                                                                        _nonAsciiAntiAlias,
                                                                        _isRetina,
                                                                        _forceAntialiasingOnRetina);
    const BOOL isComplex = c->complexChar;
    const unichar code = c->code;

    attributes->boxDrawing = !isComplex && [[iTermBoxDrawingBezierCurveFactory boxDrawingCharactersWithBezierPathsIncludingPowerline:_useNativePowerlineGlyphs] characterIsMember:code];

    if (forceTextColor) {
        attributes->foregroundColor = forceTextColor;
    } else {
        attributes->foregroundColor = iTermTextDrawingHelperGetTextColor(self,
                                                                         c,
                                                                         inUnderlinedRange,
                                                                         i,
                                                                         textColorContext,
                                                                         colorRun,
                                                                         attributes->boxDrawing);
    }

    attributes->bold = c->bold;
    attributes->faint = c->faint;
    attributes->fakeBold = c->bold;  // default value
    attributes->fakeItalic = c->italic;  // default value
    PTYFontInfo *fontInfo = [_fontProvider fontForCharacter:isComplex ? [CharToStr(code, isComplex) longCharacterAtIndex:0] : code
                                                useBoldFont:_boldAllowed
                                              useItalicFont:_italicAllowed
                                                 renderBold:&attributes->fakeBold
                                               renderItalic:&attributes->fakeItalic
                                                   remapped:remapped];

    attributes->font = fontInfo.font;
    attributes->ligatureLevel = fontInfo.ligatureLevel;
    if (_preferSpeedToFullLigatureSupport) {
        if (!c->complexChar &&
            iTermCharacterSupportsFastPath(c->code, _asciiLigaturesAvailable)) {
            attributes->ligatureLevel = 0;
        }
        if (c->complexChar || c->code > 128) {
            if (!_nonAsciiLigatures) {
                attributes->ligatureLevel = 0;
            }
        }
    }
    if (c->underline) {
        switch (c->underlineStyle) {
            case VT100UnderlineStyleSingle:
                attributes->underlineType = iTermCharacterAttributesUnderlineRegular;
                break;
            case VT100UnderlineStyleCurly:
                attributes->underlineType = iTermCharacterAttributesUnderlineCurly;
                break;
            case VT100UnderlineStyleDouble:
                attributes->underlineType = iTermCharacterAttributesUnderlineDouble;
                break;
        }
    } else if (inUnderlinedRange) {
        attributes->underlineType = iTermCharacterAttributesUnderlineRegular;
    } else {
        attributes->underlineType = iTermCharacterAttributesUnderlineNone;
    }
    attributes->strikethrough = c->strikethrough;
    attributes->drawable = drawable;
    if (ea) {
        attributes->hasUnderlineColor = ea.hasUnderlineColor;
        attributes->underlineColor = ea.underlineColor;
        attributes->isURL = (ea.urlCode != 0);
    } else {
        attributes->hasUnderlineColor = NO;
        attributes->isURL = NO;
        memset(&attributes->underlineColor, 0, sizeof(attributes->underlineColor));
    }
}

- (NSDictionary *)dictionaryForCharacterAttributes:(iTermCharacterAttributes *)attributes {
    NSUnderlineStyle underlineStyle = NSUnderlineStyleNone;
    switch (attributes->underlineType) {
        case iTermCharacterAttributesUnderlineNone:
            if (attributes->isURL) {
                underlineStyle = NSUnderlinePatternDash;
            }
            break;
        case iTermCharacterAttributesUnderlineDouble:
            if (attributes->isURL) {
                underlineStyle = NSUnderlineStylePatternDot;  // Mixed solid/underline isn't an option, so repurpose this.
            } else {
                underlineStyle = NSUnderlineStyleDouble;
            }
            break;
        case iTermCharacterAttributesUnderlineRegular:
            if (attributes->isURL) {
                underlineStyle = NSUnderlineStylePatternDot;  // Mixed solid/underline isn't an option, so repurpose this.
            } else {
                underlineStyle = NSUnderlineStyleSingle;
            }
            break;
        case iTermCharacterAttributesUnderlineCurly:
            if (attributes->isURL) {
                underlineStyle = NSUnderlineStylePatternDot;  // Mixed solid/underline isn't an option, so repurpose this.
            } else {
                underlineStyle = NSUnderlineStyleThick;  // Curly isn't an option, so repurpose this.
            }
            break;
    }
    NSUnderlineStyle strikethroughStyle = NSUnderlineStyleNone;
    if (attributes->strikethrough) {
        strikethroughStyle = NSUnderlineStyleSingle;
    }
    static NSMutableParagraphStyle *paragraphStyle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        paragraphStyle.lineBreakMode = NSLineBreakByClipping;
        paragraphStyle.tabStops = @[];
        paragraphStyle.baseWritingDirection = NSWritingDirectionLeftToRight;
    });
    return @{ (NSString *)kCTLigatureAttributeName: @(attributes->ligatureLevel),
              (NSString *)kCTForegroundColorAttributeName: (id)[attributes->foregroundColor CGColor],
              NSFontAttributeName: attributes->font,
              iTermAntiAliasAttribute: @(attributes->shouldAntiAlias),
              iTermIsBoxDrawingAttribute: @(attributes->boxDrawing),
              iTermFakeBoldAttribute: @(attributes->fakeBold),
              iTermBoldAttribute: @(attributes->bold),
              iTermFaintAttribute: @(attributes->faint),
              iTermFakeItalicAttribute: @(attributes->fakeItalic),
              iTermHasUnderlineColorAttribute: @(attributes->hasUnderlineColor),
              iTermUnderlineColorAttribute: @[ @(attributes->underlineColor.red),
                                               @(attributes->underlineColor.green),
                                               @(attributes->underlineColor.blue),
                                               @(attributes->underlineColor.mode) ],
              NSUnderlineStyleAttributeName: @(underlineStyle),
              NSStrikethroughStyleAttributeName: @(strikethroughStyle),
              NSParagraphStyleAttributeName: paragraphStyle };
}

- (NSDictionary *)imageAttributesForCharacter:(screen_char_t *)c displayColumn:(int)displayColumn {
    if (c->image) {
        return @{ iTermImageCodeAttribute: @(c->code),
                  iTermImageColumnAttribute: @(c->foregroundColor),
                  iTermImageLineAttribute: @(c->backgroundColor),
                  iTermImageDisplayColumnAttribute: @(displayColumn) };
    } else {
        return nil;
    }
}

- (BOOL)character:(const screen_char_t *)c
withExtendedAttributes:(iTermExternalAttribute *)ea1
isEquivalentToCharacter:(const screen_char_t *)pc
withExtendedAttributes:(iTermExternalAttribute *)ea2 {
    if (c->complexChar != pc->complexChar) {
        return NO;
    }
    if (!c->complexChar) {
        if (_useNonAsciiFont) {
            BOOL ascii = c->code < 128;
            BOOL pcAscii = pc->code < 128;
            if (ascii != pcAscii) {
                return NO;
            }
        }
        if (iTermCharacterSupportsFastPath(c->code, _asciiLigaturesAvailable) != iTermCharacterSupportsFastPath(pc->code, _asciiLigaturesAvailable)) {
            return NO;
        }

        static NSCharacterSet *boxSet;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            boxSet = [iTermBoxDrawingBezierCurveFactory boxDrawingCharactersWithBezierPathsIncludingPowerline:_useNativePowerlineGlyphs];
        });
        BOOL box = [boxSet characterIsMember:c->code];
        BOOL pcBox = [boxSet characterIsMember:pc->code];
        if (box != pcBox) {
            return NO;
        }
    }
    if (!ScreenCharacterAttributesEqual(*c, *pc)) {
        return NO;
    }
    if ([_fontTable haveSpecialExceptionFor:*c orCharacter:*pc]) {
        return NO;
    }
    if (ea1 == nil && ea2 == nil) {
        // fast path
        return YES;
    }

    if (ea1 != nil) {
        return NO;
    }

    return [ea1 isEqualToExternalAttribute:ea2];
}

- (BOOL)zippy {
    return (!(_asciiLigaturesAvailable && _asciiLigatures) &&
            !(_nonAsciiLigatures) &&
            [iTermAdvancedSettingsModel zippyTextDrawing]);
}

- (NSArray<id<iTermAttributedString>> *)attributedStringsForLine:(const screen_char_t *)line
                                              externalAttributes:(id<iTermExternalAttributeIndexReading>)eaIndex
                                                           range:(NSRange)indexRange
                                                 hasSelectedText:(BOOL)hasSelectedText
                                                 backgroundColor:(NSColor *)backgroundColor
                                                  forceTextColor:(NSColor *)forceTextColor
                                                        colorRun:(iTermBackgroundColorRun *)colorRun
                                                     findMatches:(NSData *)findMatches
                                                 underlinedRange:(NSRange)underlinedRange
                                                       positions:(CTVector(CGFloat) *)positions {
    NSMutableArray<id<iTermAttributedString>> *attributedStrings = [NSMutableArray array];
    iTermColorMap *colorMap = self.colorMap;
    iTermTextColorContext textColorContext = {
        .lastUnprocessedColor = nil,
        .dimmingAmount = colorMap.dimmingAmount,
        .mutingAmount = colorMap.mutingAmount,
        .hasSelectedText = hasSelectedText,
        .colorMap = self.colorMap,
        .delegate = _delegate,
        .findMatches = findMatches,
        .reverseVideo = _reverseVideo,
        .havePreviousCharacterAttributes = NO,
        .backgroundColor = backgroundColor,
        .minimumContrast = _minimumContrast,
        .previousForegroundColor = nil,
    };
    NSDictionary *previousImageAttributes = nil;
    iTermMutableAttributedStringBuilder *builder = [[iTermMutableAttributedStringBuilder alloc] init];
    builder.zippy = self.zippy;
    builder.asciiLigaturesAvailable = _asciiLigaturesAvailable && _asciiLigatures;
    iTermCharacterAttributes characterAttributes = { 0 };
    iTermCharacterAttributes previousCharacterAttributes = { 0 };
    int segmentLength = 0;
    BOOL previousDrawable = YES;
    screen_char_t predecessor = { 0 };
    BOOL lastCharacterImpartsEmojiPresentation = NO;
    iTermExternalAttribute *prevEa = nil;

    // Only defined if not preferring speed to full ligature support.
    BOOL lastWasNull = NO;
    NSCharacterSet *emojiWithDefaultTextPresentation = [NSCharacterSet emojiWithDefaultTextPresentation];
    NSCharacterSet *emojiWithDefaultEmojiPresentationCharacterSet = [NSCharacterSet emojiWithDefaultEmojiPresentation];
    for (int i = indexRange.location; i < NSMaxRange(indexRange); i++) {
        iTermPreciseTimerStatsStartTimer(&_stats[TIMER_ATTRS_FOR_CHAR]);
        screen_char_t c = line[i];
        if (!_preferSpeedToFullLigatureSupport) {
            if (c.code == 0) {
                if (!lastWasNull) {
                    c.code = ' ';
                }
                lastWasNull = YES;
            } else {
                lastWasNull = NO;
            }
        }
        unichar code = c.code;
        BOOL isComplex = c.complexChar;

        NSString *charAsString;

        if (isComplex) {
            charAsString = ComplexCharToStr(code);

            if (i > indexRange.location &&
                builder.length > 0 &&
                !(!predecessor.complexChar && predecessor.code < 128) &&
                ComplexCharCodeIsSpacingCombiningMark(code)) {
                // Spacing combining marks get their own cell but get drawn together with their base
                // character which is assumed to be in the preceding cell so they combine properly.
                // This does not apply to ASCII characters, since they can never combine with a
                // spacing combining mark. That's done for performance in the GPU renderer to avoid
                // complicating its ASCII fastpath.
                [builder appendString:charAsString];
                const CGFloat lastValue = CTVectorGet(positions, CTVectorCount(positions) - 1);
                for (int i = 0; i < charAsString.length; i++) {
                    CTVectorAppend(positions, lastValue);
                }
                continue;
            }
            const UTF32Char base = [charAsString firstCharacter];
            if (lastCharacterImpartsEmojiPresentation && [emojiWithDefaultTextPresentation longCharacterIsMember:base] && ![charAsString containsString:@"\ufe0f"]) {
                // Prevent previous character's emoji presentation from making this one have an emoji presentation as well.
                // Leave lastCharacterImpartsEmojiPresentation set to YES intentionally.
                charAsString = [charAsString stringByAppendingString:@"\ufe0e"];
            } else {
                lastCharacterImpartsEmojiPresentation = [emojiWithDefaultEmojiPresentationCharacterSet longCharacterIsMember:base];
            }
        } else if (!c.image) {
            charAsString = nil;
            if (lastCharacterImpartsEmojiPresentation && [emojiWithDefaultTextPresentation characterIsMember:code]) {
                unichar chars[2] = { code, 0xfe0e };
                // Prevent previous character's emoji presentation from making this one have an emoji presentation as well.
                // See issue 9185
                charAsString = [NSString stringWithCharacters:chars length:2];
            } else if (code != DWC_RIGHT && code >= iTermMinimumDefaultEmojiPresentationCodePoint) {  // filter out small values for speed
                lastCharacterImpartsEmojiPresentation = [emojiWithDefaultEmojiPresentationCharacterSet characterIsMember:code];
            }
        } else {
            charAsString = nil;
        }

        iTermExternalAttribute *ea = eaIndex[i];
        const BOOL drawable = iTermTextDrawingHelperIsCharacterDrawable(&c,
                                                                        i > indexRange.location ? &predecessor : NULL,
                                                                        charAsString != nil,
                                                                        _blinkingItemsVisible,
                                                                        _blinkAllowed,
                                                                        _preferSpeedToFullLigatureSupport,
                                                                        ea.urlCode);
        predecessor = c;
        if (!drawable) {
            if ((characterAttributes.drawable && ScreenCharIsDWC_RIGHT(c)) ||
                (i > indexRange.location && !memcmp(&c, &line[i - 1], sizeof(c)))) {
                // This optimization short-circuits long runs of terminal nulls.
                ++segmentLength;
                characterAttributes.drawable = NO;
                continue;
            }
        }

        if (likely(underlinedRange.length == 0) &&
            likely(drawable == previousDrawable) &&
            likely(i > indexRange.location) &&
            [self character:&c withExtendedAttributes:ea isEquivalentToCharacter:&line[i-1] withExtendedAttributes:prevEa]) {
            ++segmentLength;
            iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_ATTRS_FOR_CHAR]);
            if (drawable ||
                ((characterAttributes.underlineType ||
                  characterAttributes.strikethrough ||
                  characterAttributes.isURL) && segmentLength == 1)) {
                [self updateBuilder:builder
                         withString:drawable ? charAsString : @" "
                        orCharacter:code
                          positions:positions
                             offset:(i - indexRange.location) * _cellSize.width];
            }
            continue;
        }
        previousDrawable = drawable;

        UTF32Char remapped = 0;
        [self getAttributesForCharacter:&c
                     externalAttributes:ea
                                atIndex:i
                         forceTextColor:forceTextColor
                         forceUnderline:NSLocationInRange(i, underlinedRange)
                               colorRun:colorRun
                               drawable:drawable
                       textColorContext:&textColorContext
                             attributes:&characterAttributes
                               remapped:&remapped];
        prevEa = ea;
        if (!c.image && remapped) {
            if (c.complexChar) {
                charAsString = [charAsString stringByReplacingBaseCharacterWith:remapped];
            } else if (remapped <= 0xffff) {
                code = remapped;
            } else {
                charAsString = [NSString stringWithLongCharacter:remapped];
            }
        }
        iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_ATTRS_FOR_CHAR]);

        iTermPreciseTimerStatsStartTimer(&_stats[TIMER_SHOULD_SEGMENT]);

        NSDictionary *imageAttributes = [self imageAttributesForCharacter:&c displayColumn:i];
        BOOL combinedAttributesChanged = NO;

        // I tried segmenting when fastpath eligibility changes so we can use the fast path as much
        // as possible. In the vimdiff benchmark it was neutral, and in the spam.cc benchmark it was
        // hugely negative (66->210 ms). The failed change was to segment when this is true:
        // builder.canUseFastPath != (!c.complexChar && iTermCharacterSupportsFastPath(code, _asciiLigaturesAvailable))
        if ([self shouldSegmentWithAttributes:&characterAttributes
                              imageAttributes:imageAttributes
                           previousAttributes:&previousCharacterAttributes
                      previousImageAttributes:previousImageAttributes
                     combinedAttributesChanged:&combinedAttributesChanged]) {
            iTermPreciseTimerStatsStartTimer(&_stats[TIMER_STAT_BUILD_MUTABLE_ATTRIBUTED_STRING]);
            id<iTermAttributedString> builtString = builder.attributedString;
            if (previousCharacterAttributes.underlineType ||
                previousCharacterAttributes.strikethrough ||
                previousCharacterAttributes.isURL) {
                [builtString addAttribute:iTermUnderlineLengthAttribute
                                    value:@(segmentLength)];
            }
            segmentLength = 0;
            iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_STAT_BUILD_MUTABLE_ATTRIBUTED_STRING]);

            if (builtString.length > 0) {
                [attributedStrings addObject:builtString];
            }
            builder = [[iTermMutableAttributedStringBuilder alloc] init];
            builder.zippy = self.zippy;
            builder.asciiLigaturesAvailable = _asciiLigaturesAvailable && _asciiLigatures;
        }
        ++segmentLength;
        previousCharacterAttributes = characterAttributes;
        previousImageAttributes = [imageAttributes copy];
        iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_SHOULD_SEGMENT]);

        iTermPreciseTimerStatsStartTimer(&_stats[TIMER_COMBINE_ATTRIBUTES]);
        if (combinedAttributesChanged) {
            NSDictionary *combinedAttributes = [self dictionaryForCharacterAttributes:&characterAttributes];
            if (imageAttributes) {
                combinedAttributes = [combinedAttributes dictionaryByMergingDictionary:imageAttributes];
            }
            [builder setAttributes:combinedAttributes];
            if ([[NSFont castFrom:combinedAttributes[NSFontAttributeName]] it_hasStylisticAlternatives]) {
                // CG APIs don't support these so we must use slow core text.
                [builder disableFastPath];
            }
        }
        iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_COMBINE_ATTRIBUTES]);

        if (drawable || ((characterAttributes.underlineType ||
                          characterAttributes.strikethrough ||
                          characterAttributes.isURL) && segmentLength == 1)) {
            // Use " " when not drawable to prevent 0-length attributed strings when an underline/strikethrough is
            // present. If we get here's because there's an underline/strikethrough (which isn't quite obvious
            // from the if statement's condition).
            [self updateBuilder:builder
                     withString:drawable ? charAsString : @" "
                    orCharacter:code
                      positions:positions
                         offset:(i - indexRange.location) * _cellSize.width];
        }
    }
    if (builder.length) {
        iTermPreciseTimerStatsStartTimer(&_stats[TIMER_STAT_BUILD_MUTABLE_ATTRIBUTED_STRING]);
        id<iTermAttributedString> builtString = builder.attributedString;
        if (previousCharacterAttributes.underlineType ||
            previousCharacterAttributes.strikethrough ||
            previousCharacterAttributes.isURL) {
            [builtString addAttribute:iTermUnderlineLengthAttribute
                                            value:@(segmentLength)];
        }
        iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_STAT_BUILD_MUTABLE_ATTRIBUTED_STRING]);

        if (builtString.length > 0) {
            [attributedStrings addObject:builtString];
        }
    }

    return attributedStrings;
}

- (void)updateBuilder:(iTermMutableAttributedStringBuilder *)builder
           withString:(NSString *)string
          orCharacter:(unichar)code
            positions:(CTVector(CGFloat) *)positions
               offset:(CGFloat)offset {
    iTermPreciseTimerStatsStartTimer(&_stats[TIMER_UPDATE_BUILDER]);
    NSUInteger length;
    if (string) {
        [builder appendString:string];
        length = string.length;
    } else {
        [builder appendCharacter:code];
        length = 1;
    }
    iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_UPDATE_BUILDER]);

    iTermPreciseTimerStatsStartTimer(&_stats[TIMER_ADVANCES]);
    // Append to positions.
    for (NSUInteger j = 0; j < length; j++) {
        CTVectorAppend(positions, offset);
    }
    iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_ADVANCES]);
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
    return [iTermTextDrawingHelper offscreenCommandLineFrameForVisibleRect:_visibleRect
                                                                  cellSize:_cellSize
                                                                  gridSize:_gridSize];
}

- (NSColor *)offscreenCommandLineBackgroundColor {
    if (!self.offscreenCommandLine) {
        return nil;
    }
    if ([[self defaultBackgroundColor] isDark]) {
        return [[self defaultBackgroundColor] it_colorByDimmingByAmount:0.7];
    } else {
        return [[self defaultBackgroundColor] it_colorByDimmingByAmount:0.1];
    }
}

- (NSColor *)offscreenCommandLineOutlineColor {
    if (!self.offscreenCommandLine) {
        return nil;
    }
    return [[self defaultTextColor] it_colorByDimmingByAmount:0.95];
}

- (void)drawOffscreenCommandLineWithVirtualOffset:(CGFloat)virtualOffset {
    if (!_offscreenCommandLine) {
        return;
    }
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    [self drawOffscreenCommandLineDecorationsInContext:ctx
                                         virtualOffset:virtualOffset];

    BOOL blink = NO;
    const int row = [self rangeOfVisibleRows].location;
    iTermBackgroundColorRunsInLine *backgroundRuns =
    [iTermBackgroundColorRunsInLine backgroundRunsInLine:_offscreenCommandLine.characters.line
                                              lineLength:_gridSize.width
                                                     row:row
                                         selectedIndexes:[NSIndexSet indexSet]
                                             withinRange:NSMakeRange(0, _gridSize.width)
                                                 matches:nil
                                                anyBlink:&blink
                                                       y:row * _cellSize.height];
    
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
    outline.origin.x = 1;
    outline.size.width = _visibleRect.size.width - 2;

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
                            self.softAlternateScreenMode);
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
                           externalAttributes:nil
                                          row:y
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

- (NSRect)frameForCursorAt:(VT100GridCoord)cursorCoord {
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

- (NSRect)cursorFrame {
    return [self frameForCursorAt:_cursorCoord];
}

- (void)drawCopyModeCursorWithBackgroundColor:(NSColor *)cursorBackgroundColor
                                virtualOffset:(CGFloat)virtualOffset {
    iTermCursor *cursor = [iTermCursor itermCopyModeCursorInSelectionState:self.copyModeSelecting];
    cursor.delegate = self;

    [self reallyDrawCursor:cursor
           backgroundColor:cursorBackgroundColor
                        at:VT100GridCoordMake(_copyModeCursorCoord.x, _copyModeCursorCoord.y - _numberOfScrollbackLines)
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

- (NSRect)reallyDrawCursor:(iTermCursor *)cursor
           backgroundColor:(NSColor *)backgroundColor
                        at:(VT100GridCoord)cursorCoord
                   outline:(BOOL)outline
             virtualOffset:(CGFloat)virtualOffset {
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
    NSColor *cursorColor;
    if (outline) {
        cursorColor = [_colorMap colorForKey:kColorMapBackground];
    } else {
        cursorColor = [self backgroundColorForCursor];
    }
    NSRect rect = [self frameForCursorAt:cursorCoord];
    if (isDoubleWidth) {
        rect.size.width *= 2;
    }

    if (_passwordInput) {
        NSImage *keyImage;
        if (backgroundColor.isDark) {
            keyImage = [NSImage it_imageNamed:@"key-light" forClass:self.class];
        } else {
            keyImage = [NSImage it_imageNamed:@"key-dark" forClass:self.class];
        }
        CGPoint point = rect.origin;
        [keyImage it_drawInRect:NSMakeRect(point.x, point.y, _cellSize.width, _cellSize.height)
                       fromRect:NSZeroRect
                      operation:NSCompositingOperationSourceOver
                       fraction:1
                 respectFlipped:YES
                          hints:nil
                  virtualOffset:virtualOffset];
        return rect;
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
    [cursor drawWithRect:rect
             doubleWidth:isDoubleWidth
              screenChar:screenChar
         backgroundColor:cursorColor
         foregroundColor:cursorTextColor
                   smart:_useSmartCursorColor
                 focused:((_isInKeyWindow && _textViewIsActiveSession) || _shouldDrawFilledInCursor)
                   coord:cursorCoord
                 outline:outline
           virtualOffset:virtualOffset];
    return rect;
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

- (VT100GridCoordRange)coordRangeForRect:(NSRect)rect {
    return VT100GridCoordRangeMake(floor((rect.origin.x - [iTermPreferences intForKey:kPreferenceKeySideMargins]) / _cellSize.width),
                                   floor(rect.origin.y / _cellSize.height),
                                   ceil((NSMaxX(rect) - [iTermPreferences intForKey:kPreferenceKeySideMargins]) / _cellSize.width),
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
    _visibleRect = [_delegate textDrawingHelperVisibleRect];
    _scrollViewContentSize = _delegate.enclosingScrollView.contentSize;
    _scrollViewDocumentVisibleRect = _delegate.textDrawingHelperVisibleRect;
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
    id<iTermExternalAttributeIndexReading> eaIndex = [self.delegate drawingHelperExternalAttributesOnLine:row];

    [self constructAndDrawRunsForLine:line
                   externalAttributes:eaIndex
                                  row:row
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

@end
