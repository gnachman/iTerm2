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
#import "iTermAdvancedSettingsModel.h"
#import "iTermBackgroundColorRun.h"
#import "iTermBoxDrawingBezierCurveFactory.h"
#import "iTermColorMap.h"
#import "iTermController.h"
#import "iTermFindCursorView.h"
#import "iTermImageInfo.h"
#import "iTermIndicatorsHelper.h"
#import "iTermMutableAttributedStringBuilder.h"
#import "iTermPreciseTimer.h"
#import "iTermSelection.h"
#import "iTermTextExtractor.h"
#import "iTermTimestampDrawHelper.h"
#import "MovingAverage.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSStringITerm.h"
#import "PTYFontInfo.h"
#import "RegexKitLite.h"
#import "VT100ScreenMark.h"
#import "VT100Terminal.h"  // TODO: Remove this dependency

#define likely(x) __builtin_expect(!!(x), 1)
#define unlikely(x) __builtin_expect(!!(x), 0)

// I couldn't get masking to work with fastpath, so for now just use the slow path for underlined
// text (which should be rare, and hopefully renders just like the fastpath).
#define ENABLE_FASTPATH_UNDERLINES 0

static const int kBadgeMargin = 4;

extern void CGContextSetFontSmoothingStyle(CGContextRef, int);
extern int CGContextGetFontSmoothingStyle(CGContextRef);

BOOL CheckFindMatchAtIndex(NSData *findMatches, int index) {
    int theIndex = index / 8;
    int mask = 1 << (index & 7);
    const char *matchBytes = findMatches.bytes;
    return !!(theIndex < [findMatches length] && (matchBytes[theIndex] & mask));
}

@interface iTermTextDrawingHelper() <iTermCursorDelegate>
@end

// IMPORTANT: If you add a field here also update the comparison function
// shouldSegmentWithAttributes:imageAttributes:previousAttributes:previousImageAttributes:combinedAttributesChanged:
typedef struct {
    BOOL initialized;
    BOOL shouldAntiAlias;
    NSColor *foregroundColor;
    BOOL boxDrawing;
    NSFont *font;
    BOOL bold;
    BOOL fakeBold;
    BOOL fakeItalic;
    BOOL underline;
    BOOL isURL;
    NSInteger ligatureLevel;
    BOOL drawable;
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
static NSString *const iTermFakeBoldAttribute = @"iTermFakeBoldAttribute";
static NSString *const iTermFakeItalicAttribute = @"iTermFakeItalicAttribute";
static NSString *const iTermImageCodeAttribute = @"iTermImageCodeAttribute";
static NSString *const iTermImageColumnAttribute = @"iTermImageColumnAttribute";
static NSString *const iTermImageLineAttribute = @"iTermImageLineAttribute";
static NSString *const iTermImageDisplayColumnAttribute = @"iTermImageDisplayColumnAttribute";
static NSString *const iTermIsBoxDrawingAttribute = @"iTermIsBoxDrawingAttribute";
static NSString *const iTermUnderlineLengthAttribute = @"iTermUnderlineLengthAttribute";

typedef struct iTermTextColorContext {
    NSColor *lastUnprocessedColor;
    CGFloat dimmingAmount;
    CGFloat mutingAmount;
    BOOL hasSelectedText;
    iTermColorMap *colorMap;
    NSView<iTermTextDrawingHelperDelegate> *delegate;
    NSData *findMatches;
    BOOL reverseVideo;
    screen_char_t previousCharacterAttributes;
    BOOL havePreviousCharacterAttributes;
    NSColor *backgroundColor;
    NSColor *previousBackgroundColor;
    CGFloat minimumContrast;
    NSColor *previousForegroundColor;
} iTermTextColorContext;

@implementation iTermTextDrawingHelper {
    // Current font. Only valid for the duration of a single drawing context.
    NSFont *_selectedFont;

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
    NSMutableDictionary<NSAttributedString *, id> *_lineRefCache;

    // The cache we'll use next time.
    NSMutableDictionary<NSAttributedString *, id> *_replacementLineRefCache;
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
    }
    return self;
}

- (void)dealloc {
    [_selection release];
    [_cursorGuideColor release];
    [_badgeImage release];
    [_unfocusedSelectionColor release];
    [_markedText release];
    [_colorMap release];

    [_selectedFont release];

    [_missingImages release];
    [_backgroundStripesImage release];
    [_lineRefCache release];
    [_replacementLineRefCache release];
    [_timestampDrawHelper release];

    [super dealloc];
}

#pragma mark - Drawing: General

- (void)drawTextViewContentInRect:(NSRect)rect
                         rectsPtr:(const NSRect *)rectArray
                        rectCount:(NSInteger)rectCount {
    DLog(@"begin drawRect:%@ in view %@", [NSValue valueWithRect:rect], _delegate);
    iTermPreciseTimerSetEnabled(YES);

    if (_debug) {
        [[NSColor redColor] set];
        NSRectFill(rect);
    }
    [self updateCachedMetrics];
    // If there are two or more rects that need display, the OS will pass in |rect| as the smallest
    // bounding rect that contains them all. Luckily, we can get the list of the "real" dirty rects
    // and they're guaranteed to be disjoint. So draw each of them individually.
    [self startTiming];

    const int haloWidth = 4;
    NSInteger yLimit = _numberOfLines;

    VT100GridCoordRange boundingCoordRange = [self coordRangeForRect:rect];
    NSRange visibleLines = [self rangeOfVisibleRows];

    // Start at 0 because ligatures can draw incorrectly otherwise. When a font has a ligature for
    // -> and >-, then a line like ->->-> needs to start at the beginning since drawing only a
    // suffix of it could draw a >- ligature at the start of the range being drawn. Issue 5030.
    boundingCoordRange.start.x = 0;
    boundingCoordRange.start.y = MAX(MAX(0, boundingCoordRange.start.y - 1), visibleLines.location);
    boundingCoordRange.end.x = MIN(_gridSize.width, boundingCoordRange.end.x + haloWidth);
    boundingCoordRange.end.y = MIN(yLimit, boundingCoordRange.end.y + 1);

    int numRowsInRect = MAX(0, boundingCoordRange.end.y - boundingCoordRange.start.y);
    if (numRowsInRect == 0) {
        return;
    }
    NSMutableData *store = [NSMutableData dataWithLength:numRowsInRect * sizeof(NSRange)];
    NSRange *ranges = (NSRange *)store.mutableBytes;
    for (int i = 0; i < rectCount; i++) {
        VT100GridCoordRange coordRange = [self coordRangeForRect:rectArray[i]];
//        NSLog(@"Have to draw rect %@ (%@)", NSStringFromRect(rectArray[i]), VT100GridCoordRangeDescription(coordRange));
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

    [self drawRanges:ranges count:numRowsInRect
              origin:boundingCoordRange.start
        boundingRect:[self rectForCoordRange:boundingCoordRange]
        visibleLines:visibleLines];

    if (_showDropTargets) {
        [self drawDropTargets];
    }

    [self stopTiming];

    iTermPreciseTimerPeriodicLog(@"drawRect", _stats, sizeof(_stats) / sizeof(*_stats), 5, [iTermAdvancedSettingsModel logDrawingPerformance], nil);

    if (_debug) {
        NSColor *c = [NSColor colorWithCalibratedRed:(rand() % 255) / 255.0
                                               green:(rand() % 255) / 255.0
                                                blue:(rand() % 255) / 255.0
                                               alpha:1];
        [c set];
        NSFrameRect(rect);
    }

    [_selectedFont release];
    _selectedFont = nil;

    // Release cached CTLineRefs from the last set of drawings and update them with the new ones.
    // This keeps us from having too many lines cached at once.
    [_lineRefCache release];
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
      visibleLines:(NSRange)visibleLines {
    // Configure graphics
    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositingOperationCopy];

    iTermTextExtractor *extractor = [self.delegate drawingHelperTextExtractor];
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
        screen_char_t* theLine = [self.delegate drawingHelperLineAtIndex:line];
        NSIndexSet *selectedIndexes =
            [_selection selectedIndexesIncludingTabFillersInLine:line];
        iTermBackgroundColorRunsInLine *runsInLine =
            [iTermBackgroundColorRunsInLine backgroundRunsInLine:theLine
                                                      lineLength:_gridSize.width
                                                             row:line
                                                 selectedIndexes:selectedIndexes
                                                     withinRange:charRange
                                                         matches:matches
                                                        anyBlink:&_blinkingFound
                                                   textExtractor:extractor
                                                               y:y
                                                            line:line];
        [backgroundRunArrays addObject:runsInLine];
        iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_CONSTRUCT_BACKGROUND_RUNS]);
    }

    iTermPreciseTimerStatsStartTimer(&_stats[TIMER_DRAW_BACKGROUND]);
    // If a background image is in use, draw the whole rect at once.
    if (_hasBackgroundImage) {
        [self.delegate drawingHelperDrawBackgroundImageInRect:boundingRect
                                       blendDefaultBackground:NO];
    }

    // Now iterate over the lines and paint the backgrounds.
    for (NSInteger i = 0; i < backgroundRunArrays.count; ) {
        NSInteger rows = [self numberOfEquivalentBackgroundColorLinesInRunArrays:backgroundRunArrays fromIndex:i];
        iTermBackgroundColorRunsInLine *runArray = backgroundRunArrays[i];
        runArray.numberOfEquivalentRows = rows;
        [self drawBackgroundForLine:runArray.line
                                atY:runArray.y
                               runs:runArray.array
                     equivalentRows:rows];
        for (NSInteger j = i; j < i + rows; j++) {
            [self drawMarginsAndMarkForLine:backgroundRunArrays[j].line y:backgroundRunArrays[j].y];
        }
        i += rows;
    }
    iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_DRAW_BACKGROUND]);

    // Draw default background color over the line under the last drawn line so the tops of
    // characters aren't visible there. If there is an IME, that could be many lines tall.
    VT100GridCoordRange drawableCoordRange = [self drawableCoordRangeForRect:_visibleRect];
    [self drawExcessAtLine:drawableCoordRange.end.y];

    // Draw other background-like stuff that goes behind text.
    [self drawAccessoriesInRect:boundingRect];

    const BOOL drawCursorBeforeText = (_cursorType == CURSOR_UNDERLINE || _cursorType == CURSOR_VERTICAL);
    if (drawCursorBeforeText) {
        [self drawCursor:NO];
    }

    // Now iterate over the lines and paint the characters.
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    if ([self textAppearanceDependsOnBackgroundColor]) {
        [self drawForegroundForBackgroundRunArrays:backgroundRunArrays
                                               ctx:ctx];
    } else {
        [self drawUnprocessedForegroundForBackgroundRunArrays:backgroundRunArrays
                                                          ctx:ctx];
    }

    [self drawTopMargin];

    // If the IME is in use, draw its contents over top of the "real" screen
    // contents.
    [self drawInputMethodEditorTextAt:_cursorCoord.x
                                    y:_cursorCoord.y
                                width:_gridSize.width
                               height:_gridSize.height
                         cursorHeight:_cellSizeWithoutSpacing.height
                                  ctx:ctx];
    _blinkingFound |= self.cursorBlinking;
    if (drawCursorBeforeText) {
        if ([iTermAdvancedSettingsModel drawOutlineAroundCursor]) {
            [self drawCursor:YES];
        }
    } else {
        [self drawCursor:NO];
    }

    if (self.copyMode) {
        [self drawCopyModeCursor];
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
               equivalentRows:(NSInteger)rows {
    for (iTermBoxedBackgroundColorRun *box in runs) {
        iTermBackgroundColorRun *run = box.valuePointer;

//        NSLog(@"Paint background row %d range %@", line, NSStringFromRange(run->range));

        NSRect rect = NSMakeRect(floor([iTermAdvancedSettingsModel terminalMargin] + run->range.location * _cellSize.width),
                                 yOrigin,
                                 ceil(run->range.length * _cellSize.width),
                                 _cellSize.height * rows);
        NSColor *color = [self unprocessedColorForBackgroundRun:run];
        // The unprocessed color is needed for minimum contrast computation for text color.
        box.unprocessedBackgroundColor = color;
        color = [_colorMap processedBackgroundColorForBackgroundColor:color];
        box.backgroundColor = color;

        [box.backgroundColor set];
        NSRectFillUsingOperation(rect,
                                 _hasBackgroundImage ? NSCompositingOperationSourceOver : NSCompositingOperationCopy);

        if (_debug) {
            [[NSColor yellowColor] set];
            NSBezierPath *path = [NSBezierPath bezierPath];
            [path moveToPoint:rect.origin];
            [path lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
            [path stroke];
        }
    }
}

- (NSColor *)unprocessedColorForBackgroundRun:(iTermBackgroundColorRun *)run {
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
        // consistent with their seperator glyphs opacity(foreground).
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

        if (defaultBackground && _hasBackgroundImage) {
            alpha = 1 - _blend;
        }
    }

    return [color colorWithAlphaComponent:alpha];
}

- (void)drawExcessAtLine:(int)line {
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
                                   blendDefaultBackground:YES];

    if (_debug) {
        [[NSColor blueColor] set];
        NSBezierPath *path = [NSBezierPath bezierPath];
        [path moveToPoint:excessRect.origin];
        [path lineToPoint:NSMakePoint(NSMaxX(excessRect), NSMaxY(excessRect))];
        [path stroke];

        NSFrameRect(excessRect);
    }

    if (_showStripes) {
        [self drawStripesInRect:excessRect];
    }
}

