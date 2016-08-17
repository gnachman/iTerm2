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

static const int kBadgeMargin = 4;

extern void CGContextSetFontSmoothingStyle(CGContextRef, int);
extern int CGContextGetFontSmoothingStyle(CGContextRef);

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
    NSInteger ligatureLevel;
    BOOL drawable;
} iTermCharacterAttributes;

enum {
    TIMER_STAT_CONSTRUCTION,
    TIMER_STAT_BUILD_MUTABLE_ATTRIBUTED_STRING,
    TIMER_STAT_DRAW,

    TIMER_ATTRS_FOR_CHAR,
    TIMER_SHOULD_SEGMENT,
    TIMER_ADVANCES,
    TIMER_UPDATE_BUILDER,
    
    TIMER_STAT_MAX
};

static NSString *const iTermAntiAliasAttribute = @"iTermAntiAliasAttribute";
static NSString *const iTermBoldAttribute = @"iTermBoldAttribute";
static NSString *const iTermFakeBoldAttribute = @"iTermFakeBoldAttribute";
static NSString *const iTermFakeItalicAttribute = @"iTermFakeItalicAttribute";
static NSString *const iTermImageCodeAttribute = @"iTermImageCodeAttribute";
static NSString *const iTermImageColumnAttribute = @"iTermImageColumnAttribute";
static NSString *const iTermImageLineAttribute = @"iTermImageLineAttribute";
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
    BOOL haveUnderlinedHostname;
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

    MovingAverage *_drawRectDuration;
    MovingAverage *_drawRectInterval;

    // Frame of the view we're drawing into.
    NSRect _frame;

    // The -visibleRect of the view we're drawing into.
    NSRect _visibleRect;
    
    NSSize _scrollViewContentSize;
    NSRect _scrollViewDocumentVisibleRect;

    // Pattern for background stripes
    NSImage *_backgroundStripesImage;
    
    iTermPreciseTimerStats _stats[TIMER_STAT_MAX];
    CGFloat _baselineOffset;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        if ([iTermAdvancedSettingsModel logDrawingPerformance]) {
            NSLog(@"** Drawing performance timing enabled **");
            _drawRectDuration = [[MovingAverage alloc] init];
            _drawRectInterval = [[MovingAverage alloc] init];
            _drawRectDuration.alpha = 0.95;
            _drawRectInterval.alpha = 0.95;
            
            iTermPreciseTimerStatsInit(&_stats[TIMER_STAT_CONSTRUCTION], "Construction");
            iTermPreciseTimerStatsInit(&_stats[TIMER_STAT_BUILD_MUTABLE_ATTRIBUTED_STRING], "Builder");
            iTermPreciseTimerStatsInit(&_stats[TIMER_STAT_DRAW], "Drawing");

            iTermPreciseTimerStatsInit(&_stats[TIMER_ATTRS_FOR_CHAR], "Compute Attrs");
            iTermPreciseTimerStatsInit(&_stats[TIMER_SHOULD_SEGMENT], "Segment");
            iTermPreciseTimerStatsInit(&_stats[TIMER_UPDATE_BUILDER], "Update Builder");
            iTermPreciseTimerStatsInit(&_stats[TIMER_ADVANCES], "Advances");
        }
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
    [_drawRectDuration release];
    [_drawRectInterval release];

    [_backgroundStripesImage release];

    [super dealloc];
}

#pragma mark - Drawing: General

