//
//  iTermTextDrawingHelper.m
//  iTerm2
//
//  Created by George Nachman on 3/9/15.
//
//

#import "iTermTextDrawingHelper.h"

#import "CharacterRun.h"
#import "CharacterRunInline.h"
#import "charmaps.h"
#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermBackgroundColorRun.h"
#import "iTermColorMap.h"
#import "iTermController.h"
#import "iTermFindCursorView.h"
#import "iTermImageInfo.h"
#import "iTermIndicatorsHelper.h"
#import "iTermSelection.h"
#import "iTermTextExtractor.h"
#import "MovingAverage.h"
#import "NSColor+iTerm.h"
#import "NSStringITerm.h"
#import "RegexKitLite.h"
#import "VT100ScreenMark.h"
#import "VT100Terminal.h"  // TODO: Remove this dependency

static const int kBadgeMargin = 4;

extern void CGContextSetFontSmoothingStyle(CGContextRef, int);
extern int CGContextGetFontSmoothingStyle(CGContextRef);

@interface iTermTextDrawingHelper() <iTermCursorDelegate>
@end

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
    DLog(@"drawRect:%@ in view %@", [NSValue valueWithRect:rect], _delegate);
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

    for (int i = 0; i < rectCount; i++) {
        DLog(@"drawRect - draw sub rectangle %@", [NSValue valueWithRect:rectArray[i]]);
        [self clipAndDrawRect:rectArray[i]];
    }
    [self drawCursor];

    if (_showDropTargets) {
        [self drawDropTargets];
    }

    if (_drawRectDuration) {
        [self stopTiming];
    }
}

- (void)clipAndDrawRect:(NSRect)rect {
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [context saveGraphicsState];

    // Compute the coordinate range.
    VT100GridCoordRange coordRange = [self coordRangeForRect:rect];

    // Clip to the area that needs to be drawn. We re-create the rect from the coord range to ensure
    // it falls on the boundary of the cells.
    NSRect innerRect = [self rectForCoordRange:coordRange];
    NSRectClip(innerRect);

    // Draw an extra ring of characters outside it.
    NSRect outerRect = [self rectByGrowingRectByOneCell:innerRect];
    [self drawOneRect:outerRect];

    [context restoreGraphicsState];

    if (_debug) {
      NSColor *c = [NSColor colorWithCalibratedRed:(rand() % 255) / 255.0
                                             green:(rand() % 255) / 255.0
                                              blue:(rand() % 255) / 255.0
                                             alpha:1];
      [c set];
      NSFrameRect(rect);
    }
}