- (void)drawTopMargin {
    // Draw a margin at the top of the visible area.
    NSRect topMarginRect = _visibleRect;
    topMarginRect.origin.y -=
        MAX(0, [iTermAdvancedSettingsModel terminalVMargin] - NSMinY(_delegate.enclosingScrollView.documentVisibleRect));

    topMarginRect.size.height = [iTermAdvancedSettingsModel terminalVMargin];
    [self.delegate drawingHelperDrawBackgroundImageInRect:topMarginRect
                                   blendDefaultBackground:YES];

    if (_showStripes) {
        [self drawStripesInRect:topMarginRect];
    }
}

- (void)drawMarginsAndMarkForLine:(int)line y:(CGFloat)y {
    NSRect leftMargin = NSMakeRect(0, y, MAX(0, [iTermAdvancedSettingsModel terminalMargin]), _cellSize.height);
    NSRect rightMargin;
    NSRect visibleRect = _visibleRect;
    rightMargin.origin.x = _cellSize.width * _gridSize.width + [iTermAdvancedSettingsModel terminalMargin];
    rightMargin.origin.y = y;
    rightMargin.size.width = visibleRect.size.width - rightMargin.origin.x;
    rightMargin.size.height = _cellSize.height;

    // Draw background in margins
    [self.delegate drawingHelperDrawBackgroundImageInRect:leftMargin
                                   blendDefaultBackground:YES];
    [self.delegate drawingHelperDrawBackgroundImageInRect:rightMargin
                                   blendDefaultBackground:YES];

    [self drawMarkIfNeededOnLine:line leftMarginRect:leftMargin];
}

- (void)drawStripesInRect:(NSRect)rect {
    if (!_backgroundStripesImage) {
        _backgroundStripesImage = [[NSImage imageNamed:@"BackgroundStripes"] retain];
    }
    NSColor *color = [NSColor colorWithPatternImage:_backgroundStripesImage];
    [color set];

    [NSGraphicsContext saveGraphicsState];
    [[NSGraphicsContext currentContext] setPatternPhase:NSMakePoint(0, 0)];
    NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
    [NSGraphicsContext restoreGraphicsState];
}

#pragma mark - Drawing: Accessories

- (void)drawAccessoriesInRect:(NSRect)bgRect {
    VT100GridCoordRange coordRange = [self coordRangeForRect:bgRect];
    [self drawBadgeInRect:bgRect];

    // Draw red stripes in the background if sending input to all sessions
    if (_showStripes) {
        [self drawStripesInRect:bgRect];
    }

    // Highlight cursor line if the cursor is on this line and it's on.
    int cursorLine = _cursorCoord.y + _numberOfScrollbackLines;
    const BOOL drawCursorGuide = (self.highlightCursorLine &&
                                  cursorLine >= coordRange.start.y &&
                                  cursorLine < coordRange.end.y);
    if (drawCursorGuide) {
        CGFloat y = cursorLine * _cellSize.height;
        [self drawCursorGuideForColumns:NSMakeRange(coordRange.start.x,
                                                    coordRange.end.x - coordRange.start.x)
                                      y:y];
    }
}

- (void)drawCursorGuideForColumns:(NSRange)range y:(CGFloat)yOrigin {
    if (!_cursorVisible) {
        return;
    }
    [_cursorGuideColor set];
    NSPoint textOrigin = NSMakePoint([iTermAdvancedSettingsModel terminalMargin] + range.location * _cellSize.width, yOrigin);
    NSRect rect = NSMakeRect(textOrigin.x,
                             textOrigin.y,
                             range.length * _cellSize.width,
                             _cellSize.height);
    NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);

    rect.size.height = 1;
    NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);

    rect.origin.y += _cellSize.height - 1;
    NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
}

+ (NSRect)frameForMarkContainedInRect:(NSRect)container
                             cellSize:(CGSize)cellSize
               cellSizeWithoutSpacing:(CGSize)cellSizeWithoutSpacing
                                scale:(CGFloat)scale {
    const CGFloat verticalSpacing = MAX(0, scale * round((cellSize.height / scale - cellSizeWithoutSpacing.height / scale) / 2.0));
    CGRect rect = NSMakeRect(container.origin.x,
                             container.origin.y + verticalSpacing,
                             container.size.width,
                             cellSizeWithoutSpacing.height);
    const CGFloat kMaxHeight = 15 * scale;
    const CGFloat kMinMargin = 3 * scale;
    const CGFloat kMargin = MAX(kMinMargin, (cellSizeWithoutSpacing.height - kMaxHeight) / 2.0);

    const CGFloat overage = rect.size.width - rect.size.height + 2 * kMargin;
    if (overage > 0) {
        rect.origin.x += overage * .7;
        rect.size.width -= overage;
    }

    rect.origin.y += kMargin;
    rect.size.height -= kMargin;

    // Bump the bottom up by as much as 3 points.
    rect.size.height -= MAX(3 * scale, (cellSizeWithoutSpacing.height - 15 * scale) / 2.0);

    return rect;
}

+ (NSColor *)successMarkColor {
    return [NSColor colorWithSRGBRed:0.53846
                               green:0.757301
                                blue:1
                               alpha:1];
}