- (void)drawTextViewContentInRect:(NSRect)rect
                         rectsPtr:(const NSRect *)rectArray
                        rectCount:(NSInteger)rectCount {
//    NSLog(@"drawRect:%@ in view %@", [NSValue valueWithRect:rect], _delegate);
    if (_debug) {
        [[NSColor redColor] set];
        NSRectFill(rect);
    }
    [self updateCachedMetrics];
    // If there are two or more rects that need display, the OS will pass in |rect| as the smallest
    // bounding rect that contains them all. Luckily, we can get the list of the "real" dirty rects
    // and they're guaranteed to be disjoint. So draw each of them individually.
    if (_drawRectDuration) {
        [self startTiming];
    }

    const int haloWidth = 4;
    NSInteger yLimit = _numberOfLines;

    VT100GridCoordRange boundingCoordRange = [self coordRangeForRect:rect];
    // Start at 0 because ligatures can draw incorrectly otherwise. When a font has a ligature for
    // -> and >-, then a line like ->->-> needs to start at the beginning since drawing only a
    // suffix of it could draw a >- ligature at the start of the range being drawn. Issue 5030.
    boundingCoordRange.start.x = 0;
    boundingCoordRange.start.y = MAX(0, boundingCoordRange.start.y - 1);
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

    [self drawRanges:ranges count:numRowsInRect origin:boundingCoordRange.start boundingRect:[self rectForCoordRange:boundingCoordRange]];
    
    [self drawCursor];

    if (_showDropTargets) {
        [self drawDropTargets];
    }

    if (_drawRectDuration) {
        [self stopTiming];
    }
    
    if ([iTermAdvancedSettingsModel logDrawingPerformance]) {
        iTermPreciseTimerPeriodicLog(_stats, sizeof(_stats) / sizeof(*_stats), 0);
    }


    if (_debug) {
        NSColor *c = [NSColor colorWithCalibratedRed:(rand() % 255) / 255.0
                                               green:(rand() % 255) / 255.0
                                                blue:(rand() % 255) / 255.0
                                               alpha:1];
        [c set];
        NSFrameRect(rect);
    }
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

- (void)drawRanges:(NSRange *)ranges count:(NSInteger)numRanges origin:(VT100GridCoord)origin boundingRect:(NSRect)boundingRect {
    // Configure graphics
    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositeCopy];

    iTermTextExtractor *extractor = [self.delegate drawingHelperTextExtractor];
    _blinkingFound = NO;

    NSMutableArray<iTermBackgroundColorRunsInLine *> *backgroundRunArrays = [NSMutableArray array];
    NSRange visibleLines = [self rangeOfVisibleRows];

    for (NSInteger i = 0; i < numRanges; i++) {
        const int line = origin.y + i;
        if (line >= NSMaxRange(visibleLines)) {
            continue;
        }
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
        
//        NSLog(@"    draw line %d", line);
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
    }

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

    // Draw default background color over the line under the last drawn line so the tops of
    // characters aren't visible there. If there is an IME, that could be many lines tall.
    VT100GridCoordRange drawableCoordRange = [self drawableCoordRangeForRect:_visibleRect];
    [self drawExcessAtLine:drawableCoordRange.end.y];
    
    // Draw other background-like stuff that goes behind text.
    [self drawAccessoriesInRect:boundingRect];

    // Now iterate over the lines and paint the characters.
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    iTermBackgroundColorRunsInLine *representativeRunArray = nil;
    NSInteger count = 0;
    for (iTermBackgroundColorRunsInLine *runArray in backgroundRunArrays) {
        if (count == 0) {
            representativeRunArray = runArray;
            count = runArray.numberOfEquivalentRows;
        }
        count--;
        [self drawCharactersForLine:runArray.line
                                atY:runArray.y
                     backgroundRuns:representativeRunArray.array
                            context:ctx];
        [self drawNoteRangesOnLine:runArray.line];

        if (_debug) {
            NSString *s = [NSString stringWithFormat:@"%d", runArray.line];
            [s drawAtPoint:NSMakePoint(0, runArray.y)
                withAttributes:@{ NSForegroundColorAttributeName: [NSColor blackColor],
                                  NSBackgroundColorAttributeName: [NSColor whiteColor],
                                  NSFontAttributeName: [NSFont systemFontOfSize:8] }];
        }
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
    
    [_selectedFont release];
    _selectedFont = nil;
}

#pragma mark - Drawing: Background

- (void)drawBackgroundForLine:(int)line
                          atY:(CGFloat)yOrigin
                         runs:(NSArray<iTermBoxedBackgroundColorRun *> *)runs
               equivalentRows:(NSInteger)rows {
    for (iTermBoxedBackgroundColorRun *box in runs) {
        iTermBackgroundColorRun *run = box.valuePointer;

//        NSLog(@"Paint background row %d range %@", line, NSStringFromRange(run->range));
        
        NSRect rect = NSMakeRect(floor(MARGIN + run->range.location * _cellSize.width),
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
                                 _hasBackgroundImage ? NSCompositeSourceOver : NSCompositeCopy);

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
        MAX(0, VMARGIN - NSMinY(_delegate.enclosingScrollView.documentVisibleRect));

    topMarginRect.size.height = VMARGIN;
    [self.delegate drawingHelperDrawBackgroundImageInRect:topMarginRect
                                   blendDefaultBackground:YES];

    if (_showStripes) {
        [self drawStripesInRect:topMarginRect];
    }
}

- (void)drawMarginsAndMarkForLine:(int)line y:(CGFloat)y {
    NSRect leftMargin = NSMakeRect(0, y, MARGIN, _cellSize.height);
    NSRect rightMargin;
    NSRect visibleRect = _visibleRect;
    rightMargin.origin.x = _cellSize.width * _gridSize.width + MARGIN;
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
    NSRectFillUsingOperation(rect, NSCompositeSourceOver);
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
    NSPoint textOrigin = NSMakePoint(MARGIN + range.location * _cellSize.width, yOrigin);
    NSRect rect = NSMakeRect(textOrigin.x,
                             textOrigin.y,
                             range.length * _cellSize.width,
                             _cellSize.height);
    NSRectFillUsingOperation(rect, NSCompositeSourceOver);

    rect.size.height = 1;
    NSRectFillUsingOperation(rect, NSCompositeSourceOver);

    rect.origin.y += _cellSize.height - 1;
    NSRectFillUsingOperation(rect, NSCompositeSourceOver);
}

- (void)drawMarkIfNeededOnLine:(int)line leftMarginRect:(NSRect)leftMargin {
    VT100ScreenMark *mark = [self.delegate drawingHelperMarkOnLine:line];
    if (mark.isVisible && self.drawMarkIndicators) {
        const CGFloat verticalSpacing = MAX(0, round((_cellSize.height - _cellSizeWithoutSpacing.height) / 2.0));
        CGRect rect = NSMakeRect(leftMargin.origin.x,
                                 leftMargin.origin.y + verticalSpacing,
                                 MARGIN,
                                 _cellSizeWithoutSpacing.height);
        const CGFloat kMaxHeight = 15;
        const CGFloat kMinMargin = 3;
        const CGFloat kMargin = MAX(kMinMargin, (_cellSizeWithoutSpacing.height - kMaxHeight) / 2.0);
        NSPoint top = NSMakePoint(NSMinX(rect), rect.origin.y + kMargin);
        NSPoint right = NSMakePoint(NSMaxX(rect), NSMidY(rect));
        NSPoint bottom = NSMakePoint(NSMinX(rect), NSMaxY(rect) - kMargin);

        [[NSColor blackColor] set];
        NSBezierPath *path = [NSBezierPath bezierPath];
        [path moveToPoint:NSMakePoint(bottom.x, bottom.y)];
        [path lineToPoint:NSMakePoint(right.x, right.y)];
        [path setLineWidth:1.0];
        [path stroke];

        if (mark.code == 0) {
            // Success
            [[NSColor colorWithCalibratedRed:120.0 / 255.0 green:178.0 / 255.0 blue:255.0 / 255.0 alpha:1] set];
        } else if ([iTermAdvancedSettingsModel showYellowMarkForJobStoppedBySignal] &&
                   mark.code >= 128 && mark.code <= 128 + 32) {
            // Stopped by a signal (or an error, but we can't tell which)
            [[NSColor colorWithCalibratedRed:210.0 / 255.0 green:210.0 / 255.0 blue:90.0 / 255.0 alpha:1] set];
        } else {
            // Failure
            [[NSColor colorWithCalibratedRed:248.0 / 255.0 green:90.0 / 255.0 blue:90.0 / 255.0 alpha:1] set];
        }

        [path moveToPoint:top];
        [path lineToPoint:right];
        [path lineToPoint:bottom];
        [path lineToPoint:top];
        [path fill];
    }
}

- (void)drawNoteRangesOnLine:(int)line {
    NSArray *noteRanges = [self.delegate drawingHelperCharactersWithNotesOnLine:line];
    if (noteRanges.count) {
        for (NSValue *value in noteRanges) {
            VT100GridRange range = [value gridRangeValue];
            CGFloat x = range.location * _cellSize.width + MARGIN;
            CGFloat y = line * _cellSize.height;
            [[NSColor yellowColor] set];

            CGFloat maxX = MIN(_frame.size.width - MARGIN, range.length * _cellSize.width + x);
            CGFloat w = maxX - x;
            NSRectFill(NSMakeRect(x, y + _cellSize.height - 1.5, w, 1));
            [[NSColor orangeColor] set];
            NSRectFill(NSMakeRect(x, y + _cellSize.height - 1, w, 1));
        }

    }
}

- (CGFloat)drawTimestamps {
    [self updateCachedMetrics];

    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    if (!self.isRetina) {
        CGContextSetShouldSmoothFonts(ctx, NO);
    }
    NSString *previous = nil;
    CGFloat width = 0;
    for (int y = _scrollViewDocumentVisibleRect.origin.y / _cellSize.height;
         y < NSMaxY(_scrollViewDocumentVisibleRect) / _cellSize.height && y < _numberOfLines;
         y++) {
        CGFloat thisWidth = 0;
        previous = [self drawTimestampForLine:y previousTimestamp:previous width:&thisWidth];
        width = MAX(thisWidth, width);
    }
    if (!self.isRetina) {
        CGContextSetShouldSmoothFonts(ctx, YES);
    }
    
    return width;
}

- (NSString *)drawTimestampForLine:(int)line
                 previousTimestamp:(NSString *)previousTimestamp
                             width:(CGFloat *)widthPtr {
    NSDate *timestamp = [_delegate drawingHelperTimestampForLine:line];
    NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
    const NSTimeInterval day = -86400;
    const NSTimeInterval timeDelta = timestamp.timeIntervalSinceReferenceDate - self.now;
    if (timeDelta < day * 180) {
        // More than 180 days ago: include year
        // I tried using 365 but it was pretty confusing to see tomorrow's date.
        [fmt setDateFormat:[NSDateFormatter dateFormatFromTemplate:@"yyyyMMMd jj:mm:ss"
                                                           options:0
                                                            locale:[NSLocale currentLocale]]];
    } else if (timeDelta < day * 6) {
        // 6 days to 180 days ago: include date without year
        [fmt setDateFormat:[NSDateFormatter dateFormatFromTemplate:@"MMMd jj:mm:ss"
                                                           options:0
                                                            locale:[NSLocale currentLocale]]];
    } else if (timeDelta < day) {
        // 1 day to 6 days ago: include day of week
        [fmt setDateFormat:[NSDateFormatter dateFormatFromTemplate:@"EEE jj:mm:ss"
                                                           options:0
                                                            locale:[NSLocale currentLocale]]];
    } else {
        // In last 24 hours, just show time
        [fmt setDateFormat:[NSDateFormatter dateFormatFromTemplate:@"jj:mm:ss"
                                                           options:0
                                                            locale:[NSLocale currentLocale]]];
    }

    if (self.useTestingTimezone) {
        fmt.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    }
    NSString *theTimestamp = [fmt stringFromDate:timestamp];
    if (!timestamp || ![timestamp timeIntervalSinceReferenceDate]) {
        theTimestamp = @"";
    }
    NSString *s = theTimestamp;
    BOOL repeat = [theTimestamp isEqualToString:previousTimestamp];

    NSString *widest = [s stringByReplacingOccurrencesOfRegex:@"[\\d\\p{Alphabetic}]" withString:@"M"];
    NSSize size = [widest sizeWithAttributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:[iTermAdvancedSettingsModel pointSizeOfTimeStamp]] }];
    int w = size.width + MARGIN;
    int x = MAX(0, _frame.size.width - w);
    CGFloat y = line * _cellSize.height;
    NSColor *bgColor = [self defaultBackgroundColor];
    // I don't want to use the dimmed color for this because it's really ugly (esp on nonretina)
    // so I can't use -defaultForegroundColor here.
    NSColor *fgColor = [_colorMap colorForKey:kColorMapForeground];
    NSColor *shadowColor;
    if ([fgColor isDark]) {
        shadowColor = [NSColor whiteColor];
    } else {
        shadowColor = [NSColor blackColor];
    }

    const CGFloat alpha = 0.9;
    NSGradient *gradient =
        [[[NSGradient alloc] initWithStartingColor:[bgColor colorWithAlphaComponent:0]
                                       endingColor:[bgColor colorWithAlphaComponent:alpha]] autorelease];
    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositeSourceOver];
    [gradient drawInRect:NSMakeRect(x - 20, y, 20, _cellSize.height) angle:0];

    [[bgColor colorWithAlphaComponent:alpha] set];
    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositeSourceOver];
    NSRectFillUsingOperation(NSMakeRect(x, y, w, _cellSize.height), NSCompositeSourceOver);

    NSShadow *shadow = [[[NSShadow alloc] init] autorelease];
    shadow.shadowColor = shadowColor;
    shadow.shadowBlurRadius = 0.2f;
    shadow.shadowOffset = CGSizeMake(0.5, -0.5);

    NSDictionary *attributes;
    if (self.isRetina) {
        attributes = @{ NSFontAttributeName: [NSFont userFixedPitchFontOfSize:[iTermAdvancedSettingsModel pointSizeOfTimeStamp]],
                        NSForegroundColorAttributeName: fgColor,
                        NSShadowAttributeName: shadow };
    } else {
        NSFont *font = [NSFont userFixedPitchFontOfSize:[iTermAdvancedSettingsModel pointSizeOfTimeStamp]];
        attributes = @{ NSFontAttributeName: [[NSFontManager sharedFontManager] fontWithFamily:font.familyName
                                                                                        traits:NSBoldFontMask
                                                                                        weight:0
                                                                                          size:font.pointSize],
                        NSForegroundColorAttributeName: fgColor };
    }
    CGFloat offset = (_cellSize.height - size.height) / 2;
    if (s.length && repeat) {
        [fgColor set];
        CGFloat center = x + 10;
        NSRectFill(NSMakeRect(center - 1, y, 1, _cellSize.height));
        NSRectFill(NSMakeRect(center + 1, y, 1, _cellSize.height));
    } else {
        [s drawAtPoint:NSMakePoint(x, y + offset) withAttributes:attributes];
    }
    *widthPtr = w;
    return theTimestamp;
}