- (void)drawOneRect:(NSRect)rect {
    // The range of chars in the line that need to be drawn.
    VT100GridCoordRange coordRange = [self drawableCoordRangeForRect:rect];

    const double curLineWidth = _gridSize.width * _cellSize.width;
    if (_cellSize.height <= 0 || curLineWidth <= 0) {
        DLog(@"height or width too small");
        return;
    }

    // Configure graphics
    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositeCopy];

    iTermTextExtractor *extractor = [self.delegate drawingHelperTextExtractor];
    _blinkingFound = NO;

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
    NSRange charRange = NSMakeRange(coordRange.start.x, coordRange.end.x - coordRange.start.x);
    double y = coordRange.start.y * _cellSize.height;
    // An array of PTYTextViewBackgroundRunArray objects (one element per line).
    NSMutableArray *backgroundRunArrays = [NSMutableArray array];
    for (int line = coordRange.start.y; line < coordRange.end.y; line++, y += _cellSize.height) {
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
        [self.delegate drawingHelperDrawBackgroundImageInRect:rect
                                       blendDefaultBackground:NO];
    }

    // Now iterate over the lines and paint the backgrounds.
    for (iTermBackgroundColorRunsInLine *runArray in backgroundRunArrays) {
        [self drawBackgroundForLine:runArray.line
                                atY:runArray.y
                               runs:runArray.array];
        [self drawMarginsAndMarkForLine:runArray.line y:runArray.y];
    }

    // Draw other background-like stuff that goes behind text.
    [self drawAccessoriesInRect:rect coordRange:coordRange];

    // Now iterate over the lines and paint the characters.
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    for (iTermBackgroundColorRunsInLine *runArray in backgroundRunArrays) {
        [self drawCharactersForLine:runArray.line
                                atY:runArray.y
                     backgroundRuns:runArray.array
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

    // The OS may ask us to draw an area outside the visible area, but that looks awful so cover it
    // up by drawing some background over it.
    [self drawExcessAtLine:coordRange.end.y];
    [self drawTopMargin];

    // If the IME is in use, draw its contents over top of the "real" screen
    // contents.
    [self drawInputMethodEditorTextAt:_cursorCoord.x
                                    y:_cursorCoord.y
                                width:_gridSize.width
                               height:_gridSize.height
                         cursorHeight:_cellSize.height
                                  ctx:ctx];
    _blinkingFound |= self.cursorBlinking;
    
    [_selectedFont release];
    _selectedFont = nil;
}

#pragma mark - Drawing: Background

- (void)drawBackgroundForLine:(int)line
                          atY:(CGFloat)yOrigin
                         runs:(NSArray *)runs {
    for (iTermBoxedBackgroundColorRun *box in runs) {
        iTermBackgroundColorRun *run = box.valuePointer;
        NSRect rect = NSMakeRect(floor(MARGIN + run->range.location * _cellSize.width),
                                 yOrigin,
                                 ceil(run->range.length * _cellSize.width),
                                 _cellSize.height);
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
    NSRectFillUsingOperation(rect, NSCompositeSourceOver);
}

#pragma mark - Drawing: Accessories

- (void)drawAccessoriesInRect:(NSRect)bgRect coordRange:(VT100GridCoordRange)coordRange {
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
        const CGFloat verticalSpacing = _cellSize.height - _cellSizeWithoutSpacing.height;
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

        if (mark.code) {
            [[NSColor colorWithCalibratedRed:248.0 / 255.0 green:90.0 / 255.0 blue:90.0 / 255.0 alpha:1] set];
        } else {
            [[NSColor colorWithCalibratedRed:120.0 / 255.0 green:178.0 / 255.0 blue:255.0 / 255.0 alpha:1] set];
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
    NSSize size = [widest sizeWithAttributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:10] }];
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
        attributes = @{ NSFontAttributeName: [NSFont userFixedPitchFontOfSize:10],
                        NSForegroundColorAttributeName: fgColor,
                        NSShadowAttributeName: shadow };
    } else {
        NSFont *font = [NSFont userFixedPitchFontOfSize:10];    
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
               backgroundRuns:(NSArray *)backgroundRuns
                      context:(CGContextRef)ctx {
    screen_char_t* theLine = [self.delegate drawingHelperLineAtIndex:line];
    NSData *matches = [_delegate drawingHelperMatchesOnLine:line];
    for (iTermBoxedBackgroundColorRun *box in backgroundRuns) {
        iTermBackgroundColorRun *run = box.valuePointer;
        NSPoint textOrigin = NSMakePoint(MARGIN + run->range.location * _cellSize.width, y);

        [self constructAndDrawRunsForLine:theLine
                                      row:line
                                  inRange:run->range
                          startingAtPoint:textOrigin
                               bgselected:run->selected
                                  bgColor:box.unprocessedBackgroundColor
                                  matches:matches
                                  context:ctx];
    }
}

- (void)constructAndDrawRunsForLine:(screen_char_t *)theLine
                                row:(int)row
                            inRange:(NSRange)indexRange
                    startingAtPoint:(NSPoint)initialPoint
                         bgselected:(BOOL)bgselected
                            bgColor:(NSColor*)bgColor
                            matches:(NSData*)matches
                            context:(CGContextRef)ctx {
    const int width = _gridSize.width;
    CRunStorage *storage = [CRunStorage cRunStorageWithCapacity:width];
    CRun *run = [self constructTextRuns:theLine
                                    row:row
                               selected:bgselected
                             indexRange:indexRange
                        backgroundColor:bgColor
                                matches:matches
                                storage:storage];

    if (run) {
        [self drawRunsAt:initialPoint run:run storage:storage context:ctx];
        CRunFree(run);
    }
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

- (void)drawRunsAt:(NSPoint)initialPoint
               run:(CRun *)run
           storage:(CRunStorage *)storage
           context:(CGContextRef)ctx {
    int savedFontSmoothingStyle = 0;
    BOOL useThinStrokes = [self useThinStrokes];
    if (useThinStrokes) {
        // This seems to be available at least on 10.8 and later. The only reference to it is in
        // WebKit. This causes text to render just a little lighter, which looks nicer.
        savedFontSmoothingStyle = CGContextGetFontSmoothingStyle(ctx);
        CGContextSetFontSmoothingStyle(ctx, 16);
    }

    CGContextSetTextDrawingMode(ctx, kCGTextFill);
    while (run) {
        [self drawRun:run ctx:ctx initialPoint:initialPoint storage:storage];
        run = run->next;
    }

    if (useThinStrokes) {
        CGContextSetFontSmoothingStyle(ctx, savedFontSmoothingStyle);
    }
}

- (void)drawRun:(CRun *)currentRun
            ctx:(CGContextRef)ctx
   initialPoint:(NSPoint)initialPoint
        storage:(CRunStorage *)storage {
    NSPoint startPoint = NSMakePoint(initialPoint.x + currentRun->x, initialPoint.y);
    CGContextSetShouldAntialias(ctx, currentRun->attrs.antiAlias);

    // If there is an underline, save some values before the run gets chopped up.
    CGFloat runWidth = 0;
    int length = currentRun->string ? 1 : currentRun->length;
    NSSize *advances = nil;
    if (currentRun->attrs.underline) {
        advances = CRunGetAdvances(currentRun);
        for (int i = 0; i < length; i++) {
            runWidth += advances[i].width;
        }
    }

    if (!currentRun->string) {
        // Non-complex, except for glyphs we can't find.
        while (currentRun->length) {
            int firstComplexGlyph = [self drawSimpleRun:currentRun
                                                    ctx:ctx
                                           initialPoint:initialPoint];
            if (firstComplexGlyph < 0) {
                break;
            }
            CRun *complexRun = CRunSplit(currentRun, firstComplexGlyph);
            [self drawComplexRun:complexRun
                              at:NSMakePoint(initialPoint.x + complexRun->x, initialPoint.y)];
            CRunFree(complexRun);
        }
    } else {
        // Complex
        [self drawComplexRun:currentRun
                          at:NSMakePoint(initialPoint.x + currentRun->x, initialPoint.y)];
    }

    // Leaving anti-aliasing off causes the underline to be too thick (issue 4438).
    CGContextSetShouldAntialias(ctx, YES);

    // Draw underline
    if (currentRun->attrs.underline) {
        [self drawUnderlineOfColor:currentRun->attrs.color
                      atCellOrigin:startPoint
                              font:currentRun->attrs.fontInfo.font
                             width:runWidth];
    }
}

- (void)drawUnderlineOfColor:(NSColor *)color
                atCellOrigin:(NSPoint)startPoint
                        font:(NSFont *)font
                       width:(CGFloat)runWidth {
    [color set];
    NSBezierPath *path = [NSBezierPath bezierPath];

    NSPoint origin = NSMakePoint(startPoint.x,
                                 startPoint.y +
                                     _cellSize.height +
                                     font.descender -
                                     font.underlinePosition);
    [path moveToPoint:origin];
    [path lineToPoint:NSMakePoint(origin.x + runWidth, origin.y)];
    [path setLineWidth:font.underlineThickness];
    [path stroke];
}

// Note: caller must nil out _selectedFont after the graphics context becomes invalid.
- (int)drawSimpleRun:(CRun *)currentRun
                 ctx:(CGContextRef)ctx
        initialPoint:(NSPoint)initialPoint {
    int firstMissingGlyph;
    CGGlyph *glyphs = CRunGetGlyphs(currentRun, &firstMissingGlyph);
    if (!glyphs) {
        return -1;
    }

    size_t numCodes = currentRun->length;
    size_t length = numCodes;
    if (firstMissingGlyph >= 0) {
        length = firstMissingGlyph;
    }
    [self selectFont:currentRun->attrs.fontInfo.font inContext:ctx];
    CGContextSetFillColorSpace(ctx, [[currentRun->attrs.color colorSpace] CGColorSpace]);
    int componentCount = [currentRun->attrs.color numberOfComponents];

    CGFloat components[componentCount];
    [currentRun->attrs.color getComponents:components];
    CGContextSetFillColor(ctx, components);

    double y = initialPoint.y + _cellSize.height + currentRun->attrs.fontInfo.baselineOffset;
    int x = initialPoint.x + currentRun->x;
    // Flip vertically and translate to (x, y).
    CGFloat m21 = 0.0;
    if (currentRun->attrs.fakeItalic) {
        m21 = 0.2;
    }
    CGContextSetTextMatrix(ctx, CGAffineTransformMake(1.0,  0.0,
                                                      m21, -1.0,
                                                      x, y));

    void *advances = CRunGetAdvances(currentRun);
    CGContextShowGlyphsWithAdvances(ctx, glyphs, advances, length);

    if (currentRun->attrs.fakeBold) {
        // If anti-aliased, drawing twice at the same position makes the strokes thicker.
        // If not anti-alised, draw one pixel to the right.
        CGContextSetTextMatrix(ctx, CGAffineTransformMake(1.0,  0.0,
                                                          m21, -1.0,
                                                          x + (currentRun->attrs.antiAlias ? _antiAliasedShift : 1),
                                                          y));

        CGContextShowGlyphsWithAdvances(ctx, glyphs, advances, length);
    }
    return firstMissingGlyph;
}

- (void)drawImageCellInRun:(CRun *)run atPoint:(NSPoint)point {
    iTermImageInfo *imageInfo = GetImageInfo(run->attrs.imageCode);
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
    NSRectFill(NSMakeRect(0, 0, _cellSize.width * run->numImageCells, _cellSize.height));
    if (imageInfo.animated) {
        [_delegate drawingHelperDidFindRunOfAnimatedCellsStartingAt:run->coord ofLength:run->numImageCells];
        _animated = YES;
    }
    [image drawInRect:NSMakeRect(0, 0, _cellSize.width * run->numImageCells, _cellSize.height)
             fromRect:NSMakeRect(chunkSize.width * run->attrs.imageColumn,
                                 image.size.height - _cellSize.height - chunkSize.height * run->attrs.imageLine,
                                 chunkSize.width * run->numImageCells,
                                 chunkSize.height)
            operation:NSCompositeSourceOver
             fraction:1];
    [NSGraphicsContext restoreGraphicsState];
}

- (BOOL)complexRunIsBoxDrawingCell:(CRun *)complexRun {
    switch (complexRun->key) {
        case ITERM_BOX_DRAWINGS_LIGHT_UP_AND_LEFT:
        case ITERM_BOX_DRAWINGS_LIGHT_DOWN_AND_LEFT:
        case ITERM_BOX_DRAWINGS_LIGHT_DOWN_AND_RIGHT:
        case ITERM_BOX_DRAWINGS_LIGHT_UP_AND_RIGHT:
        case ITERM_BOX_DRAWINGS_LIGHT_VERTICAL_AND_HORIZONTAL:
        case ITERM_BOX_DRAWINGS_LIGHT_HORIZONTAL:
        case ITERM_BOX_DRAWINGS_LIGHT_VERTICAL_AND_RIGHT:
        case ITERM_BOX_DRAWINGS_LIGHT_VERTICAL_AND_LEFT:
        case ITERM_BOX_DRAWINGS_LIGHT_UP_AND_HORIZONTAL:
        case ITERM_BOX_DRAWINGS_LIGHT_DOWN_AND_HORIZONTAL:
        case ITERM_BOX_DRAWINGS_LIGHT_VERTICAL:
            return YES;
        default:
            return NO;
    }
}

- (void)drawBoxDrawingCellInRun:(CRun *)complexRun at:(NSPoint)pos {
    NSBezierPath *path = [self bezierPathForBoxDrawingCode:complexRun->key];
    NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
    [ctx saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:pos.x yBy:pos.y];
    [transform concat];
    [complexRun->attrs.color set];
    [path stroke];
    [ctx restoreGraphicsState];
}

- (NSAttributedString *)attributedStringForComplexRun:(CRun *)complexRun {
    PTYFontInfo *fontInfo = complexRun->attrs.fontInfo;
    NSColor *color = complexRun->attrs.color;
    NSString *str = complexRun->string;
    NSDictionary *attrs = @{ NSFontAttributeName: fontInfo.font,
                             NSForegroundColorAttributeName: color };

    return [[[NSAttributedString alloc] initWithString:str
                                            attributes:attrs] autorelease];
}

- (void)drawStringWithCombiningMarksInRun:(CRun *)complexRun at:(NSPoint)pos {
    PTYFontInfo *fontInfo = complexRun->attrs.fontInfo;
    BOOL fakeBold = complexRun->attrs.fakeBold;
    BOOL fakeItalic = complexRun->attrs.fakeItalic;
    BOOL antiAlias = complexRun->attrs.antiAlias;

    NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
    NSColor *color = complexRun->attrs.color;

    [ctx saveGraphicsState];
    [ctx setCompositingOperation:NSCompositeSourceOver];

    // This renders characters with combining marks better but is slower.
    NSAttributedString *attributedString = [self attributedStringForComplexRun:complexRun];

    // We used to use -[NSAttributedString drawWithRect:options] but
    // it does a lousy job rendering multiple combining marks. This is close
    // to what WebKit does and appears to be the highest quality text
    // rendering available.

    CTLineRef lineRef = CTLineCreateWithAttributedString((CFAttributedStringRef)attributedString);
    CFArrayRef runs = CTLineGetGlyphRuns(lineRef);
    CGContextRef cgContext = (CGContextRef) [ctx graphicsPort];
    CGContextSetFillColorWithColor(cgContext, [self cgColorForColor:color]);
    CGContextSetStrokeColorWithColor(cgContext, [self cgColorForColor:color]);

    CGFloat c = 0.0;
    if (fakeItalic) {
        c = 0.2;
    }

    const CGFloat ty = pos.y + fontInfo.baselineOffset + _cellSize.height;
    CGAffineTransform textMatrix = CGAffineTransformMake(1.0,  0.0,
                                                         c, -1.0,
                                                         pos.x, ty);
    CGContextSetTextMatrix(cgContext, textMatrix);

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
        const CGPoint *positions = CTRunGetPositionsPtr(run);
        if (!positions) {
            NSMutableData *tempBuffer =
                [[[NSMutableData alloc] initWithLength:sizeof(CGPoint) * length] autorelease];
            CTRunGetPositions(run, CFRangeMake(0, length), (CGPoint *)tempBuffer.mutableBytes);
            positions = tempBuffer.mutableBytes;
        }
        CTFontRef runFont = CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);
        CTFontDrawGlyphs(runFont, buffer, (NSPoint *)positions, length, cgContext);

        if (fakeBold) {
            CGContextTranslateCTM(cgContext, antiAlias ? _antiAliasedShift : 1, 0);
            CTFontDrawGlyphs(runFont, buffer, (NSPoint *)positions, length, cgContext);
            CGContextTranslateCTM(cgContext, antiAlias ? -_antiAliasedShift : -1, 0);
        }
    }
    CFRelease(lineRef);
    [ctx restoreGraphicsState];
}

// TODO: Support fake italic
- (void)drawAttributedStringInRun:(CRun *)complexRun at:(NSPoint)pos {
    PTYFontInfo *fontInfo = complexRun->attrs.fontInfo;
    BOOL fakeBold = complexRun->attrs.fakeBold;
    BOOL antiAlias = complexRun->attrs.antiAlias;

    NSGraphicsContext *ctx = [NSGraphicsContext currentContext];

    [ctx saveGraphicsState];
    [ctx setCompositingOperation:NSCompositeSourceOver];

    CGFloat width = CRunGetAdvances(complexRun)[0].width;
    NSAttributedString* attributedString = [self attributedStringForComplexRun:complexRun];

    // Note that drawInRect doesn't use the right baseline, but drawWithRect
    // does.
    //
    // This comment is mostly out-of-date, as this function is now used only
    // for surrogate pairs, and is ripe for deletion.
    //
    // This technique was picked because it can find glyphs that aren't in the
    // selected font (e.g., tests/radical.txt). It doesn't draw combining marks
    // as well as CTFontDrawGlyphs (though they are generally passable).  It
    // fails badly in two known cases:
    // 1. Enclosing marks (q in a circle shows as a q)
    // 2. U+239d, a part of a paren for graphics drawing, doesn't quite render
    //    right (though it appears to need to render in another char's cell).
    // Other rejected approaches included using CTFontGetGlyphsForCharacters+
    // CGContextShowGlyphsWithAdvances, which doesn't render thai characters
    // correctly in UTF-8-demo.txt.
    //
    // We use width*2 so that wide characters that are not double width chars
    // render properly. These are font-dependent. See tests/suits.txt for an
    // example.
    [attributedString drawWithRect:NSMakeRect(pos.x,
                                              pos.y + fontInfo.baselineOffset + _cellSize.height,
                                              width * 2,
                                              _cellSize.height)
                           options:0];
    if (fakeBold) {
        // If anti-aliased, drawing twice at the same position makes the strokes thicker.
        // If not anti-alised, draw one pixel to the right.
        [attributedString drawWithRect:NSMakeRect(pos.x + (antiAlias ? 0 : 1),
                                                  pos.y + fontInfo.baselineOffset + _cellSize.height,
                                                  width*2,
                                                  _cellSize.height)
                               options:0];
    }

    [ctx restoreGraphicsState];
}

- (void)drawComplexRun:(CRun *)complexRun at:(NSPoint)pos {
    if (complexRun->attrs.imageCode > 0) {
        // Handle cells that are part of an image.
        [self drawImageCellInRun:complexRun atPoint:pos];
    } else if ([self complexRunIsBoxDrawingCell:complexRun]) {
        // Special box-drawing cells don't use the font so they look prettier.
        [self drawBoxDrawingCellInRun:complexRun at:pos];
    } else if (StringContainsCombiningMark(complexRun->string)) {
        // High-quality but slow rendering, needed especially for multiple combining marks.
        [self drawStringWithCombiningMarksInRun:complexRun at:pos];
    } else {
        // Faster (not fast, but faster) than drawStringWithCombiningMarksInRun. This is used for
        // surrogate pairs and when drawing a simple run fails because a glyph couldn't be found.
        [self drawAttributedStringInRun:complexRun at:pos];
    }
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
                            _useHFSPlusMapping);
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
            CRunStorage *storage = [CRunStorage cRunStorageWithCapacity:charsInLine];
            CRun *run = [self constructTextRuns:buf
                                            row:y
                                       selected:NO
                                     indexRange:NSMakeRange(i, charsInLine)
                                backgroundColor:nil
                                        matches:nil
                                        storage:storage];
            if (run) {
                [self drawRunsAt:NSMakePoint(x, y) run:run storage:storage context:ctx];

                // Draw an underline.
                [self drawUnderlineOfColor:[self defaultTextColor]
                              atCellOrigin:NSMakePoint(x, y)
                                      font:run->attrs.fontInfo.font
                                     width:charsInLine * _cellSize.width];
                CRunFree(run);
            }

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
                                        cursorY,
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
    return NSMakeRect(floor(_cursorCoord.x * _cellSize.width + MARGIN),
                      rowNumber * _cellSize.height + (_cellSize.height - _cellSizeWithoutSpacing.height),
                      MIN(_cellSize.width, _cellSizeWithoutSpacing.width),
                      _cellSizeWithoutSpacing.height);
}