+ (NSColor *)errorMarkColor {
    return [NSColor colorWithSRGBRed:0.987265
                               green:0.447845
                                blue:0.426244
                               alpha:1];
}

+ (NSColor *)otherMarkColor {
    return [NSColor colorWithSRGBRed:0.856645
                               green:0.847289
                                blue:0.425771
                               alpha:1];
}

- (void)drawMarkIfNeededOnLine:(int)line leftMarginRect:(NSRect)leftMargin {
    VT100ScreenMark *mark = [self.delegate drawingHelperMarkOnLine:line];
    if (mark.isVisible && self.drawMarkIndicators) {
        NSRect insetLeftMargin = leftMargin;
        insetLeftMargin.origin.x += 1;
        insetLeftMargin.size.width -= 1;
        NSRect rect = [iTermTextDrawingHelper frameForMarkContainedInRect:insetLeftMargin
                                                                 cellSize:_cellSize
                                                   cellSizeWithoutSpacing:_cellSizeWithoutSpacing
                                                                    scale:1];
        const CGFloat minX = round(NSMinX(rect));
        NSPoint top = NSMakePoint(minX, NSMinY(rect));
        NSPoint right = NSMakePoint(minX + NSWidth(rect), NSMidY(rect) - 0.25);
        NSPoint bottom = NSMakePoint(minX, NSMaxY(rect) - 0.5);


        [[NSColor blackColor] set];
        NSBezierPath *path = [NSBezierPath bezierPath];
        [path moveToPoint:NSMakePoint(bottom.x, bottom.y)];
        [path lineToPoint:NSMakePoint(right.x, right.y)];
        [path setLineWidth:1.0];
        [path stroke];

        NSColor *color = nil;
        if (mark.code == 0) {
            // Success
            color = [iTermTextDrawingHelper successMarkColor];
        } else if ([iTermAdvancedSettingsModel showYellowMarkForJobStoppedBySignal] &&
                   mark.code >= 128 && mark.code <= 128 + 32) {
            // Stopped by a signal (or an error, but we can't tell which)
            color = [iTermTextDrawingHelper otherMarkColor];
        } else {
            // Failure
            color = [iTermTextDrawingHelper errorMarkColor];
        }

        if (leftMargin.size.width == 1) {
            NSRect rect = NSInsetRect(leftMargin, 0, leftMargin.size.height * 0.25);
            [[color colorWithAlphaComponent:0.75] set];
            NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
        } else {
            [color set];
            [path moveToPoint:top];
            [path lineToPoint:right];
            [path lineToPoint:bottom];
            [path lineToPoint:top];
            [path fill];
        }
    }
}

- (void)drawNoteRangesOnLine:(int)line {
    NSArray *noteRanges = [self.delegate drawingHelperCharactersWithNotesOnLine:line];
    if (noteRanges.count) {
        for (NSValue *value in noteRanges) {
            VT100GridRange range = [value gridRangeValue];
            CGFloat x = range.location * _cellSize.width + [iTermAdvancedSettingsModel terminalMargin];
            CGFloat y = line * _cellSize.height;
            [[NSColor yellowColor] set];

            CGFloat maxX = MIN(_frame.size.width - [iTermAdvancedSettingsModel terminalMargin], range.length * _cellSize.width + x);
            CGFloat w = maxX - x;
            NSRectFill(NSMakeRect(x, y + _cellSize.height - 1.5, w, 1));
            [[NSColor orangeColor] set];
            NSRectFill(NSMakeRect(x, y + _cellSize.height - 1, w, 1));
        }

    }
}

- (void)createTimestampDrawingHelper {
    [_timestampDrawHelper autorelease];
    _timestampDrawHelper =
        [[iTermTimestampDrawHelper alloc] initWithBackgroundColor:[self defaultBackgroundColor]
                                                        textColor:[_colorMap colorForKey:kColorMapForeground]
                                                              now:self.now
                                               useTestingTimezone:self.useTestingTimezone
                                                        rowHeight:_cellSize.height
                                                           retina:self.isRetina];

}

- (void)drawTimestamps {
    if (!self.showTimestamps) {
        return;
    }

    [self updateCachedMetrics];

    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    if (!self.isRetina) {
        CGContextSetShouldSmoothFonts(ctx, NO);
    }
    // Note: for the foreground color, we don't use the dimmed version because it looks bad on
    // nonretina displays. That's why I go to the colormap instead of using -defaultForegroundColor.
    for (int y = _scrollViewDocumentVisibleRect.origin.y / _cellSize.height;
         y < NSMaxY(_scrollViewDocumentVisibleRect) / _cellSize.height && y < _numberOfLines;
         y++) {
        [_timestampDrawHelper setDate:[_delegate drawingHelperTimestampForLine:y] forLine:y];
    }
    [_timestampDrawHelper drawInContext:[NSGraphicsContext currentContext] frame:_frame];
    if (!self.isRetina) {
        CGContextSetShouldSmoothFonts(ctx, YES);
    }
}

+ (NSRect)rectForBadgeImageOfSize:(NSSize)imageSize
                  destinationRect:(NSRect)rect
             destinationFrameSize:(NSSize)textViewSize
                      visibleSize:(NSSize)visibleSize
                    sourceRectPtr:(NSRect *)sourceRectPtr {
    if (NSEqualSizes(NSZeroSize, imageSize)) {
        return NSZeroRect;
    }
    NSRect destination = NSMakeRect(textViewSize.width - imageSize.width - [iTermAdvancedSettingsModel badgeRightMargin],
                                    textViewSize.height - visibleSize.height + kiTermIndicatorStandardHeight + [iTermAdvancedSettingsModel badgeTopMargin],
                                    imageSize.width,
                                    imageSize.height);
    NSRect intersection = NSIntersectionRect(rect, destination);
    if (intersection.size.width == 0 || intersection.size.height == 1) {
        return NSZeroRect;
    }
    NSRect source = intersection;
    source.origin.x -= destination.origin.x;
    source.origin.y -= destination.origin.y;
    source.origin.y = imageSize.height - (source.origin.y + source.size.height);
    *sourceRectPtr = source;
    return intersection;
}

- (NSSize)drawBadgeInRect:(NSRect)rect {
    NSRect source;
    NSRect intersection = [iTermTextDrawingHelper rectForBadgeImageOfSize:_badgeImage.size
                                                          destinationRect:rect
                                                     destinationFrameSize:_frame.size
                                                              visibleSize:_scrollViewDocumentVisibleRect.size
                                                            sourceRectPtr:&source];
    if (NSEqualSizes(NSZeroSize, intersection.size)) {
        return NSZeroSize;
    }
    [_badgeImage drawInRect:intersection
                   fromRect:source
                  operation:NSCompositingOperationSourceOver
                   fraction:1
             respectFlipped:YES
                      hints:nil];

    NSSize imageSize = _badgeImage.size;
    imageSize.width += kBadgeMargin + [iTermAdvancedSettingsModel badgeRightMargin];

    return imageSize;
}

#pragma mark - Drawing: Drop targets

- (void)drawDropTargets {
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
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);

        [borderColor set];
        NSFrameRect(rect);

        [label drawInRect:rect withAttributes:[label attributesUsingFont:[NSFont boldSystemFontOfSize:8]
                                                             fittingSize:rect.size
                                                              attributes:attributes]];
    }];
}