- (NSSize)drawBadgeInRect:(NSRect)rect {
    NSImage *image = _badgeImage;
    if (!image) {
        return NSZeroSize;
    }
    NSSize textViewSize = _frame.size;
    NSSize visibleSize = _scrollViewDocumentVisibleRect.size;
    NSSize imageSize = image.size;
    NSRect destination = NSMakeRect(textViewSize.width - imageSize.width - [iTermAdvancedSettingsModel badgeRightMargin],
                                    textViewSize.height - visibleSize.height + kiTermIndicatorStandardHeight + [iTermAdvancedSettingsModel badgeTopMargin],
                                    imageSize.width,
                                    imageSize.height);
    NSRect intersection = NSIntersectionRect(rect, destination);
    if (intersection.size.width == 0 || intersection.size.height == 1) {
        return NSZeroSize;
    }
    NSRect source = intersection;
    source.origin.x -= destination.origin.x;
    source.origin.y -= destination.origin.y;
    source.origin.y = imageSize.height - (source.origin.y + source.size.height);

    [image drawInRect:intersection
             fromRect:source
            operation:NSCompositeSourceOver
             fraction:1
       respectFlipped:YES
                hints:nil];
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
        NSRectFillUsingOperation(rect, NSCompositeSourceOver);
        
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

#pragma mark - Drawing: Text

- (void)drawCharactersForLine:(int)line
                          atY:(CGFloat)y
               backgroundRuns:(NSArray<iTermBoxedBackgroundColorRun *> *)backgroundRuns
                      context:(CGContextRef)ctx {
    screen_char_t* theLine = [self.delegate drawingHelperLineAtIndex:line];
    NSData *matches = [_delegate drawingHelperMatchesOnLine:line];
    for (iTermBoxedBackgroundColorRun *box in backgroundRuns) {
        iTermBackgroundColorRun *run = box.valuePointer;
        NSPoint textOrigin = NSMakePoint(MARGIN + run->range.location * _cellSize.width,
                                         y);
        [self constructAndDrawRunsForLine:theLine
                                      row:line
                                  inRange:run->range
                          startingAtPoint:textOrigin
                               bgselected:run->selected
                                  bgColor:box.unprocessedBackgroundColor
                 processedBackgroundColor:box.backgroundColor
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
    NSArray<NSAttributedString *> *attributedStrings = [self attributedStringsForLine:theLine
                                                                                range:indexRange
                                                                      hasSelectedText:bgselected
                                                                      backgroundColor:bgColor
                                                                       forceTextColor:forceTextColor
                                                                          findMatches:matches
                                                                      underlinedRange:[self underlinedRangeOnLine:row + _totalScrollbackOverflow]
                                                                            positions:&positions];
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[TIMER_STAT_CONSTRUCTION]);
    
    iTermPreciseTimerStatsStartTimer(&_stats[TIMER_STAT_DRAW]);
    [self drawMultipartAttributedString:attributedStrings
                                atPoint:initialPoint
                                 origin:VT100GridCoordMake(indexRange.location, row)
                              positions:&positions
                              inContext:ctx
                        backgroundColor:processedBackgroundColor];
    
    CTVectorDestroy(&positions);
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[TIMER_STAT_DRAW]);
}

- (void)drawMultipartAttributedString:(NSArray<NSAttributedString *> *)attributedStrings
                              atPoint:(NSPoint)initialPoint
                               origin:(VT100GridCoord)initialOrigin
                            positions:(CTVector(CGFloat) *)positions
                            inContext:(CGContextRef)ctx
                      backgroundColor:(NSColor *)backgroundColor {
    NSPoint point = initialPoint;
    VT100GridCoord origin = initialOrigin;
    NSInteger start = 0;
    for (NSAttributedString *singlePartAttributedString in attributedStrings) {
        CGFloat *subpositions = CTVectorElementsFromIndex(positions, start);
        start += singlePartAttributedString.length;
        CGFloat width =
            [self drawSinglePartAttributedString:singlePartAttributedString
                                         atPoint:point
                                          origin:origin
                                       positions:subpositions
                                       inContext:ctx
                                 backgroundColor:backgroundColor];
//        [[NSColor colorWithRed:arc4random_uniform(255) / 255.0
//                         green:arc4random_uniform(255) / 255.0
//                          blue:arc4random_uniform(255) / 255.0
//                         alpha:1] set];
//        NSFrameRect(NSMakeRect(point.x + positions->elements[0], point.y, width, _cellSize.height));

        origin.x += round(width / _cellSize.width);

    }
}

- (void)drawBoxDrawingCharacter:(unichar)theCharacter withAttributes:(NSDictionary *)attributes at:(NSPoint)pos {
    NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
    [ctx saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:pos.x yBy:pos.y];
    [transform concat];

    for (NSBezierPath *path in [iTermBoxDrawingBezierCurveFactory bezierPathsForBoxDrawingCode:theCharacter
                                                                                      cellSize:_cellSize]) {
        NSColor *color = attributes[NSForegroundColorAttributeName];
        [color set];
        [path stroke];
    }

    [ctx restoreGraphicsState];
}

#warning This should return a number of cells, not a number of points.
- (CGFloat)drawSinglePartAttributedString:(NSAttributedString *)attributedString
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
        [self drawImageWithCode:[attributes[iTermImageCodeAttribute] shortValue]
                         origin:origin
                         length:attributedString.length
                        atPoint:point
                  originInImage:originInImage];
        return _cellSize.width * attributedString.length;
    } else if ([attributes[iTermIsBoxDrawingAttribute] boolValue]) {
        // Special box-drawing cells don't use the font so they look prettier.
        [attributedString.string enumerateComposedCharacters:^(NSRange range, unichar simple, NSString *complexString, BOOL *stop) {
            NSPoint p = NSMakePoint(point.x + positions[range.location], point.y);
            [self drawBoxDrawingCharacter:simple
                           withAttributes:[attributedString attributesAtIndex:range.location
                                                               effectiveRange:nil]
                                       at:p];
        }];
        return _cellSize.width * attributedString.length;
    } else if (attributedString.length > 0) {
        CGFloat width = positions[attributedString.length - 1] + _cellSize.width;
        NSPoint offsetPoint = point;
        offsetPoint.y -= round((_cellSize.height - _cellSizeWithoutSpacing.height) / 2.0);
        [self drawTextOnlyAttributedString:attributedString atPoint:offsetPoint positions:positions width:width backgroundColor:backgroundColor];
        DLog(@"Return width of %d", (int)round(width));
        return width;
    } else {
        // attributedString is empty
        return 0;
    }
}