- (void)drawCursor {
    DLog(@"drawCursor");

    if (![self cursorInVisibleRow]) {
        return;
    }

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
        [cursor drawWithRect:rect
                 doubleWidth:isDoubleWidth
                  screenChar:screenChar
             backgroundColor:cursorColor
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

- (CRun *)constructTextRuns:(screen_char_t *)theLine
                        row:(int)row
                   selected:(BOOL)bgselected
                 indexRange:(NSRange)indexRange
            backgroundColor:(NSColor *)bgColor
                    matches:(NSData *)matches
                    storage:(CRunStorage *)storage {
    const int width = _gridSize.width;
    iTermColorMap *colorMap = self.colorMap;
    BOOL inUnderlinedRange = NO;
    CRun *firstRun = NULL;
    CAttrs attrs = { 0 };
    CRun *currentRun = NULL;
    const char* matchBytes = [matches bytes];
    int lastForegroundColor = -1;
    int lastFgGreen = -1;
    int lastFgBlue = -1;
    int lastForegroundColorMode = -1;
    int lastBold = 2;  // Bold is a one-bit field so it can never equal 2.
    int lastFaint = 2;  // Same for faint
    NSColor *lastColor = nil;
    CGFloat curX = 0;
    NSRange underlinedRange = [self underlinedRangeOnLine:row];
    const int underlineStartsAt = underlinedRange.location;
    const int underlineEndsAt = NSMaxRange(underlinedRange);
    const CGFloat dimmingAmount = colorMap.dimmingAmount;
    const CGFloat mutingAmount = colorMap.mutingAmount;
    const double minimumContrast = _minimumContrast;
    NSColor *lastUnprocessedColor = nil;
    NSColor *lastProcessedColor = nil;

    for (int i = indexRange.location; i < indexRange.location + indexRange.length; i++) {
        inUnderlinedRange = (i >= underlineStartsAt && i < underlineEndsAt);
        if (theLine[i].code == DWC_RIGHT) {
            if (i == indexRange.location) {
                // If the run begins with a DWC_RIGHT then we must advance curX since it won't have
                // been advanced by the drawable part of the character. This can happen because
                // the drawable rect can begin at any cell.
                curX += _cellSize.width;
            }
            continue;
        }

        BOOL doubleWidth = i < width - 1 && (theLine[i + 1].code == DWC_RIGHT);
        unichar thisCharUnichar = 0;
        NSString* thisCharString = nil;
        CGFloat thisCharAdvance;

        if (!_useNonAsciiFont || (theLine[i].code < 128 && !theLine[i].complexChar)) {
            attrs.antiAlias = _asciiAntiAlias;
        } else {
            attrs.antiAlias = _nonAsciiAntiAlias;
        }
        BOOL isSelection = NO;

        // Figure out the color for this char.
        if (bgselected) {
            // Is a selection.
            isSelection = YES;
            // NOTE: This could be optimized by caching the color.
            CRunAttrsSetColor(&attrs, storage, [colorMap colorForKey:kColorMapSelectedText]);
        } else {
            // Not a selection.
            if (_reverseVideo &&
                ((theLine[i].foregroundColor == ALTSEM_DEFAULT &&
                  theLine[i].foregroundColorMode == ColorModeAlternate) ||
                 (theLine[i].foregroundColor == ALTSEM_CURSOR &&
                  theLine[i].foregroundColorMode == ColorModeAlternate))) {
                // Reverse video is on. Either is cursor or has default foreground color. Use
                // background color.
                CRunAttrsSetColor(&attrs, storage,
                                  [colorMap colorForKey:kColorMapBackground]);
            } else {
                if (theLine[i].foregroundColor == lastForegroundColor &&
                    theLine[i].fgGreen == lastFgGreen &&
                    theLine[i].fgBlue == lastFgBlue &&
                    theLine[i].foregroundColorMode == lastForegroundColorMode &&
                    theLine[i].bold == lastBold &&
                    theLine[i].faint == lastFaint) {
                    // Looking up colors with -drawingHelperColorForCode:... is expensive and it's common to
                    // have consecutive characters with the same color.
                    CRunAttrsSetColor(&attrs, storage, lastColor);
                } else {
                    // Not reversed or not subject to reversing (only default
                    // foreground color is drawn in reverse video).
                    lastForegroundColor = theLine[i].foregroundColor;
                    lastFgGreen = theLine[i].fgGreen;
                    lastFgBlue = theLine[i].fgBlue;
                    lastForegroundColorMode = theLine[i].foregroundColorMode;
                    lastBold = theLine[i].bold;
                    lastFaint = theLine[i].faint;
                    CRunAttrsSetColor(&attrs,
                                      storage,
                                      [_delegate drawingHelperColorForCode:theLine[i].foregroundColor
                                                                     green:theLine[i].fgGreen
                                                                      blue:theLine[i].fgBlue
                                                                 colorMode:theLine[i].foregroundColorMode
                                                                      bold:theLine[i].bold
                                                                     faint:theLine[i].faint
                                                              isBackground:NO]);
                    lastColor = attrs.color;
                }
            }
        }

        if (matches && !isSelection) {
            // Test if this is a highlighted match from a find.
            int theIndex = i / 8;
            int mask = 1 << (i & 7);
            if (theIndex < [matches length] && matchBytes[theIndex] & mask) {
                CRunAttrsSetColor(&attrs,
                                  storage,
                                  [NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:1]);
            }
        }

        if (bgColor && (minimumContrast > 0.001 ||
                        dimmingAmount > 0.001 ||
                        mutingAmount > 0.001 ||
                        theLine[i].faint)) {  // faint implies alpha<1 and is faster than getting the alpha component
            NSColor *processedColor;
            if (attrs.color == lastUnprocessedColor) {
                processedColor = lastProcessedColor;
            } else {
                processedColor = [colorMap processedTextColorForTextColor:attrs.color
                                                      overBackgroundColor:bgColor];
                lastUnprocessedColor = attrs.color;
                lastProcessedColor = processedColor;
            }
            
            CRunAttrsSetColor(&attrs,
                              storage,
                              processedColor);
        }

        BOOL drawable;
        if (_blinkingItemsVisible || !(_blinkAllowed && theLine[i].blink)) {
            // This char is either not blinking or during the "on" cycle of the
            // blink. It should be drawn.

            // Set the character type and its unichar/string.
            if (theLine[i].complexChar) {
                thisCharString = ComplexCharToStr(theLine[i].code);
                if (!thisCharString) {
                    // A bug that's happened more than once is that code gets
                    // set to 0 but complexChar is left set to true.
                    NSLog(@"No complex char for code %d", (int)theLine[i].code);
                    thisCharString = @"";
                    drawable = NO;
                } else {
                    drawable = YES;  // TODO: not all unicode is drawable
                }
            } else {
                thisCharString = nil;
                // Non-complex char
                // TODO: There are other spaces in unicode that should be supported.
                drawable = (theLine[i].code != 0 &&
                            theLine[i].code != '\t' &&
                            !(theLine[i].code >= ITERM2_PRIVATE_BEGIN &&
                              theLine[i].code <= ITERM2_PRIVATE_END));

                if (drawable) {
                    thisCharUnichar = theLine[i].code;
                }
            }
        } else {
            // Chatacter hidden because of blinking.
            drawable = NO;
        }

        // Set all other common attributes.
        if (doubleWidth) {
            thisCharAdvance = _cellSize.width * 2;
        } else {
            thisCharAdvance = _cellSize.width;
        }

        if (drawable) {
            BOOL fakeBold = theLine[i].bold;
            BOOL fakeItalic = theLine[i].italic;
            attrs.fontInfo = [_delegate drawingHelperFontForChar:theLine[i].code
                                                       isComplex:theLine[i].complexChar
                                                      renderBold:&fakeBold
                                                    renderItalic:&fakeItalic];
            attrs.fakeBold = fakeBold;
            attrs.fakeItalic = fakeItalic;
            attrs.underline = theLine[i].underline || inUnderlinedRange;
            attrs.imageCode = theLine[i].image ? theLine[i].code : 0;
            attrs.imageColumn = theLine[i].foregroundColor;
            attrs.imageLine = theLine[i].backgroundColor;
            if (theLine[i].image) {
                thisCharString = @"I";
            }
            if (inUnderlinedRange && !_haveUnderlinedHostname) {
                attrs.color = [colorMap colorForKey:kColorMapLink];
            }
            if (!currentRun) {
                firstRun = currentRun = malloc(sizeof(CRun));
                CRunInitialize(currentRun, &attrs, storage, VT100GridCoordMake(i, row), curX);
            }
            if (thisCharString) {
                currentRun = CRunAppendString(currentRun,
                                              &attrs,
                                              thisCharString,
                                              theLine[i].code,
                                              thisCharAdvance,
                                              curX);
            } else {
                currentRun = CRunAppend(currentRun, &attrs, thisCharUnichar, thisCharAdvance, curX);
            }
        } else {
            if (currentRun) {
                CRunTerminate(currentRun);
            }
            attrs.fakeBold = NO;
            attrs.fakeItalic = NO;
            attrs.fontInfo = nil;
        }
        
        curX += thisCharAdvance;
    }
    return firstRun;
}

- (NSRange)underlinedRangeOnLine:(int)row {
    if (_underlineRange.coordRange.start.x < 0) {
        return NSMakeRange(0, 0);
    }

    if (row == _underlineRange.coordRange.start.y && row == _underlineRange.coordRange.end.y) {
        // Whole underline is on one line.
        const int start = VT100GridWindowedRangeStart(_underlineRange).x;
        const int end = VT100GridWindowedRangeEnd(_underlineRange).x;
        return NSMakeRange(start, end - start);
    } else if (row == _underlineRange.coordRange.start.y) {
        // Underline spans multiple lines, starting at this one.
        const int start = VT100GridWindowedRangeStart(_underlineRange).x;
        const int end =
        _underlineRange.columnWindow.length > 0 ? VT100GridRangeMax(_underlineRange.columnWindow) + 1
        : _gridSize.width;
        return NSMakeRange(start, end - start);
    } else if (row == _underlineRange.coordRange.end.y) {
        // Underline spans multiple lines, ending at this one.
        const int start =
        _underlineRange.columnWindow.length > 0 ? _underlineRange.columnWindow.location : 0;
        const int end = VT100GridWindowedRangeEnd(_underlineRange).x;
        return NSMakeRange(start, end - start);
    } else if (row > _underlineRange.coordRange.start.y && row < _underlineRange.coordRange.end.y) {
        // Underline spans multiple lines. This is not the first or last line, so all chars
        // in it are underlined.
        const int start =
        _underlineRange.columnWindow.length > 0 ? _underlineRange.columnWindow.location : 0;
        const int end =
        _underlineRange.columnWindow.length > 0 ? VT100GridRangeMax(_underlineRange.columnWindow) + 1
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

- (BOOL)cursorInVisibleRow {
    NSRange range = [self rangeOfVisibleRows];
    int cursorLine = _numberOfLines - _gridSize.height + _cursorCoord.y;
    return NSLocationInRange(cursorLine, range);
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

- (NSRect)rectByGrowingRectByOneCell:(NSRect)innerRect {
    NSSize frameSize = _frame.size;
    NSPoint minPoint = NSMakePoint(MAX(0, innerRect.origin.x - _cellSize.width),
                                   MAX(0, innerRect.origin.y - _cellSize.height));
    NSPoint maxPoint = NSMakePoint(MIN(frameSize.width, NSMaxX(innerRect) + _cellSize.width),
                                   MIN(frameSize.height, NSMaxY(innerRect) + _cellSize.height));
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

// Not inclusive of end.x or end.y. Range of coords clipped to visible area and addressable lines.
- (VT100GridCoordRange)drawableCoordRangeForRect:(NSRect)rect {
    VT100GridCoordRange range;
    NSRange charRange = [self rangeOfColumnsFrom:rect.origin.x ofWidth:rect.size.width];
    range.start.x = charRange.location;
    range.end.x = charRange.location + charRange.length;

    // Where to start drawing?
    int lineStart = rect.origin.y / _cellSize.height;
    int lineEnd = ceil((rect.origin.y + rect.size.height) / _cellSize.height);

    // Ensure valid line ranges
    lineStart = MAX(0, lineStart);
    lineEnd = MIN(lineEnd, _numberOfLines);

    // Ensure lineEnd isn't beyond the bottom of the visible area.
    range.start.y = lineStart;
    range.end.y = MIN(lineEnd, NSMaxRange([self rangeOfVisibleRows]));

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

- (NSBezierPath *)bezierPathForBoxDrawingCode:(int)code {
    //  0 1 2
    //  3 4 5
    //  6 7 8
    NSArray *points = nil;
    // The points array is a series of numbers from the above grid giving the
    // sequence of points to move the pen to.
    switch (code) {
        case ITERM_BOX_DRAWINGS_LIGHT_UP_AND_LEFT:  // ┘
            points = @[ @(3), @(4), @(1) ];
            break;
        case ITERM_BOX_DRAWINGS_LIGHT_DOWN_AND_LEFT:  // ┐
            points = @[ @(3), @(4), @(7) ];
            break;
        case ITERM_BOX_DRAWINGS_LIGHT_DOWN_AND_RIGHT:  // ┌
            points = @[ @(7), @(4), @(5) ];
            break;
        case ITERM_BOX_DRAWINGS_LIGHT_UP_AND_RIGHT:  // └
            points = @[ @(1), @(4), @(5) ];
            break;
        case ITERM_BOX_DRAWINGS_LIGHT_VERTICAL_AND_HORIZONTAL:  // ┼
            points = @[ @(3), @(5), @(4), @(1), @(7) ];
            break;
        case ITERM_BOX_DRAWINGS_LIGHT_HORIZONTAL:  // ─
            points = @[ @(3), @(5) ];
            break;
        case ITERM_BOX_DRAWINGS_LIGHT_VERTICAL_AND_RIGHT:  // ├
            points = @[ @(1), @(4), @(5), @(4), @(7) ];
            break;
        case ITERM_BOX_DRAWINGS_LIGHT_VERTICAL_AND_LEFT:  // ┤
            points = @[ @(1), @(4), @(3), @(4), @(7) ];
            break;
        case ITERM_BOX_DRAWINGS_LIGHT_UP_AND_HORIZONTAL:  // ┴
            points = @[ @(3), @(4), @(1), @(4), @(5) ];
            break;
        case ITERM_BOX_DRAWINGS_LIGHT_DOWN_AND_HORIZONTAL:  // ┬
            points = @[ @(3), @(4), @(7), @(4), @(5) ];
            break;
        case ITERM_BOX_DRAWINGS_LIGHT_VERTICAL:  // │
            points = @[ @(1), @(7) ];
            break;
        default:
            break;
    }
    CGFloat xs[] = { 0, _cellSize.width / 2, _cellSize.width };
    CGFloat ys[] = { 0, _cellSize.height / 2, _cellSize.height };
    NSBezierPath *path = [NSBezierPath bezierPath];
    BOOL first = YES;
    for (NSNumber *n in points) {
        CGFloat x = xs[n.intValue % 3];
        CGFloat y = ys[n.intValue / 3];
        NSPoint p = NSMakePoint(x, y);
        if (first) {
            [path moveToPoint:p];
            first = NO;
        } else {
            [path lineToPoint:p];
        }
    }
    return path;
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
    double selectedAlpha = 1.0 - _transparency;
    aColor = [aColor colorWithAlphaComponent:selectedAlpha];
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

- (void)selectFont:(NSFont *)font inContext:(CGContextRef)ctx {
    if (font != _selectedFont) {
        // This method is really slow so avoid doing it when it's not necessary
        CGContextSelectFont(ctx,
                            [[font fontName] UTF8String],
                            [font pointSize],
                            kCGEncodingMacRoman);
        [_selectedFont release];
        _selectedFont = [font retain];
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

- (void)cursorDrawCharacter:(screen_char_t)screenChar
                        row:(int)row
                      point:(NSPoint)point
                doubleWidth:(BOOL)doubleWidth
              overrideColor:(NSColor *)overrideColor
                    context:(CGContextRef)ctx
            backgroundColor:(NSColor *)backgroundColor {
    // Offset the point by the vertical spacing. The point is derived from the box cursor's frame,
    // which is different than the top of the row (the cursor doesn't get taller as vertical spacing
    // is added, or shorter as it is removed). Text still wants to be rendered relative to the top
    // of the row including spacing, though.
    point.y -= (_cellSize.height - _cellSizeWithoutSpacing.height);

    CRunStorage *storage = [CRunStorage cRunStorageWithCapacity:1];
    // Draw the characters.
    screen_char_t temp[2];
    temp[0] = screenChar;
    memset(temp + 1, 0, sizeof(temp[1]));
    if (doubleWidth) {
        temp[1].code = DWC_RIGHT;
    }
    CRun *run = [self constructTextRuns:temp
                                    row:row
                               selected:NO
                             indexRange:NSMakeRange(0, 1)
                        backgroundColor:backgroundColor
                                matches:nil
                                storage:storage];
    if (run) {
        CRun *head = run;
        NSFont *theFont = nil;
        // If an override color is given, change the runs' colors.
        if (overrideColor) {
            while (run) {
                if (run->attrs.fontInfo.font) {
                    theFont = [[run->attrs.fontInfo.font retain] autorelease];
                }
                CRunAttrsSetColor(&run->attrs, run->storage, overrideColor);
                run = run->next;
            }
        }
        [self drawRunsAt:point run:head storage:storage context:ctx];

        // draw underline
        if (screenChar.underline && screenChar.code && theFont) {
            NSColor *underlineColor = nil;
            if (overrideColor) {
                underlineColor = overrideColor;
            } else {
                underlineColor =
                    [_delegate drawingHelperColorForCode:screenChar.foregroundColor
                                                   green:screenChar.fgGreen
                                                    blue:screenChar.fgBlue
                                               colorMode:screenChar.foregroundColorMode  // TODO: Test this if it's not alternate
                                                    bold:screenChar.bold
                                                   faint:screenChar.faint
                                            isBackground:_reverseVideo];
            }

            [self drawUnderlineOfColor:underlineColor
                          atCellOrigin:point
                                  font:theFont
                                 width:doubleWidth ? _cellSize.width * 2 : _cellSize.width];
        }

        CRunFree(head);
    }
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