- (void)enumerateDropTargets:(void (^)(NSString *, NSRange))block {
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
                                                    ctx:(CGContextRef)ctx {
    // Combine runs on each line, except those with different values of
    // `selected` or `match`. Those properties affect foreground color and must
    // split ligatures up.
    NSArray<iTermBackgroundColorRunsInLine *> *fakeRunArrays = [backgroundRunArrays mapWithBlock:^id(iTermBackgroundColorRunsInLine *runs) {
        NSMutableArray<iTermBoxedBackgroundColorRun *> *combinedRuns = [NSMutableArray array];
        iTermBackgroundColorRun previousRun = { {0} };
        BOOL havePreviousRun = NO;
        for (iTermBoxedBackgroundColorRun *run in runs.array) {
            if (!havePreviousRun) {
                havePreviousRun = YES;
                previousRun = *run.valuePointer;
            } else if (run.valuePointer->selected == previousRun.selected &&
                       run.valuePointer->isMatch == previousRun.isMatch) {
                previousRun.range = NSUnionRange(previousRun.range, run.valuePointer->range);
            } else {
                [combinedRuns addObject:[iTermBoxedBackgroundColorRun boxedBackgroundColorRunWithValue:previousRun]];
                previousRun = *run.valuePointer;
            }
        }
        if (havePreviousRun) {
            [combinedRuns addObject:[iTermBoxedBackgroundColorRun boxedBackgroundColorRunWithValue:previousRun]];
        }

        iTermBackgroundColorRunsInLine *fakeRuns = [[[iTermBackgroundColorRunsInLine alloc] init] autorelease];
        fakeRuns.line = runs.line;
        fakeRuns.y = runs.y;
        fakeRuns.numberOfEquivalentRows = runs.numberOfEquivalentRows;
        fakeRuns.array = combinedRuns;
        return fakeRuns;
    }];
    [self drawForegroundForBackgroundRunArrays:fakeRunArrays
                                           ctx:ctx];
}

// Draws
- (void)drawForegroundForBackgroundRunArrays:(NSArray<iTermBackgroundColorRunsInLine *> *)backgroundRunArrays
                                         ctx:(CGContextRef)ctx {
    iTermBackgroundColorRunsInLine *representativeRunArray = nil;
    NSInteger count = 0;
    for (iTermBackgroundColorRunsInLine *runArray in backgroundRunArrays) {
        if (count == 0) {
            representativeRunArray = runArray;
            count = runArray.numberOfEquivalentRows;
        }
        count--;
        [self drawForegroundForLineNumber:runArray.line
                                        y:runArray.y
                           backgroundRuns:representativeRunArray.array
                                  context:ctx];
    }
}

- (void)drawForegroundForLineNumber:(int)line
                                  y:(CGFloat)y
                     backgroundRuns:(NSArray<iTermBoxedBackgroundColorRun *> *)backgroundRuns
                            context:(CGContextRef)ctx {
    [self drawCharactersForLine:line
                            atY:y
                 backgroundRuns:backgroundRuns
                        context:ctx];
    [self drawNoteRangesOnLine:line];

    if (_debug) {
        NSString *s = [NSString stringWithFormat:@"%d", line];
        [s drawAtPoint:NSMakePoint(0, y)
        withAttributes:@{ NSForegroundColorAttributeName: [NSColor blackColor],
                          NSBackgroundColorAttributeName: [NSColor whiteColor],
                          NSFontAttributeName: [NSFont systemFontOfSize:8] }];
    }
}

#pragma mark - Drawing: Text

- (void)drawCharactersForLine:(int)line
                          atY:(CGFloat)y
               backgroundRuns:(NSArray<iTermBoxedBackgroundColorRun *> *)backgroundRuns
                      context:(CGContextRef)ctx {
    screen_char_t* theLine = [self.delegate drawingHelperLineAtIndex:line];
    NSData *matches = [_delegate drawingHelperMatchesOnLine:line];
    for (iTermBoxedBackgroundColorRun *box in backgroundRuns) {
        iTermBackgroundColorRun *run = box.valuePointer;
        NSPoint textOrigin = NSMakePoint([iTermAdvancedSettingsModel terminalMargin] + run->range.location * _cellSize.width,
                                         y);
        [self constructAndDrawRunsForLine:theLine
                                      row:line
                                  inRange:run->range
                          startingAtPoint:textOrigin
                               bgselected:run->selected
                                  bgColor:box.unprocessedBackgroundColor
                 processedBackgroundColor:box.backgroundColor
                                 colorRun:box.valuePointer
                                  matches:matches
                           forceTextColor:nil
                                  context:ctx];
    }
}

- (void)constructAndDrawRunsForLine:(screen_char_t *)theLine
                                row:(int)row
                            inRange:(NSRange)indexRange
                    startingAtPoint:(NSPoint)initialPoint
                         bgselected:(BOOL)bgselected
                            bgColor:(NSColor *)bgColor
           processedBackgroundColor:(NSColor *)processedBackgroundColor
                           colorRun:(iTermBackgroundColorRun *)colorRun
                            matches:(NSData *)matches
                     forceTextColor:(NSColor *)forceTextColor  // optional
                            context:(CGContextRef)ctx {
    CTVector(CGFloat) positions;
    CTVectorCreate(&positions, _gridSize.width);

    if (indexRange.location > 0) {
        screen_char_t firstCharacter = theLine[indexRange.location];
        if (firstCharacter.code == DWC_RIGHT && !firstCharacter.complexChar) {
            // Don't try to start drawing in the middle of a double-width character.
            indexRange.location -= 1;
            indexRange.length += 1;
            initialPoint.x -= _cellSize.width;
        }
    }

//    NSLog(@"Draw text on line %d range %@", row, NSStringFromRange(indexRange));

    iTermPreciseTimerStatsStartTimer(&_stats[TIMER_STAT_CONSTRUCTION]);
    NSArray<id<iTermAttributedString>> *attributedStrings = [self attributedStringsForLine:theLine
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
    [self drawMultipartAttributedString:attributedStrings
                                atPoint:initialPoint
                                 origin:VT100GridCoordMake(indexRange.location, row)
                              positions:&positions
                              inContext:ctx
                        backgroundColor:processedBackgroundColor];

    CTVectorDestroy(&positions);
    iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_STAT_DRAW]);
}

- (void)drawMultipartAttributedString:(NSArray<id<iTermAttributedString>> *)attributedStrings
                              atPoint:(NSPoint)initialPoint
                               origin:(VT100GridCoord)initialOrigin
                            positions:(CTVector(CGFloat) *)positions
                            inContext:(CGContextRef)ctx
                      backgroundColor:(NSColor *)backgroundColor {
    NSPoint point = initialPoint;
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
                                                 backgroundColor:backgroundColor];
        } else {
            NSPoint offsetPoint = point;
            offsetPoint.y -= round((_cellSize.height - _cellSizeWithoutSpacing.height) / 2.0);
            numCellsDrawn = [self drawFastPathString:(iTermCheapAttributedString *)singlePartAttributedString
                                             atPoint:offsetPoint
                                              origin:origin
                                           positions:subpositions
                                           inContext:ctx
                                     backgroundColor:backgroundColor];
        }
//        [[NSColor colorWithRed:arc4random_uniform(255) / 255.0
//                         green:arc4random_uniform(255) / 255.0
//                          blue:arc4random_uniform(255) / 255.0
//                         alpha:1] set];
//        NSFrameRect(NSMakeRect(point.x + subpositions[0], point.y, numCellsDrawn * _cellSize.width, _cellSize.height));

        origin.x += numCellsDrawn;

    }
}

- (void)drawBoxDrawingCharacter:(unichar)theCharacter withAttributes:(NSDictionary *)attributes at:(NSPoint)pos {
    NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
    [ctx saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:pos.x yBy:pos.y];
    [transform concat];

    BOOL solid = NO;
    for (NSBezierPath *path in [iTermBoxDrawingBezierCurveFactory bezierPathsForBoxDrawingCode:theCharacter
                                                                                      cellSize:_cellSize
                                                                                         scale:1
                                                                                         solid:&solid]) {
        NSColor *color = [NSColor colorWithCGColor:(CGColorRef)attributes[(NSString *)kCTForegroundColorAttributeName]];
        [color set];
        if (solid) {
            [path fill];
        } else {
            [path stroke];
        }
    }

    [ctx restoreGraphicsState];
}

- (void)selectFont:(NSFont *)font inContext:(CGContextRef)ctx {
    if (font != _selectedFont) {
        // This method is really slow so avoid doing it when it's not
        // necessary. It is also deprecated but CoreText is extremely slow so
        // we'll keep using until Apple fixes that.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CGContextSelectFont(ctx,
                            [[font fontName] UTF8String],
                            [font pointSize],
                            kCGEncodingMacRoman);
#pragma clang diagnostic pop
        [_selectedFont release];
        _selectedFont = [font retain];
    }
}

// Just like drawTextOnlyAttributedString but 2-3x faster. Uses
// CGContextShowGlyphsAtPositions instead of CTFontDrawGlyphs.
- (int)drawFastPathString:(iTermCheapAttributedString *)cheapString
                  atPoint:(NSPoint)point
                   origin:(VT100GridCoord)origin
                positions:(CGFloat *)positions
                inContext:(CGContextRef)ctx
          backgroundColor:(NSColor *)backgroundColor {
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
                  originInImage:originInImage];
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
        [self drawTextOnlyAttributedStringWithoutUnderline:[NSAttributedString attributedStringWithString:string
                                                                                               attributes:cheapString.attributes]
                                                   atPoint:point
                                                 positions:positions
                                           backgroundColor:backgroundColor
                                           graphicsContext:[NSGraphicsContext currentContext]
                                                     smear:NO];
        return cheapString.length;
    }
    CGColorRef const color = (CGColorRef)cheapString.attributes[(NSString *)kCTForegroundColorAttributeName];
    const BOOL fakeItalic = [cheapString.attributes[iTermFakeItalicAttribute] boolValue];
    const BOOL fakeBold = [cheapString.attributes[iTermFakeBoldAttribute] boolValue];
    const BOOL antiAlias = [cheapString.attributes[iTermAntiAliasAttribute] boolValue];

    CGContextSetShouldAntialias(ctx, antiAlias);

    int savedFontSmoothingStyle = 0;
    const CGFloat *components = CGColorGetComponents(color);
    const BOOL useThinStrokes = [self useThinStrokesAgainstBackgroundColor:backgroundColor
                                                           foregroundColor:color];
    if (useThinStrokes) {
        CGContextSetShouldSmoothFonts(ctx, YES);
        // This seems to be available at least on 10.8 and later. The only reference to it is in
        // WebKit. This causes text to render just a little lighter, which looks nicer.
        savedFontSmoothingStyle = CGContextGetFontSmoothingStyle(ctx);
        CGContextSetFontSmoothingStyle(ctx, 16);
    }

    size_t numCodes = cheapString.length;
    size_t length = numCodes;
    [self selectFont:font inContext:ctx];
    CGContextSetFillColorSpace(ctx, CGColorGetColorSpace(color));
    if (CGColorGetAlpha(color) < 1) {
        CGContextSetBlendMode(ctx, kCGBlendModeSourceAtop);
    }
    CGContextSetFillColor(ctx, components);
    double y = point.y + _cellSize.height + _baselineOffset;
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
#if 0
    // Indicates which regions were drawn with the fastpath
    [[NSColor yellowColor] set];
    NSFrameRect(NSMakeRect(point.x + positions[0], point.y, positions[length - 1] - positions[0] + _cellSize.width, _cellSize.height));