- (void)drawTextOnlyAttributedString:(NSAttributedString *)attributedString
                                atPoint:(NSPoint)origin
                           positions:(CGFloat *)stringPositions
                               width:(CGFloat)width
                     backgroundColor:(NSColor *)backgroundColor {
    DLog(@"Draw attributed string beginning at %d", (int)round(origin.x));
    NSDictionary *attributes = [attributedString attributesAtIndex:0 effectiveRange:nil];
    NSColor *color = attributes[NSForegroundColorAttributeName];

    BOOL bold = [attributes[iTermBoldAttribute] boolValue];
    BOOL fakeBold = [attributes[iTermFakeBoldAttribute] boolValue];
    BOOL fakeItalic = [attributes[iTermFakeItalicAttribute] boolValue];
    BOOL antiAlias = [attributes[iTermAntiAliasAttribute] boolValue];
    NSGraphicsContext *ctx = [NSGraphicsContext currentContext];

    [ctx saveGraphicsState];
    [ctx setCompositingOperation:NSCompositeSourceOver];

    // We used to use -[NSAttributedString drawWithRect:options] but
    // it does a lousy job rendering multiple combining marks. This is close
    // to what WebKit does and appears to be the highest quality text
    // rendering available.

    CTLineRef lineRef = CTLineCreateWithAttributedString((CFAttributedStringRef)attributedString);
    CFArrayRef runs = CTLineGetGlyphRuns(lineRef);
    CGContextRef cgContext = (CGContextRef) [ctx graphicsPort];
    CGContextSetShouldAntialias(cgContext, antiAlias);
    CGContextSetFillColorWithColor(cgContext, [self cgColorForColor:color]);
    CGContextSetStrokeColorWithColor(cgContext, [self cgColorForColor:color]);

    CGFloat c = 0.0;
    if (fakeItalic) {
        c = 0.2;
    }

    int savedFontSmoothingStyle = 0;
    BOOL useThinStrokes = [self thinStrokes] && ([backgroundColor brightnessComponent] < [color brightnessComponent]);
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
                                                         origin.x, ty);
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
            if (characterIndex != previousCharacterIndex && stringPositions[characterIndex] != cellOrigin) {
                positionOfFirstGlyphInCluster = positions[glyphIndex].x;
                cellOrigin = stringPositions[characterIndex];
            }
            positions[glyphIndex].x += cellOrigin - positionOfFirstGlyphInCluster;
        }

        CTFontRef runFont = CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);
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
    }
    CFRelease(lineRef);
    
    if (useThinStrokes) {
        CGContextSetFontSmoothingStyle(cgContext, savedFontSmoothingStyle);
    }

    [ctx restoreGraphicsState];
    

    [attributedString enumerateAttribute:NSUnderlineStyleAttributeName
                                 inRange:NSMakeRange(0, attributedString.length)
                                 options:0
                              usingBlock:^(NSNumber * _Nullable value, NSRange range, BOOL * _Nonnull stop) {
                                  if (value.integerValue) {
                                      NSDictionary *attributes = [attributedString attributesAtIndex:range.location effectiveRange:nil];
                                      NSColor *underline = [self.colorMap colorForKey:kColorMapUnderline];
                                      NSColor *color = (underline ? underline : attributes[NSForegroundColorAttributeName]);
                                      const CGFloat width = [attributes[iTermUnderlineLengthAttribute] intValue] * _cellSize.width;
                                      [self drawUnderlineOfColor:color
                                                    atCellOrigin:NSMakePoint(origin.x + stringPositions[range.location], origin.y)
                                                            font:attributes[NSFontAttributeName]
                                                           width:width];
                                  }
                              }];
}

static NSColor *iTermTextDrawingHelperGetTextColor(screen_char_t *c,
                                                   BOOL inUnderlinedRange,
                                                   int index,
                                                   iTermTextColorContext *context) {
    NSColor *rawColor = nil;
    BOOL isMatch = NO;
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
    } else if (inUnderlinedRange && !context->haveUnderlinedHostname) {
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

static BOOL iTermTextDrawingHelperIsCharacterDrawable(screen_char_t *c,
                                                      NSString *charAsString,
                                                      BOOL blinkingItemsVisible,
                                                      BOOL blinkAllowed) {
    const unichar code = c->code;
    if ((code == DWC_RIGHT ||
         code == DWC_SKIP ||
         code == TAB_FILLER) && !c->complexChar) {
        return NO;
    }
    if (blinkingItemsVisible || !(blinkAllowed && c->blink)) {
        // This char is either not blinking or during the "on" cycle of the
        // blink. It should be drawn.

        if (c->complexChar) {
            // TODO: Not all composed/surrogate pair grapheme clusters are drawable
            return charAsString != nil;
        } else {
            // Non-complex char
            // TODO: There are other spaces in unicode that should be supported.
            return (code != 0 &&
                    code != '\t' &&
                    !(code >= ITERM2_PRIVATE_BEGIN && code <= ITERM2_PRIVATE_END));

        }
    } else {
        // Chatacter hidden because of blinking.
        return NO;
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
    if ([previousImageAttributes[iTermImageColumnAttribute] integerValue] + 1 != [imageAttributes[iTermImageColumnAttribute] integerValue]) {
        return NO;
    }
    
    return YES;
}

- (void)getAttributesForCharacter:(screen_char_t *)c
                          atIndex:(NSInteger)i
                   forceTextColor:(NSColor *)forceTextColor
                   forceUnderline:(BOOL)inUnderlinedRange
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
        attributes->foregroundColor = iTermTextDrawingHelperGetTextColor(c,
                                                                         inUnderlinedRange,
                                                                         i,
                                                                         textColorContext);
    }

    const BOOL complex = c->complexChar;
    const unichar code = c->code;

    attributes->boxDrawing = !complex && [[iTermBoxDrawingBezierCurveFactory boxDrawingCharactersWithBezierPaths] characterIsMember:code];
    attributes->bold = c->bold;

    attributes->fakeBold = c->bold;  // default value
    attributes->fakeItalic = c->italic;  // default value
    PTYFontInfo *fontInfo = [_delegate drawingHelperFontForChar:code
                                                      isComplex:complex
                                                     renderBold:&attributes->fakeBold
                                                   renderItalic:&attributes->fakeItalic];

    attributes->font = fontInfo.font;
    attributes->ligatureLevel = fontInfo.ligatureLevel;
    attributes->underline = (c->underline || inUnderlinedRange);
    attributes->drawable = YES;
}