#endif

    if (useThinStrokes) {
        CGContextSetFontSmoothingStyle(ctx, savedFontSmoothingStyle);
    }
    if (CGColorGetAlpha(color) < 1) {
        CGContextSetBlendMode(ctx, kCGBlendModeNormal);
    }

    return length;
}

- (int)drawSinglePartAttributedString:(NSAttributedString *)attributedString
                              atPoint:(NSPoint)point
                               origin:(VT100GridCoord)origin
                            positions:(CGFloat *)positions
                            inContext:(CGContextRef)ctx
                      backgroundColor:(NSColor *)backgroundColor {
    NSDictionary *attributes = [attributedString attributesAtIndex:0 effectiveRange:nil];
    if (attributes[iTermImageCodeAttribute]) {
        // Handle cells that are part of an image.
        VT100GridCoord originInImage = VT100GridCoordMake([attributes[iTermImageColumnAttribute] intValue],
                                                          [attributes[iTermImageLineAttribute] intValue]);
        int displayColumn = [attributes[iTermImageDisplayColumnAttribute] intValue];
        [self drawImageWithCode:[attributes[iTermImageCodeAttribute] shortValue]
                         origin:VT100GridCoordMake(displayColumn, origin.y)
                         length:attributedString.length
                        atPoint:NSMakePoint(positions[0] + point.x, point.y)
                  originInImage:originInImage];
        return attributedString.length;
    } else if ([attributes[iTermIsBoxDrawingAttribute] boolValue]) {
        // Special box-drawing cells don't use the font so they look prettier.
        [attributedString.string enumerateComposedCharacters:^(NSRange range, unichar simple, NSString *complexString, BOOL *stop) {
            NSPoint p = NSMakePoint(point.x + positions[range.location], point.y);
            [self drawBoxDrawingCharacter:simple
                           withAttributes:[attributedString attributesAtIndex:range.location
                                                               effectiveRange:nil]
                                       at:p];
        }];
        return attributedString.length;
    } else if (attributedString.length > 0) {
        NSPoint offsetPoint = point;
        offsetPoint.y -= round((_cellSize.height - _cellSizeWithoutSpacing.height) / 2.0);
        [self drawTextOnlyAttributedString:attributedString atPoint:offsetPoint positions:positions backgroundColor:backgroundColor];
        return attributedString.length;
    } else {
        // attributedString is empty
        return 0;
    }
}