- (NSDictionary *)dictionaryForCharacterAttributes:(iTermCharacterAttributes *)attributes {
    return @{ (NSString *)kCTLigatureAttributeName: @(attributes->ligatureLevel),
              NSForegroundColorAttributeName: attributes->foregroundColor,
              NSFontAttributeName: attributes->font,
              iTermAntiAliasAttribute: @(attributes->shouldAntiAlias),
              iTermIsBoxDrawingAttribute: @(attributes->boxDrawing),
              iTermFakeBoldAttribute: @(attributes->fakeBold),
              iTermBoldAttribute: @(attributes->bold),
              iTermFakeItalicAttribute: @(attributes->fakeItalic),
              NSUnderlineStyleAttributeName: attributes->underline ? @(NSUnderlineStyleSingle) : @(NSUnderlineStyleNone) };
}

- (NSDictionary *)imageAttributesForCharacter:(screen_char_t *)c {
    if (c->image) {
        return @{ iTermImageCodeAttribute: @(c->code),
                  iTermImageColumnAttribute: @(c->foregroundColor),
                  iTermImageLineAttribute: @(c->backgroundColor) };
    } else {
        return nil;
    }
}

- (NSArray<NSAttributedString *> *)attributedStringsForLine:(screen_char_t *)line
                                                      range:(NSRange)indexRange
                                            hasSelectedText:(BOOL)hasSelectedText
                                            backgroundColor:(NSColor *)backgroundColor
                                             forceTextColor:(NSColor *)forceTextColor
                                                findMatches:(NSData *)findMatches
                                            underlinedRange:(NSRange)underlinedRange
                                                  positions:(CTVector(CGFloat) *)positions {
    NSMutableArray<NSAttributedString *> *attributedStrings = [NSMutableArray array];
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
        .haveUnderlinedHostname = _haveUnderlinedHostname,
        .previousForegroundColor = nil,
    };
    NSDictionary *previousImageAttributes = nil;
    iTermMutableAttributedStringBuilder *builder = [[[iTermMutableAttributedStringBuilder alloc] init] autorelease];
    iTermPreciseTimer buildTimer = { 0 };
    NSTimeInterval totalBuilderTime = 0;
    iTermCharacterAttributes characterAttributes = { 0 };
    iTermCharacterAttributes previousCharacterAttributes = { 0 };
    int segmentLength = 0;

    for (int i = indexRange.location; i < NSMaxRange(indexRange); i++) {
        iTermPreciseTimerStatsStartTimer(&_stats[TIMER_ATTRS_FOR_CHAR]);
        screen_char_t c = line[i];
        unichar code = c.code;
        BOOL complex = c.complexChar;

        NSString *charAsString;
        if (complex) {
            charAsString = ComplexCharToStr(c.code);
        } else {
            charAsString = nil;
        }
        
        const BOOL drawable = iTermTextDrawingHelperIsCharacterDrawable(&c,
                                                                        charAsString,
                                                                        _blinkingItemsVisible,
                                                                        _blinkAllowed);
        if (!drawable) {
            if (characterAttributes.drawable && c.code == DWC_RIGHT && !c.complexChar) {
                ++segmentLength;
            }
            characterAttributes.drawable = NO;
            continue;
        }
        [self getAttributesForCharacter:&c
                                atIndex:i
                         forceTextColor:forceTextColor
                         forceUnderline:NSLocationInRange(i, underlinedRange)
                       textColorContext:&textColorContext
                             attributes:&characterAttributes];

        iTermPreciseTimerStatsAccumulate(&_stats[TIMER_ATTRS_FOR_CHAR]);
        
        iTermPreciseTimerStatsStartTimer(&_stats[TIMER_SHOULD_SEGMENT]);

        NSDictionary *imageAttributes = [self imageAttributesForCharacter:&c];
        BOOL justSegmented = NO;
        BOOL combinedAttributesChanged;
        if ([self shouldSegmentWithAttributes:&characterAttributes
                              imageAttributes:imageAttributes
                           previousAttributes:&previousCharacterAttributes
                      previousImageAttributes:previousImageAttributes
                     combinedAttributesChanged:&combinedAttributesChanged]) {
            justSegmented = YES;
            
            iTermPreciseTimerStart(&buildTimer);
            NSMutableAttributedString *mutableAttributedString = builder.attributedString;
            if (previousCharacterAttributes.underline) {
                [mutableAttributedString addAttribute:iTermUnderlineLengthAttribute
                                                value:@(segmentLength)
                                                range:NSMakeRange(0, mutableAttributedString.length)];
            }
            segmentLength = 0;
            totalBuilderTime += iTermPreciseTimerMeasure(&buildTimer);
            [attributedStrings addObject:mutableAttributedString];
            builder = [[[iTermMutableAttributedStringBuilder alloc] init] autorelease];
        }
        ++segmentLength;
        memcpy(&previousCharacterAttributes, &characterAttributes, sizeof(previousCharacterAttributes));
        previousImageAttributes = [[imageAttributes copy] autorelease];
        iTermPreciseTimerStatsAccumulate(&_stats[TIMER_SHOULD_SEGMENT]);

        iTermPreciseTimerStatsStartTimer(&_stats[TIMER_UPDATE_BUILDER]);
        
        if (combinedAttributesChanged) {
            NSDictionary *combinedAttributes = [self dictionaryForCharacterAttributes:&characterAttributes];
            if (imageAttributes) {
                combinedAttributes = [combinedAttributes dictionaryByMergingDictionary:imageAttributes];
            }
            [builder setAttributes:combinedAttributes];
        }

        NSUInteger length;
        if (charAsString) {
            [builder appendString:charAsString];
            length = charAsString.length;
        } else {
            [builder appendCharacter:code];
            length = 1;
        }
        iTermPreciseTimerStatsAccumulate(&_stats[TIMER_UPDATE_BUILDER]);

        
        iTermPreciseTimerStatsStartTimer(&_stats[TIMER_ADVANCES]);
        // Append to positions.
        CGFloat offset = (i - indexRange.location) * _cellSize.width;
        for (NSUInteger j = 0; j < length; j++) {
            CTVectorAppend(positions, offset);
        }
        iTermPreciseTimerStatsAccumulate(&_stats[TIMER_ADVANCES]);
    }
    if (builder.length) {
        iTermPreciseTimerStart(&buildTimer);
        NSMutableAttributedString *mutableAttributedString = builder.attributedString;
        if (previousCharacterAttributes.underline) {
            [mutableAttributedString addAttribute:iTermUnderlineLengthAttribute
                                            value:@(segmentLength)
                                            range:NSMakeRange(0, mutableAttributedString.length)];
        }
        totalBuilderTime += iTermPreciseTimerMeasure(&buildTimer);
        [attributedStrings addObject:mutableAttributedString];
    }
    iTermPreciseTimerStatsRecord(&_stats[TIMER_STAT_BUILD_MUTABLE_ATTRIBUTED_STRING],
                                 totalBuilderTime);
    iTermPreciseTimerStatsRecordTimer(&_stats[TIMER_ATTRS_FOR_CHAR]);
    iTermPreciseTimerStatsRecordTimer(&_stats[TIMER_SHOULD_SEGMENT]);
    iTermPreciseTimerStatsRecordTimer(&_stats[TIMER_ADVANCES]);
    iTermPreciseTimerStatsRecordTimer(&_stats[TIMER_UPDATE_BUILDER]);
    
    return attributedStrings;
}

- (BOOL)useThinStrokes {
    switch (self.thinStrokes) {
        case iTermThinStrokesSettingAlways:
            return YES;

        case iTermThinStrokesSettingNever:
            return NO;
            
        case iTermThinStrokesSettingRetinaOnly:
            return _isRetina;
    }
}

- (void)drawUnderlineOfColor:(NSColor *)color
                atCellOrigin:(NSPoint)startPoint
                        font:(NSFont *)font
                       width:(CGFloat)runWidth {
    [color set];
    NSBezierPath *path = [NSBezierPath bezierPath];

    NSPoint origin = NSMakePoint(startPoint.x,
                                 startPoint.y + _cellSize.height + _underlineOffset);
    [path moveToPoint:origin];
    [path lineToPoint:NSMakePoint(origin.x + runWidth, origin.y)];
    [path setLineWidth:font.underlineThickness];
    [path stroke];
}

// origin is the first location onscreen
- (void)drawImageWithCode:(unichar)code
                   origin:(VT100GridCoord)origin
                   length:(NSInteger)length
                  atPoint:(NSPoint)point
            originInImage:(VT100GridCoord)originInImage {
    iTermImageInfo *imageInfo = GetImageInfo(code);
    NSImage *image = [imageInfo imageWithCellSize:_cellSize];
    NSSize chunkSize = NSMakeSize(image.size.width / imageInfo.size.width,
                                  image.size.height / imageInfo.size.height);

    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:point.x yBy:point.y + _cellSize.height];
    [transform scaleXBy:1.0 yBy:-1.0];
    [transform concat];
    
    NSColor *backgroundColor = [self defaultBackgroundColor];
    [backgroundColor set];
    NSRectFill(NSMakeRect(0, 0, _cellSize.width * length, _cellSize.height));
    if (imageInfo.animated) {
        [_delegate drawingHelperDidFindRunOfAnimatedCellsStartingAt:origin ofLength:length];
        _animated = YES;
    }
    [image drawInRect:NSMakeRect(0, 0, _cellSize.width * length, _cellSize.height)
             fromRect:NSMakeRect(chunkSize.width * originInImage.x,
                                 image.size.height - _cellSize.height - chunkSize.height * originInImage.y,
                                 chunkSize.width * length,
                                 chunkSize.height)
            operation:NSCompositeSourceOver
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
                            _useHFSPlusMapping,
                            self.unicodeVersion);
        int cursorX = 0;
        int baseX = floor(xStart * _cellSize.width + MARGIN);
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
            x = floor(xStart * _cellSize.width + MARGIN);
            y = (yStart + _numberOfLines - height) * _cellSize.height;
            i += charsInLine;
        }

        if (!foundCursor && i == cursorIndex) {
            if (justWrapped) {
                cursorX = MARGIN + width * _cellSize.width;
                cursorY = preWrapY;
            } else {
                cursorX = x;
                cursorY = y;
            }
        }
        const double kCursorWidth = 2.0;
        double rightMargin = MARGIN + _gridSize.width * _cellSize.width;
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

- (NSRect)cursorFrame {
    const int rowNumber = _cursorCoord.y + _numberOfLines - _gridSize.height;
    const CGFloat height = MIN(_cellSize.height, _cellSizeWithoutSpacing.height);
    return NSMakeRect(floor(_cursorCoord.x * _cellSize.width + MARGIN),
                      rowNumber * _cellSize.height + MAX(0, round((_cellSize.height - _cellSizeWithoutSpacing.height) / 2.0)),
                      MIN(_cellSize.width, _cellSizeWithoutSpacing.width),
                      height);
}