- (void)drawTextOnlyAttributedStringWithoutUnderline:(NSAttributedString *)attributedString
                                             atPoint:(NSPoint)origin
                                           positions:(CGFloat *)stringPositions
                                     backgroundColor:(NSColor *)backgroundColor
                                     graphicsContext:(NSGraphicsContext *)ctx
                                               smear:(BOOL)smear {
    if (attributedString.length == 0) {
        return;
    }
    NSDictionary *attributes = [attributedString attributesAtIndex:0 effectiveRange:nil];
    CGColorRef cgColor = (CGColorRef)attributes[(NSString *)kCTForegroundColorAttributeName];

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
    lineRef = (CTLineRef)_lineRefCache[attributedString];
    if (lineRef == nil) {
        lineRef = CTLineCreateWithAttributedString((CFAttributedStringRef)attributedString);
        _lineRefCache[attributedString] = (id)lineRef;
        CFRelease(lineRef);
    }
    _replacementLineRefCache[attributedString] = (id)lineRef;

    CFArrayRef runs = CTLineGetGlyphRuns(lineRef);
    CGContextRef cgContext = (CGContextRef) [ctx graphicsPort];
    CGContextSetShouldAntialias(cgContext, antiAlias);
    CGContextSetFillColorWithColor(cgContext, cgColor);
    CGContextSetStrokeColorWithColor(cgContext, cgColor);

    CGFloat c = 0.0;
    if (fakeItalic) {
        c = 0.2;
    }

    int savedFontSmoothingStyle = 0;
    BOOL useThinStrokes = [self useThinStrokesAgainstBackgroundColor:backgroundColor
                                                     foregroundColor:cgColor];
    if (useThinStrokes) {
        CGContextSetShouldSmoothFonts(cgContext, YES);
        // This seems to be available at least on 10.8 and later. The only reference to it is in
        // WebKit. This causes text to render just a little lighter, which looks nicer.
        savedFontSmoothingStyle = CGContextGetFontSmoothingStyle(cgContext);
        CGContextSetFontSmoothingStyle(cgContext, 16);
    }

    const CGFloat ty = origin.y + _baselineOffset + _cellSize.height;
    CGAffineTransform textMatrix = CGAffineTransformMake(1.0, 0.0,
                                                         c, -1.0,
                                                         origin.x + stringPositions[0], ty);
    CGContextSetTextMatrix(cgContext, textMatrix);

    CGFloat cellOrigin = -1;
    CFIndex previousCharacterIndex = -1;
    for (CFIndex j = 0; j < CFArrayGetCount(runs); j++) {
        CTRunRef run = CFArrayGetValueAtIndex(runs, j);
        size_t length = CTRunGetGlyphCount(run);
        const CGGlyph *buffer = CTRunGetGlyphsPtr(run);
        if (!buffer) {
            NSMutableData *tempBuffer =
                [[[NSMutableData alloc] initWithLength:sizeof(CGGlyph) * length] autorelease];
            CTRunGetGlyphs(run, CFRangeMake(0, length), (CGGlyph *)tempBuffer.mutableBytes);
            buffer = tempBuffer.mutableBytes;
        }

        NSMutableData *positionsBuffer =
            [[[NSMutableData alloc] initWithLength:sizeof(CGPoint) * length] autorelease];
        CTRunGetPositions(run, CFRangeMake(0, length), (CGPoint *)positionsBuffer.mutableBytes);
        CGPoint *positions = positionsBuffer.mutableBytes;

        const CFIndex *glyphIndexToCharacterIndex = CTRunGetStringIndicesPtr(run);
        if (!glyphIndexToCharacterIndex) {
            NSMutableData *tempBuffer =
                [[[NSMutableData alloc] initWithLength:sizeof(CFIndex) * length] autorelease];
            CTRunGetStringIndices(run, CFRangeMake(0, length), (CFIndex *)tempBuffer.mutableBytes);
            glyphIndexToCharacterIndex = (CFIndex *)tempBuffer.mutableBytes;
        }

        CGFloat positionOfFirstGlyphInCluster = positions[0].x;
        for (size_t glyphIndex = 0; glyphIndex < length; glyphIndex++) {
            CFIndex characterIndex = glyphIndexToCharacterIndex[glyphIndex];
            CGFloat characterPosition = stringPositions[characterIndex] - stringPositions[0];
            if (characterIndex != previousCharacterIndex && characterPosition != cellOrigin) {
                positionOfFirstGlyphInCluster = positions[glyphIndex].x;
                cellOrigin = characterPosition;
            }
            positions[glyphIndex].x += cellOrigin - positionOfFirstGlyphInCluster;
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


    if (useThinStrokes) {
        CGContextSetFontSmoothingStyle(cgContext, savedFontSmoothingStyle);
    }

    [ctx restoreGraphicsState];
}

- (void)drawTextOnlyAttributedString:(NSAttributedString *)attributedString
                                atPoint:(NSPoint)origin
                           positions:(CGFloat *)stringPositions
                     backgroundColor:(NSColor *)backgroundColor {
    NSGraphicsContext *graphicsContext = [NSGraphicsContext currentContext];

    [self drawTextOnlyAttributedStringWithoutUnderline:attributedString
                                               atPoint:origin
                                             positions:stringPositions
                                       backgroundColor:backgroundColor
                                       graphicsContext:graphicsContext
                                                 smear:NO];

    __block CGContextRef maskGraphicsContext = nil;
    __block CGImageRef alphaMask = nil;
    NSDictionary *maskingAttributes = @{ (NSString *)kCTForegroundColorAttributeName: (id)[[NSColor colorWithSRGBRed:0 green:0 blue:0 alpha:1] CGColor] };
    CGContextRef cgContext = (CGContextRef) [graphicsContext graphicsPort];

    [attributedString enumerateAttribute:NSUnderlineStyleAttributeName
                                 inRange:NSMakeRange(0, attributedString.length)
                                 options:0
                              usingBlock:^(NSNumber * _Nullable value, NSRange range, BOOL * _Nonnull stop) {
                                  NSUnderlineStyle underlineStyle = value.integerValue;
                                  if (underlineStyle != NSUnderlineStyleNone) {
                                      CGFloat xOrigin = origin.x + stringPositions[range.location];
                                      const BOOL mask = YES;
                                      NSDictionary *attributes = [attributedString attributesAtIndex:range.location
                                                                                      effectiveRange:nil];
                                      const CGFloat width = [attributes[iTermUnderlineLengthAttribute] intValue] * _cellSize.width;
                                      if (mask) {
                                          const CGFloat maskHeight = _cellSize.height * 2;
                                          if (!maskGraphicsContext) {
                                              // Create a mask image.
                                              maskGraphicsContext = [self newGrayscaleContextOfSize:NSMakeSize(width, maskHeight)];
                                              [NSGraphicsContext saveGraphicsState];
                                              [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithGraphicsPort:maskGraphicsContext
                                                                                                                              flipped:NO]];

                                              // Draw the background
                                              [[NSColor whiteColor] setFill];
                                              CGContextFillRect([[NSGraphicsContext currentContext] graphicsPort], NSMakeRect(0, 0, width, maskHeight));

                                              // Draw text into the mask
                                              NSMutableAttributedString *modifiedAttributedString = [[attributedString mutableCopy] autorelease];
                                              NSRange fullRange = NSMakeRange(0, modifiedAttributedString.length);
                                              [modifiedAttributedString removeAttribute:(NSString *)kCTForegroundColorAttributeName range:fullRange];
                                              [modifiedAttributedString addAttributes:maskingAttributes range:fullRange];

                                              [self drawTextOnlyAttributedStringWithoutUnderline:modifiedAttributedString
                                                                                         atPoint:NSMakePoint(-stringPositions[range.location], 0)
                                                                                       positions:stringPositions
                                                                                 backgroundColor:[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:1]
                                                                                 graphicsContext:[NSGraphicsContext currentContext]
                                                                                           smear:YES];

                                              // Switch back to the window's context
                                              [NSGraphicsContext restoreGraphicsState];

                                              // Create an image mask from what we've drawn so far
                                              alphaMask = CGBitmapContextCreateImage(maskGraphicsContext);
                                          }

                                          // Mask it
                                          CGContextSaveGState(cgContext);
                                          CGContextClipToMask(cgContext,
                                                              NSMakeRect(xOrigin,
                                                                         origin.y,
                                                                         width,
                                                                         maskHeight),
                                                              alphaMask);
                                      }

                                      NSColor *underline = [self.colorMap colorForKey:kColorMapUnderline];
                                      CGColorRef cgColor = (underline ? [underline CGColor] : (CGColorRef)attributes[(NSString *)kCTForegroundColorAttributeName]);
                                      [self drawUnderlineOfColor:[NSColor colorWithCGColor:cgColor]
                                                           style:underlineStyle
                                                    atCellOrigin:NSMakePoint(xOrigin, origin.y)
                                                            font:attributes[NSFontAttributeName]
                                                           width:width];


                                      if (mask) {
                                          // Remove mask
                                          CGContextRestoreGState(cgContext);
                                      }
                                  }
                              }];

    if (maskGraphicsContext) {
        CGContextRelease(maskGraphicsContext);
    }
    if (alphaMask) {
        CGImageRelease(alphaMask);
    }
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
                                            iTermBackgroundColorRun *colorRun) {
    NSColor *rawColor = nil;
    BOOL isMatch = NO;
    if (c->faint && colorRun && !context->backgroundColor) {
        context->backgroundColor = [self unprocessedColorForBackgroundRun:colorRun];
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
        context->havePreviousCharacterAttributes = NO;
    } else if (inUnderlinedRange) {
        // Blue link text.
        rawColor = [context->colorMap colorForKey:kColorMapLink];
        context->havePreviousCharacterAttributes = NO;
    } else if (context->hasSelectedText) {
        // Selected text.
        rawColor = [context->colorMap colorForKey:kColorMapSelectedText];
        context->havePreviousCharacterAttributes = NO;
    } else if (context->reverseVideo &&
               ((c->foregroundColor == ALTSEM_DEFAULT && c->foregroundColorMode == ColorModeAlternate) ||
                (c->foregroundColor == ALTSEM_CURSOR && c->foregroundColorMode == ColorModeAlternate))) {
        // Reverse video is on. Either is cursor or has default foreground color. Use
        // background color.
        rawColor = [context->colorMap colorForKey:kColorMapBackground];
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
    } else {
        // Foreground attributes are just like the last character. There is a cached foreground color.
        if (needsProcessing && context->backgroundColor != context->previousBackgroundColor) {
            // Process the text color for the current background color, which has changed since
            // the last cell.
            rawColor = context->lastUnprocessedColor;
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
                                               overBackgroundColor:context->backgroundColor];
    } else {
        result = rawColor;
    }
    context->previousForegroundColor = result;
    return result;
}

static BOOL iTermTextDrawingHelperShouldAntiAlias(screen_char_t *c,
                                                  BOOL useNonAsciiFont,
                                                  BOOL asciiAntiAlias,
                                                  BOOL nonAsciiAntiAlias) {
    if (!useNonAsciiFont || (c->code < 128 && !c->complexChar)) {
        return asciiAntiAlias;
    } else {
        return nonAsciiAntiAlias;
    }
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
        // Not an image cell. Try to quicly check if the attributes are the same, which is the normal case.
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
                                          newAttributes->fakeItalic != previousAttributes->fakeItalic ||
                                          newAttributes->underline != previousAttributes->underline ||
                                          newAttributes->isURL != previousAttributes->isURL ||
                                          newAttributes->drawable != previousAttributes->drawable);
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
                          atIndex:(NSInteger)i
                   forceTextColor:(NSColor *)forceTextColor
                   forceUnderline:(BOOL)inUnderlinedRange
                         colorRun:(iTermBackgroundColorRun *)colorRun
                         drawable:(BOOL)drawable
                 textColorContext:(iTermTextColorContext *)textColorContext
                       attributes:(iTermCharacterAttributes *)attributes {
    attributes->initialized = YES;
    attributes->shouldAntiAlias = iTermTextDrawingHelperShouldAntiAlias(c,
                                                                       _useNonAsciiFont,
                                                                       _asciiAntiAlias,
                                                                       _nonAsciiAntiAlias);
    if (forceTextColor) {
        attributes->foregroundColor = forceTextColor;
    } else {
        attributes->foregroundColor = iTermTextDrawingHelperGetTextColor(self,
                                                                         c,
                                                                         inUnderlinedRange,
                                                                         i,
                                                                         textColorContext,
                                                                         colorRun);
    }

    const BOOL isComplex = c->complexChar;
    const unichar code = c->code;

    attributes->boxDrawing = !isComplex && [[iTermBoxDrawingBezierCurveFactory boxDrawingCharactersWithBezierPaths] characterIsMember:code];
    attributes->bold = c->bold;

    attributes->fakeBold = c->bold;  // default value
    attributes->fakeItalic = c->italic;  // default value
    PTYFontInfo *fontInfo = [_delegate drawingHelperFontForChar:code
                                                      isComplex:isComplex
                                                     renderBold:&attributes->fakeBold
                                                   renderItalic:&attributes->fakeItalic];

    attributes->font = fontInfo.font;
    attributes->ligatureLevel = fontInfo.ligatureLevel;
    if (!c->complexChar && iTermCharacterSupportsFastPath(c->code, _asciiLigaturesAvailable)) {
        attributes->ligatureLevel = 0;
    }
    if (c->complexChar || c->code > 128) {
        if (!_nonAsciiLigatures) {
            attributes->ligatureLevel = 0;
        }
    }
    attributes->underline = (c->underline || inUnderlinedRange);
    attributes->isURL = (c->urlCode != 0);
    attributes->drawable = drawable;
}

- (NSDictionary *)dictionaryForCharacterAttributes:(iTermCharacterAttributes *)attributes {
    NSUnderlineStyle underlineStyle = NSUnderlineStyleNone;
    if (attributes->underline) {
        if (attributes->isURL) {
            underlineStyle = NSUnderlineStyleDouble;
        } else {
            underlineStyle = NSUnderlineStyleSingle;
        }
    } else if (attributes->isURL) {
        underlineStyle = NSUnderlinePatternDash;
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
              iTermFakeItalicAttribute: @(attributes->fakeItalic),
              NSUnderlineStyleAttributeName: @(underlineStyle),
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

- (BOOL)character:(screen_char_t *)c isEquivalentToCharacter:(screen_char_t *)pc {
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
            boxSet = [[iTermBoxDrawingBezierCurveFactory boxDrawingCharactersWithBezierPaths] retain];
        });
        BOOL box = [boxSet characterIsMember:c->code];
        BOOL pcBox = [boxSet characterIsMember:pc->code];
        if (box != pcBox) {
            return NO;
        }
    }
    if (!ScreenCharacterAttributesEqual(c, pc)) {
        return NO;
    }

    return YES;
}

- (BOOL)zippy {
    return (!(_asciiLigaturesAvailable && _asciiLigatures) &&
            !(_nonAsciiLigatures) &&
            [iTermAdvancedSettingsModel zippyTextDrawing]);
}

- (NSArray<id<iTermAttributedString>> *)attributedStringsForLine:(screen_char_t *)line
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
    iTermMutableAttributedStringBuilder *builder = [[[iTermMutableAttributedStringBuilder alloc] init] autorelease];
    builder.zippy = self.zippy;
    builder.asciiLigaturesAvailable = _asciiLigaturesAvailable && _asciiLigatures;
    iTermCharacterAttributes characterAttributes = { 0 };
    iTermCharacterAttributes previousCharacterAttributes = { 0 };
    int segmentLength = 0;
    BOOL previousDrawable = YES;

    for (int i = indexRange.location; i < NSMaxRange(indexRange); i++) {
        iTermPreciseTimerStatsStartTimer(&_stats[TIMER_ATTRS_FOR_CHAR]);
        screen_char_t c = line[i];
        unichar code = c.code;
        BOOL isComplex = c.complexChar;

        NSString *charAsString;
        if (isComplex) {
            charAsString = ComplexCharToStr(c.code);
        } else {
            charAsString = nil;
        }

        const BOOL drawable = iTermTextDrawingHelperIsCharacterDrawable(&c,
                                                                        charAsString != nil,
                                                                        _blinkingItemsVisible,
                                                                        _blinkAllowed);
        if (!drawable) {
            if ((characterAttributes.drawable && c.code == DWC_RIGHT && !c.complexChar) ||
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
#if !ENABLE_FASTPATH_UNDERLINES
            likely(!c.underline) &&
            likely(c.urlCode == 0) &&
#endif
            [self character:&c isEquivalentToCharacter:&line[i-1]]) {
            ++segmentLength;
            iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_ATTRS_FOR_CHAR]);
            if (drawable || ((characterAttributes.underline || characterAttributes.isURL) && segmentLength == 1)) {
                [self updateBuilder:builder
                         withString:drawable ? charAsString : @" "
                        orCharacter:code
                          positions:positions
                             offset:(i - indexRange.location) * _cellSize.width];
            }
            continue;
        }
        previousDrawable = drawable;

        [self getAttributesForCharacter:&c
                                atIndex:i
                         forceTextColor:forceTextColor
                         forceUnderline:NSLocationInRange(i, underlinedRange)
                               colorRun:colorRun
                               drawable:drawable
                       textColorContext:&textColorContext
                             attributes:&characterAttributes];

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
            if (previousCharacterAttributes.underline || previousCharacterAttributes.isURL) {
                [builtString addAttribute:iTermUnderlineLengthAttribute
                                    value:@(segmentLength)];
            }
            segmentLength = 0;
            iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_STAT_BUILD_MUTABLE_ATTRIBUTED_STRING]);

            if (builtString.length > 0) {
                [attributedStrings addObject:builtString];
            }
            builder = [[[iTermMutableAttributedStringBuilder alloc] init] autorelease];
            builder.zippy = self.zippy;
            builder.asciiLigaturesAvailable = _asciiLigaturesAvailable && _asciiLigatures;
        }
        ++segmentLength;
        memcpy(&previousCharacterAttributes, &characterAttributes, sizeof(previousCharacterAttributes));
        previousImageAttributes = [[imageAttributes copy] autorelease];
#if !ENABLE_FASTPATH_UNDERLINES
        if (characterAttributes.underline || characterAttributes.isURL) {
            [builder disableFastPath];
        }
#endif
        iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_SHOULD_SEGMENT]);

        iTermPreciseTimerStatsStartTimer(&_stats[TIMER_COMBINE_ATTRIBUTES]);
        if (combinedAttributesChanged) {
            NSDictionary *combinedAttributes = [self dictionaryForCharacterAttributes:&characterAttributes];
            if (imageAttributes) {
                combinedAttributes = [combinedAttributes dictionaryByMergingDictionary:imageAttributes];
            }
            [builder setAttributes:combinedAttributes];
        }
        iTermPreciseTimerStatsMeasureAndAccumulate(&_stats[TIMER_COMBINE_ATTRIBUTES]);

        if (drawable || ((characterAttributes.underline || characterAttributes.isURL) && segmentLength == 1)) {
            // Use " " when not drawable to prevent 0-length attributed strings when an underline is
            // present. If we get here's because there's an underline (which isn't quite obvious
            // from the if statement's condition).
            [self updateBuilder:builder
                     withString:drawable ? charAsString : @" "
                    orCharacter:code
                      positions:positions
                         offset:(i - indexRange.location) * _cellSize.width];
            if (characterAttributes.boxDrawing) {
                [builder disableFastPath];
            }
        }
    }
    if (builder.length) {
        iTermPreciseTimerStatsStartTimer(&_stats[TIMER_STAT_BUILD_MUTABLE_ATTRIBUTED_STRING]);
        id<iTermAttributedString> builtString = builder.attributedString;
        if (previousCharacterAttributes.underline || previousCharacterAttributes.isURL) {
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

- (CGFloat)underlineThicknessForFont:(NSFont *)font {
    return MAX(0.5, [self retinaRound:font.underlineThickness]);
}

- (void)drawUnderlineOfColor:(NSColor *)color
                       style:(NSUnderlineStyle)underlineStyle
                atCellOrigin:(NSPoint)startPoint
                        font:(NSFont *)font
                       width:(CGFloat)runWidth {
    [color set];
    NSBezierPath *path = [NSBezierPath bezierPath];

    NSPoint origin = NSMakePoint(startPoint.x,
                                 [self yOriginForUnderlineForFont:font
                                                          yOffset:startPoint.y
                                                       cellHeight:_cellSize.height]);
    origin.y += self.isRetina ? 0.25 : 0.5;
    CGFloat dashPattern[] = { 4, 3 };
    CGFloat phase = fmod(startPoint.x, dashPattern[0] + dashPattern[1]);

    const CGFloat lineWidth = [self underlineThicknessForFont:font];
    switch (underlineStyle) {
        case NSUnderlineStyleSingle:
            [path moveToPoint:origin];
            [path lineToPoint:NSMakePoint(origin.x + runWidth, origin.y)];
            [path setLineWidth:lineWidth];
            [path stroke];
            break;

        case NSUnderlineStyleDouble: {
            origin.y -= lineWidth;
            [path moveToPoint:origin];
            [path lineToPoint:NSMakePoint(origin.x + runWidth, origin.y)];
            [path setLineWidth:lineWidth];
            [path stroke];

            path = [NSBezierPath bezierPath];
            [path moveToPoint:NSMakePoint(origin.x, origin.y + lineWidth + 1)];
            [path lineToPoint:NSMakePoint(origin.x + runWidth, origin.y + lineWidth + 1)];
            [path setLineWidth:lineWidth];
            [path setLineDash:dashPattern count:2 phase:phase];
            [path stroke];
            break;
        }

        case NSUnderlinePatternDash: {
            [path moveToPoint:origin];
            [path lineToPoint:NSMakePoint(origin.x + runWidth, origin.y)];
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
            originInImage:(VT100GridCoord)originInImage {
    //DLog(@"Drawing image at %@ with code %@", VT100GridCoordDescription(origin), @(code));
    iTermImageInfo *imageInfo = GetImageInfo(code);
    NSImage *image = [imageInfo imageWithCellSize:_cellSize];
    if (!image) {
        if (!imageInfo) {
            DLog(@"Image is missing (brown)");
            [[NSColor brownColor] set];
        } else {
            DLog(@"Image isn't loaded yet (gray)");
            [_missingImages addObject:imageInfo.uniqueIdentifier];

            [[NSColor grayColor] set];
        }
        NSRectFill(NSMakeRect(point.x, point.y, _cellSize.width * length, _cellSize.height));
        return;
    }
    [_missingImages removeObject:imageInfo.uniqueIdentifier];

    NSSize chunkSize = NSMakeSize(image.size.width / imageInfo.size.width,
                                  image.size.height / imageInfo.size.height);

    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:point.x yBy:point.y + _cellSize.height];
    [transform scaleXBy:1.0 yBy:-1.0];
    [transform concat];

    if (imageInfo.animated) {
        [_delegate drawingHelperDidFindRunOfAnimatedCellsStartingAt:origin ofLength:length];
        _animated = YES;
    }
    [image drawInRect:NSMakeRect(0, 0, _cellSize.width * length, _cellSize.height)
             fromRect:NSMakeRect(chunkSize.width * originInImage.x,
                                 image.size.height - _cellSize.height - chunkSize.height * originInImage.y,
                                 chunkSize.width * length,
                                 chunkSize.height)
            operation:NSCompositingOperationSourceOver
             fraction:1];
    [NSGraphicsContext restoreGraphicsState];
}

- (BOOL)drawInputMethodEditorTextAt:(int)xStart
                                  y:(int)yStart
                              width:(int)width
                             height:(int)height
                       cursorHeight:(double)cursorHeight
                                ctx:(CGContextRef)ctx {
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
                            self.unicodeVersion);
        int cursorX = 0;
        int baseX = floor(xStart * _cellSize.width + [iTermAdvancedSettingsModel terminalMargin]);
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
                buf[charsInLine + i].code == DWC_RIGHT) {
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

            NSRectFill(r);

            // Draw the characters.
            [self constructAndDrawRunsForLine:buf
                                          row:y
                                      inRange:NSMakeRange(i, charsInLine)
                              startingAtPoint:NSMakePoint(x, y)
                                   bgselected:NO
                                      bgColor:nil
                     processedBackgroundColor:[self defaultBackgroundColor]
                                     colorRun:nil
                                      matches:nil
                               forceTextColor:[self defaultTextColor]
                                      context:ctx];
            // Draw an underline.
            BOOL ignore;
            PTYFontInfo *fontInfo = [_delegate drawingHelperFontForChar:128
                                                              isComplex:NO
                                                             renderBold:&ignore
                                                           renderItalic:&ignore];
            [self drawUnderlineOfColor:[self defaultTextColor]
                                 style:NSUnderlineStyleSingle
                          atCellOrigin:NSMakePoint(x, y - round((_cellSize.height - _cellSizeWithoutSpacing.height) / 2.0))
                                  font:fontInfo.font
                                 width:charsInLine * _cellSize.width];

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
            x = floor(xStart * _cellSize.width + [iTermAdvancedSettingsModel terminalMargin]);
            y = (yStart + _numberOfLines - height) * _cellSize.height;
            i += charsInLine;
        }

        if (!foundCursor && i == cursorIndex) {
            if (justWrapped) {
                cursorX = [iTermAdvancedSettingsModel terminalMargin] + width * _cellSize.width;
                cursorY = preWrapY;
            } else {
                cursorX = x;
                cursorY = y;
            }
        }
        const double kCursorWidth = 2.0;
        double rightMargin = [iTermAdvancedSettingsModel terminalMargin] + _gridSize.width * _cellSize.width;
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
        NSRectFill(cursorFrame);

        return TRUE;
    }
    return FALSE;
}

#pragma mark - Drawing: Cursor

- (NSRect)frameForCursorAt:(VT100GridCoord)cursorCoord {
    const int rowNumber = cursorCoord.y + _numberOfLines - _gridSize.height;
    if ([iTermAdvancedSettingsModel fullHeightCursor]) {
        const CGFloat height = MAX(_cellSize.height, _cellSizeWithoutSpacing.height);
        return NSMakeRect(floor(cursorCoord.x * _cellSize.width + [iTermAdvancedSettingsModel terminalMargin]),
                          rowNumber * _cellSize.height,
                          MIN(_cellSize.width, _cellSizeWithoutSpacing.width),
                          height);
    } else {
        const CGFloat height = MIN(_cellSize.height, _cellSizeWithoutSpacing.height);
        return NSMakeRect(floor(cursorCoord.x * _cellSize.width + [iTermAdvancedSettingsModel terminalMargin]),
                          rowNumber * _cellSize.height + MAX(0, round((_cellSize.height - _cellSizeWithoutSpacing.height) / 2.0)),
                          MIN(_cellSize.width, _cellSizeWithoutSpacing.width),
                          height);
    }
}

- (NSRect)cursorFrame {
    return [self frameForCursorAt:_cursorCoord];
}

- (void)drawCopyModeCursor {
    iTermCursor *cursor = [iTermCursor itermCopyModeCursorInSelectionState:self.copyModeSelecting];
    cursor.delegate = self;

    [self reallyDrawCursor:cursor
                        at:VT100GridCoordMake(_copyModeCursorCoord.x, _copyModeCursorCoord.y - _numberOfScrollbackLines)
                   outline:NO];
}

- (void)drawCursor:(BOOL)outline {
    DLog(@"drawCursor:%@", @(outline));

    // Update the last time the cursor moved.
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!VT100GridCoordEquals(_cursorCoord, _oldCursorPosition)) {
        _lastTimeCursorMoved = now;
    }

    if ([self shouldDrawCursor]) {
        iTermCursor *cursor = [iTermCursor cursorOfType:_cursorType];
        cursor.delegate = self;
        NSRect rect = [self reallyDrawCursor:cursor at:_cursorCoord outline:outline];

        if (_showSearchingCursor) {
            NSImage *image = [NSImage imageNamed:@"SearchCursor"];
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

                [image drawInRect:imageRect
                         fromRect:NSZeroRect
                        operation:NSCompositingOperationSourceOver
                         fraction:1
                   respectFlipped:YES
                            hints:nil];
            }
        }
    }

    _oldCursorPosition = _cursorCoord;
}