- (void)drawCursor {
    DLog(@"drawCursor");

    // Update the last time the cursor moved.
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!VT100GridCoordEquals(_cursorCoord, _oldCursorPosition)) {
        _lastTimeCursorMoved = now;
    }

    if ([self shouldDrawCursor]) {
        // Get the character that's under the cursor.
        screen_char_t *theLine = [self.delegate drawingHelperLineAtScreenIndex:_cursorCoord.y];
        BOOL isDoubleWidth;
        screen_char_t screenChar = [self charForCursorAtColumn:_cursorCoord.x
                                                        inLine:theLine
                                                   doubleWidth:&isDoubleWidth];

        // Update the "find cursor" view.
        [self.delegate drawingHelperUpdateFindCursorView];

        // Get the color of the cursor.
        NSColor *cursorColor;
        cursorColor = [self backgroundColorForCursor];
        NSRect rect = [self cursorFrame];
        if (isDoubleWidth) {
            rect.size.width *= 2;
        }
        iTermCursor *cursor = [iTermCursor cursorOfType:_cursorType];
        cursor.delegate = self;
        
        NSColor *cursorTextColor = [_delegate drawingHelperColorForCode:ALTSEM_CURSOR
                                                                  green:0
                                                                   blue:0
                                                              colorMode:ColorModeAlternate
                                                                   bold:NO
                                                                  faint:NO
                                                           isBackground:NO];

        [cursor drawWithRect:rect
                 doubleWidth:isDoubleWidth
                  screenChar:screenChar
             backgroundColor:cursorColor
             foregroundColor:cursorTextColor
                       smart:_useSmartCursorColor
                     focused:((_isInKeyWindow && _textViewIsActiveSession) || _shouldDrawFilledInCursor)
                       coord:_cursorCoord
                  cellHeight:_cellSize.height];
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
                        operation:NSCompositeSourceOver
                         fraction:1
                   respectFlipped:YES
                            hints:nil];
            }
        }
    }

    _oldCursorPosition = _cursorCoord;
    [_selectedFont release];
    _selectedFont = nil;
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
    if (_reverseVideo) {
        return [[_colorMap colorForKey:kColorMapCursorText] colorWithAlphaComponent:1.0];
    } else {
        return [[_colorMap colorForKey:kColorMapCursor] colorWithAlphaComponent:1.0];
    }
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
    DLog(@"shouldDrawCursor: hasMarkedText=%d, cursorVisible=%d, showCursor=%d, column=%d, row=%d, "
         @"width=%d, height=%d. Result=%@",
         (int)[self hasMarkedText], (int)_cursorVisible, (int)shouldShowCursor, column, row,
         width, height, @(result));
    return result;
}

#pragma mark - Coord/Rect Utilities

- (NSRange)rangeOfVisibleRows {
    int visibleRows = floor((_scrollViewContentSize.height - VMARGIN * 2) / _cellSize.height);
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
    return VT100GridCoordRangeMake(floor((rect.origin.x - MARGIN) / _cellSize.width),
                                   floor(rect.origin.y / _cellSize.height),
                                   ceil((NSMaxX(rect) - MARGIN) / _cellSize.width),
                                   ceil(NSMaxY(rect) / _cellSize.height));
}

- (NSRect)rectForCoordRange:(VT100GridCoordRange)coordRange {
    return NSMakeRect(coordRange.start.x * _cellSize.width + MARGIN,
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
    charRange.location = MAX(0, (x - MARGIN) / _cellSize.width);
    charRange.length = ceil((x + width - MARGIN) / _cellSize.width) - charRange.location;
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
}

- (void)startTiming {
    [_drawRectDuration startTimer];
    NSTimeInterval interval = [_drawRectInterval timeSinceTimerStarted];
    if ([_drawRectInterval haveStartedTimer]) {
        [_drawRectInterval addValue:interval];
    }
    [_drawRectInterval startTimer];
}

- (void)stopTiming {
    [_drawRectDuration addValue:[_drawRectDuration timeSinceTimerStarted]];
    NSLog(@"%p Moving average time draw rect is %04f, time between calls to drawRect is %04f",
          self, _drawRectDuration.value, _drawRectInterval.value);
}

#pragma mark - iTermCursorDelegate

- (iTermCursorNeighbors)cursorNeighbors {
    iTermCursorNeighbors neighbors;
    memset(&neighbors, 0, sizeof(neighbors));
    NSArray *coords = @[ @[ @0,    @(-1) ],     // Above
                         @[ @(-1), @0    ],     // Left
                         @[ @1,    @0    ],     // Right
                         @[ @0,    @1    ] ];   // Below
    int prevY = -2;
    screen_char_t *theLine = nil;

    for (NSArray *tuple in coords) {
        int dx = [tuple[0] intValue];
        int dy = [tuple[1] intValue];
        int x = _cursorCoord.x + dx;
        int y = _cursorCoord.y + dy;

        if (y != prevY) {
            if (y >= 0 && y < _gridSize.height) {
                theLine = [_delegate drawingHelperLineAtScreenIndex:y];
            } else {
                theLine = nil;
            }
        }
        prevY = y;

        int xi = dx + 1;
        int yi = dy + 1;
        if (theLine && x >= 0 && x < _gridSize.width) {
            neighbors.chars[yi][xi] = theLine[x];
            neighbors.valid[yi][xi] = YES;
        }

    }
    return neighbors;
}

- (void)cursorDrawCharacterAt:(VT100GridCoord)coord
                overrideColor:(NSColor *)overrideColor
                      context:(CGContextRef)ctx
              backgroundColor:(NSColor *)backgroundColor {
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [context saveGraphicsState];

    int row = coord.y + _numberOfScrollbackLines;
    VT100GridCoordRange coordRange = VT100GridCoordRangeMake(coord.x, row, coord.x + 1, row + 1);
    NSRect innerRect = [self rectForCoordRange:coordRange];
    NSRectClip(innerRect);

    screen_char_t *line = [self.delegate drawingHelperLineAtIndex:row];
    [self constructAndDrawRunsForLine:line
                                  row:row
                              inRange:NSMakeRange(0, _gridSize.width)
                      startingAtPoint:NSMakePoint(MARGIN, row * _cellSize.height)
                           bgselected:NO
                              bgColor:backgroundColor
             processedBackgroundColor:backgroundColor
                              matches:nil
                       forceTextColor:overrideColor
                              context:ctx];
    
    [context restoreGraphicsState];
}

- (NSColor *)cursorColorForCharacter:(screen_char_t)screenChar
                      wantBackground:(BOOL)wantBackgroundColor
                               muted:(BOOL)muted {
    BOOL isBackground = wantBackgroundColor;

    if (_reverseVideo) {
        if (wantBackgroundColor &&
            screenChar.backgroundColorMode == ColorModeAlternate &&
            screenChar.backgroundColor == ALTSEM_DEFAULT) {
            isBackground = NO;
        } else if (!wantBackgroundColor &&
                   screenChar.foregroundColorMode == ColorModeAlternate &&
                   screenChar.foregroundColor == ALTSEM_DEFAULT) {
            isBackground = YES;
        }
    }
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

@end