- (NSRect)reallyDrawCursor:(iTermCursor *)cursor at:(VT100GridCoord)cursorCoord outline:(BOOL)outline {
    // Get the character that's under the cursor.
    screen_char_t *theLine;
    if (cursorCoord.y >= 0) {
        theLine = [self.delegate drawingHelperLineAtScreenIndex:cursorCoord.y];
    } else {
        theLine = [self.delegate drawingHelperLineAtIndex:cursorCoord.y + _numberOfScrollbackLines];
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
        NSImage *keyImage = [NSImage imageNamed:@"key"];
        CGPoint point = rect.origin;
        [keyImage drawInRect:NSMakeRect(point.x, point.y, _cellSize.width, _cellSize.height)
                    fromRect:NSZeroRect
                   operation:NSCompositingOperationSourceOver
                    fraction:1
              respectFlipped:YES
                       hints:nil];
        return rect;
    }


    NSColor *cursorTextColor;
    if (_reverseVideo) {
        cursorTextColor = [_colorMap colorForKey:kColorMapBackground];
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
                 outline:outline];
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
                                inLine:(screen_char_t *)theLine
                           doubleWidth:(BOOL *)doubleWidth {
    screen_char_t screenChar = theLine[column];
    int width = _gridSize.width;
    if (column == width) {
        screenChar = theLine[column - 1];
        screenChar.code = 0;
        screenChar.complexChar = NO;
    }
    if (screenChar.code) {
        if (screenChar.code == DWC_RIGHT) {
          *doubleWidth = NO;
        } else {
          *doubleWidth = (column < width - 1) && (theLine[column+1].code == DWC_RIGHT);
        }
    } else {
        *doubleWidth = NO;
    }
    return screenChar;
}

- (BOOL)shouldDrawCursor {
    BOOL shouldShowCursor = [self shouldShowCursor];
    int column = _cursorCoord.x;
    int row = _cursorCoord.y;
    int width = _gridSize.width;
    int height = _gridSize.height;

    int cursorRow = row + _numberOfScrollbackLines;
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
                   _cursorVisible &&
                   shouldShowCursor &&
                   column <= width &&
                   column >= 0 &&
                   row >= 0 &&
                   row < height);
    DLog(@"shouldDrawCursor: hasMarkedText=%d, cursorVisible=%d, showCursor=%d, column=%d, row=%d"
         @"width=%d, height=%d. Result=%@",
         (int)[self hasMarkedText], (int)_cursorVisible, (int)shouldShowCursor, column, row,
         width, height, @(result));
    return result;
}

#pragma mark - Coord/Rect Utilities

- (NSRange)rangeOfVisibleRows {
    int visibleRows = floor((_scrollViewContentSize.height - [iTermAdvancedSettingsModel terminalVMargin] * 2) / _cellSize.height);
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
    return VT100GridCoordRangeMake(floor((rect.origin.x - [iTermAdvancedSettingsModel terminalMargin]) / _cellSize.width),
                                   floor(rect.origin.y / _cellSize.height),
                                   ceil((NSMaxX(rect) - [iTermAdvancedSettingsModel terminalMargin]) / _cellSize.width),
                                   ceil(NSMaxY(rect) / _cellSize.height));
}

- (NSRect)rectForCoordRange:(VT100GridCoordRange)coordRange {
    return NSMakeRect(coordRange.start.x * _cellSize.width + [iTermAdvancedSettingsModel terminalMargin],
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
    charRange.location = MAX(0, (x - [iTermAdvancedSettingsModel terminalMargin]) / _cellSize.width);
    charRange.length = ceil((x + width - [iTermAdvancedSettingsModel terminalMargin]) / _cellSize.width) - charRange.location;
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

- (CGColorRef)cgColorForColor:(NSColor *)color {
    const NSInteger numberOfComponents = [color numberOfComponents];
    CGFloat components[numberOfComponents];
    CGColorSpaceRef colorSpace = [[color colorSpace] CGColorSpace];

    [color getComponents:(CGFloat *)&components];

    return (CGColorRef)[(id)CGColorCreate(colorSpace, components) autorelease];
}

- (BOOL)hasMarkedText {
    return _inputMethodMarkedRange.length > 0;
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
                                 overBackgroundColor:[self defaultBackgroundColor]];
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
    _visibleRect = _delegate.visibleRect;
    _scrollViewContentSize = _delegate.enclosingScrollView.contentSize;
    _scrollViewDocumentVisibleRect = _delegate.enclosingScrollView.documentVisibleRect;

    BOOL ignore1 = NO, ignore2 = NO;
    PTYFontInfo *fontInfo = [_delegate drawingHelperFontForChar:'a'
                                                      isComplex:NO
                                                     renderBold:&ignore1
                                                   renderItalic:&ignore2];
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
                                                 lineSource:^screen_char_t *(int y) {
                                                     return [_delegate drawingHelperLineAtScreenIndex:y];
                                                 }];
}

- (void)cursorDrawCharacterAt:(VT100GridCoord)coord
                  doubleWidth:(BOOL)doubleWidth
                overrideColor:(NSColor *)overrideColor
                      context:(CGContextRef)ctx
              backgroundColor:(NSColor *)backgroundColor {
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [context saveGraphicsState];

    int row = coord.y + _numberOfScrollbackLines;
    int width = doubleWidth ? 2 : 1;
    VT100GridCoordRange coordRange = VT100GridCoordRangeMake(coord.x, row, coord.x + width, row + 1);
    NSRect innerRect = [self rectForCoordRange:coordRange];
    NSRectClip(innerRect);

    screen_char_t *line = [self.delegate drawingHelperLineAtIndex:row];
    [self constructAndDrawRunsForLine:line
                                  row:row
                              inRange:NSMakeRange(0, _gridSize.width)
                      startingAtPoint:NSMakePoint([iTermAdvancedSettingsModel terminalMargin], row * _cellSize.height)
                           bgselected:NO
                              bgColor:backgroundColor
             processedBackgroundColor:backgroundColor
                             colorRun:nil
                              matches:nil
                       forceTextColor:overrideColor
                              context:ctx];

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
