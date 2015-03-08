//
//  PTYTextView+Drawing.m
//  iTerm2
//
//  Created by George Nachman on 3/8/15.
//
//

#import "PTYTextView+Drawing.h"
#import "CharacterRunInline.h"
#import "charmaps.h"
#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermController.h"
#import "iTermFindCursorView.h"
#import "iTermFindOnPageHelper.h"
#import "iTermSelection.h"
#import "iTermTextExtractor.h"
#import "MovingAverage.h"
#import "NSColor+iTerm.h"
#import "VT100ScreenMark.h"
#import "VT100Terminal.h"  // TODO: Remove this dependency

static const int kBadgeMargin = 4;
static const int kBadgeRightMargin = 10;

@interface PTYTextView ()
@property(nonatomic, readonly) NSString *currentUnderlineHostname;
@property(nonatomic, readonly) NSImage *badgeImage;
@property(nonatomic, readonly) NSColor *unfocusedSelectionColor;
- (double)excess;
- (double)cursorHeight;
- (BOOL)_isCursorBlinking;
- (double)transparencyAlpha;
- (NSPoint)globalCursorLocation;
@end

@implementation PTYTextView (Drawing)

- (void)drawRect:(NSRect)rect {
    DLog(@"drawRect:%@ in view %@", [NSValue valueWithRect:rect], self);
    // If there are two or more rects that need display, the OS will pass in |rect| as the smallest
    // bounding rect that contains them all. Luckily, we can get the list of the "real" dirty rects
    // and they're guaranteed to be disjoint. So draw each of them individually.
    const NSRect *rectArray;
    NSInteger rectCount;
    if (drawRectDuration_) {
        [drawRectDuration_ startTimer];
        NSTimeInterval interval = [drawRectInterval_ timeSinceTimerStarted];
        if ([drawRectInterval_ haveStartedTimer]) {
            [drawRectInterval_ addValue:interval];
        }
        [drawRectInterval_ startTimer];
    }
    [self getRectsBeingDrawn:&rectArray count:&rectCount];
    for (int i = 0; i < rectCount; i++) {
        DLog(@"drawRect - draw sub rectangle %@", [NSValue valueWithRect:rectArray[i]]);
        [self clipAndDrawRect:rectArray[i]];
    }

    if (drawRectDuration_) {
        [drawRectDuration_ addValue:[drawRectDuration_ timeSinceTimerStarted]];
        NSLog(@"%p Moving average time draw rect is %04f, time between calls to drawRect is %04f",
              self, drawRectDuration_.value, drawRectInterval_.value);
    }

    id<PTYTextViewDelegate> delegate = self.delegate;
    [_indicatorsHelper setIndicator:kiTermIndicatorMaximized
                            visible:[delegate textViewIsMaximized]];
    [_indicatorsHelper setIndicator:kItermIndicatorBroadcastInput
                            visible:[delegate textViewSessionIsBroadcastingInput]];
    [_indicatorsHelper setIndicator:kiTermIndicatorCoprocess
                            visible:[delegate textViewHasCoprocess]];
    [_indicatorsHelper setIndicator:kiTermIndicatorAlert
                            visible:[delegate alertOnNextMark]];
    [_indicatorsHelper setIndicator:kiTermIndicatorAllOutputSuppressed
                            visible:[delegate textViewSuppressingAllOutput]];
    [_indicatorsHelper drawInFrame:self.visibleRect];

    if (_showTimestamps) {
        [self drawTimestamps];
    }

    // Not sure why this is needed, but for some reason this view draws over its subviews.
    for (NSView *subview in [self subviews]) {
        [subview setNeedsDisplay:YES];
    }
}

- (void)clipAndDrawRect:(NSRect)rect {
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [context saveGraphicsState];

    int minX = floor((rect.origin.x - MARGIN) / _charWidth);
    int maxX = ceil((NSMaxX(rect) - MARGIN) / _charWidth);
    int minY = rect.origin.y / _lineHeight;
    int maxY = ceil(NSMaxY(rect) / _lineHeight);

    NSRect innerRect;
    innerRect.origin = NSMakePoint(minX * _charWidth + MARGIN,
                                   minY * _lineHeight);
    innerRect.size = NSMakeSize((maxX - minX) * _charWidth, (maxY - minY) * _lineHeight);

    // Clip to the area that needs to be drawn.
    NSRectClip(innerRect);

    // Draw an extra ring of characters outside it.
    NSSize size = self.frame.size;
    NSPoint minPoint = { MAX(0, innerRect.origin.x - _charWidth),
        MAX(0, innerRect.origin.y - _lineHeight) };
    NSPoint maxPoint = { MIN(size.width - 1, NSMaxX(innerRect) + _charWidth),
        MIN(size.height - 1, NSMaxY(innerRect) + _lineHeight) };
    NSRect outerRect = NSMakeRect(minPoint.x,
                                  minPoint.y,
                                  maxPoint.x - minPoint.x,
                                  maxPoint.y - minPoint.y);
    [self drawOneRect:outerRect];

    [context restoreGraphicsState];
}

- (void)drawOneRect:(NSRect)rect
{
    // The range of chars in the line that need to be drawn.
    NSRange charRange = NSMakeRange(MAX(0, (rect.origin.x - MARGIN) / _charWidth),
                                    ceil((rect.origin.x + rect.size.width - MARGIN) / _charWidth));
    charRange.length -= charRange.location;
    id<PTYTextViewDataSource> dataSource = self.dataSource;
    id<PTYTextViewDelegate> delegate = self.delegate;
    if (charRange.location + charRange.length > [dataSource width]) {
        charRange.length = [dataSource width] - charRange.location;
    }
#ifdef DEBUG_DRAWING
    static int iteration=0;
    static BOOL prevBad=NO;
    ++iteration;
    if (prevBad) {
        NSLog(@"Last was bad.");
        prevBad = NO;
    }
    DebugLog([NSString stringWithFormat:@"%s(%p): rect=(%f,%f,%f,%f) frameRect=(%f,%f,%f,%f)]",
              __PRETTY_FUNCTION__, self,
              rect.origin.x, rect.origin.y, rect.size.width, rect.size.height,
              [self frame].origin.x, [self frame].origin.y, [self frame].size.width, [self frame].size.height]);
#endif
    double curLineWidth = [dataSource width] * _charWidth;
    if (_lineHeight <= 0 || curLineWidth <= 0) {
        DLog(@"height or width too small");
        return;
    }

    // Configure graphics
    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositeCopy];

    // Where to start drawing?
    int lineStart = rect.origin.y / _lineHeight;
    int lineEnd = ceil((rect.origin.y + rect.size.height) / _lineHeight);

    // Ensure valid line ranges
    if (lineStart < 0) {
        lineStart = 0;
    }
    if (lineEnd > [dataSource numberOfLines]) {
        lineEnd = [dataSource numberOfLines];
    }
    NSRect visible = [self scrollViewContentSize];
    int vh = visible.size.height;
    int lh = _lineHeight;
    int visibleRows = vh / lh;
    NSRect docVisibleRect = [[self enclosingScrollView] documentVisibleRect];
    double hiddenAbove = docVisibleRect.origin.y + [self frame].origin.y;
    int firstVisibleRow = hiddenAbove / lh;
    if (lineEnd > firstVisibleRow + visibleRows) {
        lineEnd = firstVisibleRow + visibleRows;
    }

#ifdef DEBUG_DRAWING
    DebugLog([NSString stringWithFormat:@"drawRect: Draw lines in range [%d, %d)", lineStart, lineEnd]);
    // Draw each line
    NSDictionary* dct =
    [NSDictionary dictionaryWithObjectsAndKeys:
     [NSColor textBackgroundColor], NSBackgroundColorAttributeName,
     [NSColor textColor], NSForegroundColorAttributeName,
     [NSFont userFixedPitchFontOfSize: 0], NSFontAttributeName, NULL];
#endif
    int overflow = [dataSource scrollbackOverflow];
#ifdef DEBUG_DRAWING
    NSMutableString* lineDebug = [NSMutableString stringWithFormat:@"drawRect:%d,%d %dx%d drawing these lines with scrollback overflow of %d, iteration=%d:\n", (int)rect.origin.x, (int)rect.origin.y, (int)rect.size.width, (int)rect.size.height, (int)[_dataSource scrollbackOverflow], iteration];
#endif
    double y = lineStart * _lineHeight;
    BOOL anyBlinking = NO;

    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];

    for (int line = lineStart; line < lineEnd; line++) {
        NSRect lineRect = [self visibleRect];
        lineRect.origin.y = line * _lineHeight;
        lineRect.size.height = _lineHeight;
        if ([self needsToDrawRect:lineRect]) {
            if (overflow <= line) {
                // If overflow > 0 then the lines in the _dataSource are not
                // lined up in the normal way with the view. This happens when
                // the _dataSource has scrolled its contents up but -[refresh]
                // has not been called yet, so the view's contents haven't been
                // scrolled up yet. When that's the case, the first line of the
                // view is what the first line of the _dataSource was before
                // it overflowed. Continue to draw text in this out-of-alignment
                // manner until refresh is called and gets things in sync again.
                anyBlinking |= [self drawLine:line-overflow
                                          AtY:y
                                    charRange:charRange
                                      context:ctx];
            }
#ifdef DEBUG_DRAWING
            // if overflow > line then the requested line cannot be drawn
            // because it has been lost to the sands of time.
            if (gDebugLogging) {
                screen_char_t* theLine = [_dataSource getLineAtIndex:line-overflow];
                int w = [_dataSource width];
                char dl[w+1];
                for (int i = 0; i < [_dataSource width]; ++i) {
                    if (theLine[i].complexChar) {
                        dl[i] = '#';
                    } else {
                        dl[i] = theLine[i].code;
                    }
                }
                DebugLog([NSString stringWithUTF8String:dl]);
            }

            screen_char_t* theLine = [_dataSource getLineAtIndex:line-overflow];
            for (int i = 0; i < [_dataSource width]; ++i) {
                [lineDebug appendFormat:@"%@", ScreenCharToStr(&theLine[i])];
            }
            [lineDebug appendString:@"\n"];
            [[NSString stringWithFormat:@"Iter %d, line %d, y=%d", iteration, line, (int)(y)]
             drawInRect:NSMakeRect(rect.size.width-200,
                                   y,
                                   200,
                                   _lineHeight)
             withAttributes:dct];
#endif
        }
        y += _lineHeight;
    }
#ifdef DEBUG_DRAWING
    [self appendDebug:lineDebug];
#endif
    NSRect excessRect;
    if (_numberOfIMELines) {
        // Draw a default-color rectangle from below the last line of text to
        // the bottom of the frame to make sure that IME offset lines are
        // cleared when the screen is scrolled up.
        excessRect.origin.x = 0;
        excessRect.origin.y = lineEnd * _lineHeight;
        excessRect.size.width = [[self enclosingScrollView] contentSize].width;
        excessRect.size.height = [self frame].size.height - excessRect.origin.y;
    } else  {
        // Draw the excess bar at the bottom of the visible rect the in case
        // that some other tab has a larger font and these lines don't fit
        // evenly in the available space.
        NSRect visibleRect = [self visibleRect];
        excessRect.origin.x = 0;
        excessRect.origin.y = visibleRect.origin.y + visibleRect.size.height - [self excess];
        excessRect.size.width = [[self enclosingScrollView] contentSize].width;
        excessRect.size.height = [self excess];
    }
#ifdef DEBUG_DRAWING
    // Draws the excess bar in a different color each time
    static int i;
    i++;
    double rc = ((double)((i + 0) % 100)) / 100;
    double gc = ((double)((i + 33) % 100)) / 100;
    double bc = ((double)((i + 66) % 100)) / 100;
    [[NSColor colorWithCalibratedRed:rc green:gc blue:bc alpha:1] set];
    NSRectFill(excessRect);
#else
    [delegate textViewDrawBackgroundImageInView:self
                                       viewRect:excessRect
                         blendDefaultBackground:YES];
#endif

    // Draw a margin at the top of the visible area.
    NSRect topMarginRect = [self visibleRect];
    if (topMarginRect.origin.y > 0) {
        topMarginRect.size.height = VMARGIN;
        [delegate textViewDrawBackgroundImageInView:self
                                           viewRect:topMarginRect
                             blendDefaultBackground:YES];
    }

#ifdef DEBUG_DRAWING
    // Draws a different-colored rectangle around each drawn area. Useful for
    // seeing which groups of lines were drawn in a batch.
    static double it;
    it += 3.14/4;
    double red = sin(it);
    double green = sin(it + 1*2*3.14/3);
    double blue = sin(it + 2*2*3.14/3);
    NSColor* c = [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1];
    [c set];
    NSRect r = rect;
    r.origin.y++;
    r.size.height -= 2;
    NSFrameRect(rect);
    if (overflow != 0) {
        // Draw a diagonal line through blocks that were drawn when there
        // [_dataSource scrollbackOverflow] > 0.
        [NSBezierPath strokeLineFromPoint:NSMakePoint(r.origin.x, r.origin.y)
                                  toPoint:NSMakePoint(r.origin.x + r.size.width, r.origin.y + r.size.height)];
    }
    NSString* debug;
    if (overflow == 0) {
        debug = [NSString stringWithFormat:@"origin=%d", (int)rect.origin.y];
    } else {
        debug = [NSString stringWithFormat:@"origin=%d, overflow=%d", (int)rect.origin.y, (int)overflow];
    }
    [debug drawInRect:rect withAttributes:dct];
#endif
    // If the IME is in use, draw its contents over top of the "real" screen
    // contents.
    [self drawInputMethodEditorTextAt:[dataSource cursorX] - 1
                                    y:[dataSource cursorY] - 1
                                width:[dataSource width]
                               height:[dataSource height]
                         cursorHeight:[self cursorHeight]
                                  ctx:ctx];
    [self drawCursor];
    anyBlinking |= [self _isCursorBlinking];

#ifdef DEBUG_DRAWING
    if (overflow) {
        // It's useful to put a breakpoint at the top of this function
        // when prevBad == YES because then you can see the results of this
        // draw function.
        prevBad=YES;
    }
#endif
    if (anyBlinking) {
        // The user might have used the scroll wheel to cause blinking text to become
        // visible. Make sure the timer is running if anything onscreen is
        // blinking.
        [delegate textViewWillNeedUpdateForBlink];
    }
    [selectedFont_ release];
    selectedFont_ = nil;
}

- (BOOL)drawLine:(int)line
             AtY:(double)curY
       charRange:(NSRange)charRange
         context:(CGContextRef)ctx {
    BOOL anyBlinking = NO;
#ifdef DEBUG_DRAWING
    int screenstartline = [self frame].origin.y / _lineHeight;
    DebugLog([NSString stringWithFormat:@"Draw line %d (%d on screen)", line, (line - screenstartline)]);
#endif
    id<PTYTextViewDataSource> dataSource = self.dataSource;
    id<PTYTextViewDelegate> delegate = self.delegate;
    const BOOL stripes = _showStripesWhenBroadcastingInput && [delegate textViewSessionIsBroadcastingInput];
    int WIDTH = [dataSource width];
    screen_char_t* theLine = [dataSource getLineAtIndex:line];
    BOOL hasBGImage = [delegate textViewHasBackgroundImage];
    double selectedAlpha = 1.0 - self.transparency;
    double alphaIfTransparencyInUse = [self transparencyAlpha];
    BOOL reversed = [[dataSource terminal] reverseVideo];
    NSColor *aColor = nil;

    // Redraw margins ------------------------------------------------------------------------------
    NSRect leftMargin = NSMakeRect(0, curY, MARGIN, _lineHeight);
    NSRect rightMargin;
    NSRect visibleRect = [self visibleRect];
    rightMargin.origin.x = _charWidth * WIDTH;
    rightMargin.origin.y = curY;
    rightMargin.size.width = visibleRect.size.width - rightMargin.origin.x;
    rightMargin.size.height = _lineHeight;

    aColor = [self colorForCode:ALTSEM_DEFAULT
                          green:0
                           blue:0
                      colorMode:ColorModeAlternate
                           bold:NO
                          faint:NO
                   isBackground:YES];

    // Draw background in margins
    [delegate textViewDrawBackgroundImageInView:self viewRect:leftMargin blendDefaultBackground:YES];
    [delegate textViewDrawBackgroundImageInView:self viewRect:rightMargin blendDefaultBackground:YES];

    aColor = [aColor colorWithAlphaComponent:selectedAlpha];
    [aColor set];
    // Indicate marks in margin --
    VT100ScreenMark *mark = [dataSource markOnLine:line];
    if (mark.isVisible) {
        NSImage *image = mark.code ? _markErrImage : _markImage;
        CGFloat offset = (_lineHeight - _markImage.size.height) / 2.0;
        [image drawAtPoint:NSMakePoint(leftMargin.origin.x,
                                       leftMargin.origin.y + offset)
                  fromRect:NSMakeRect(0, 0, _markImage.size.width, _markImage.size.height)
                 operation:NSCompositeSourceOver
                  fraction:1.0];
    }
    // Draw text and background --------------------------------------------------------------------
    // Contiguous sections of background with the same color
    // are combined into runs and draw as one operation
    int bgstart = -1;
    int j = charRange.location;
    int bgColor = 0;
    int bgGreen = 0;
    int bgBlue = 0;
    ColorMode bgColorMode = ColorModeNormal;
    BOOL bgselected = NO;
    BOOL isMatch = NO;
    NSData* matches = _findOnPageHelper.highlightMap[@(line + [dataSource totalScrollbackOverflow])];
    const char *matchBytes = [matches bytes];

    // Iterate over each character in the line.
    // Go one past where we really need to go to simplify the code.  // TODO(georgen): Fix that.
    int limit = charRange.location + charRange.length;
    NSIndexSet *selectedIndexes = [self.selection selectedIndexesOnLine:line];
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:dataSource];
    BOOL blinkAllowed = self.blinkAllowed;
    while (j < limit) {
        if (theLine[j].code == DWC_RIGHT) {
            // Do not draw the right-hand side of double-width characters.
            j++;
            continue;
        }
        if (blinkAllowed && theLine[j].blink) {
            anyBlinking = YES;
        }

        BOOL selected;
        if (theLine[j].code == DWC_SKIP) {
            selected = NO;
        } else if (theLine[j].code == TAB_FILLER) {
            if ([extractor isTabFillerOrphanAt:VT100GridCoordMake(j, line)]) {
                // Treat orphaned tab fillers like spaces.
                selected = [selectedIndexes containsIndex:j];
            } else {
                // Select all leading tab fillers iff the tab is selected.
                selected = [self isFutureTabSelectedAfterX:j Y:line];
            }
        } else {
            selected = [selectedIndexes containsIndex:j];
        }
        BOOL double_width = j < WIDTH - 1 && (theLine[j+1].code == DWC_RIGHT);
        BOOL match = NO;
        if (matchBytes) {
            // Test if this char is a highlighted match from a Find.
            const int theIndex = j / 8;
            const int bitMask = 1 << (j & 7);
            match = theIndex < [matches length] && (matchBytes[theIndex] & bitMask);
        }

        if (j != limit && bgstart < 0) {
            // Start new run
            bgstart = j;
            bgColor = theLine[j].backgroundColor;
            bgGreen = theLine[j].bgGreen;
            bgBlue = theLine[j].bgBlue;
            bgColorMode = theLine[j].backgroundColorMode;
            bgselected = selected;
            isMatch = match;
        }

        if (j != limit &&
            bgselected == selected &&
            theLine[j].backgroundColor == bgColor &&
            theLine[j].bgGreen == bgGreen &&
            theLine[j].bgBlue == bgBlue &&
            theLine[j].backgroundColorMode == bgColorMode &&
            match == isMatch) {
            // Continue the run
            j += (double_width ? 2 : 1);
        } else if (bgstart >= 0) {
            // This run is finished, draw it

            [self drawRunStartingAtIndex:bgstart
                                     row:line
                                   endAt:j
                                 yOrigin:curY
                              hasBGImage:hasBGImage
                       defaultBgColorPtr:&aColor
                alphaIfTransparencyInUse:alphaIfTransparencyInUse
                                 bgColor:bgColor
                             bgColorMode:bgColorMode
                                  bgBlue:bgBlue
                                 bgGreen:bgGreen
                                reversed:reversed
                              bgselected:bgselected
                                 isMatch:isMatch
                                 stripes:stripes
                                    line:theLine
                                 matches:matches
                                 context:ctx];
            bgstart = -1;
            // Return to top of loop without incrementing j so this
            // character gets the chance to start its own run
        } else {
            // Don't need to draw and not on a run, move to next char
            j += (double_width ? 2 : 1);
        }
    }
    if (bgstart >= 0) {
        // Draw last run, if necesary.
        [self drawRunStartingAtIndex:bgstart
                                 row:line
                               endAt:j
                             yOrigin:curY
                          hasBGImage:hasBGImage
                   defaultBgColorPtr:&aColor
            alphaIfTransparencyInUse:alphaIfTransparencyInUse
                             bgColor:bgColor
                         bgColorMode:bgColorMode
                              bgBlue:bgBlue
                             bgGreen:bgGreen
                            reversed:reversed
                          bgselected:bgselected
                             isMatch:isMatch
                             stripes:stripes
                                line:theLine
                             matches:matches
                             context:ctx];
    }

    NSArray *noteRanges = [dataSource charactersWithNotesOnLine:line];
    if (noteRanges.count) {
        for (NSValue *value in noteRanges) {
            VT100GridRange range = [value gridRangeValue];
            CGFloat x = range.location * _charWidth + MARGIN;
            CGFloat y = line * _lineHeight;
            [[NSColor yellowColor] set];

            CGFloat maxX = MIN(self.bounds.size.width - MARGIN, range.length * _charWidth + x);
            CGFloat w = maxX - x;
            NSRectFill(NSMakeRect(x, y + _lineHeight - 1.5, w, 1));
            [[NSColor orangeColor] set];
            NSRectFill(NSMakeRect(x, y + _lineHeight - 1, w, 1));
        }
        
    }
    
    return anyBlinking;
}

- (BOOL)drawInputMethodEditorTextAt:(int)xStart
                                  y:(int)yStart
                              width:(int)width
                             height:(int)height
                       cursorHeight:(double)cursorHeight
                                ctx:(CGContextRef)ctx {
    id<PTYTextViewDelegate> delegate = self.delegate;
    id<PTYTextViewDataSource> dataSource = self.dataSource;
    iTermColorMap *colorMap = self.colorMap;

    // draw any text for NSTextInput
    if ([self hasMarkedText]) {
        NSString* str = [_markedText string];
        const int maxLen = [str length] * kMaxParts;
        screen_char_t buf[maxLen];
        screen_char_t fg = {0}, bg = {0};
        fg.foregroundColor = ALTSEM_DEFAULT;
        fg.foregroundColorMode = ColorModeAlternate;
        fg.bold = NO;
        fg.faint = NO;
        fg.italic = NO;
        fg.blink = NO;
        fg.underline = NO;
        memset(&bg, 0, sizeof(bg));
        int len;
        int cursorIndex = (int)_inputMethodSelectedRange.location;
        StringToScreenChars(str,
                            buf,
                            fg,
                            bg,
                            &len,
                            [delegate textViewAmbiguousWidthCharsAreDoubleWidth],
                            &cursorIndex,
                            NULL,
                            [delegate textViewUseHFSPlusMapping]);
        int cursorX = 0;
        int baseX = floor(xStart * _charWidth + MARGIN);
        int i;
        int y = (yStart + [dataSource numberOfLines] - height) * _lineHeight;
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
                                  charsInLine * _charWidth,
                                  _lineHeight);
            if (!colorMap.dimOnlyText) {
                [[colorMap dimmedColorForKey:kColorMapBackground] set];
            } else {
                [[colorMap mutedColorForKey:kColorMapBackground] set];
            }
            NSRectFill(r);

            // Draw the characters.
            CRunStorage *storage = [CRunStorage cRunStorageWithCapacity:charsInLine];
            CRun *run = [self _constructRuns:NSMakePoint(x, y)
                                     theLine:buf
                                         row:y
                                    reversed:NO
                                  bgselected:NO
                                       width:[dataSource width]
                                  indexRange:NSMakeRange(i, charsInLine)
                                     bgColor:nil
                                     matches:nil
                                     storage:storage];
            if (run) {
                [self _drawRunsAt:NSMakePoint(x, y) run:run storage:storage context:ctx];
                CRunFree(run);
            }

            // Draw an underline.
            NSColor *foregroundColor = [colorMap mutedColorForKey:kColorMapForeground];
            [foregroundColor set];
            NSRect s = NSMakeRect(x,
                                  y + _lineHeight - 1,
                                  charsInLine * _charWidth,
                                  1);
            NSRectFill(s);

            // Save the cursor's cell coords
            if (i <= cursorIndex && i + charsInLine > cursorIndex) {
                // The char the cursor is at was drawn in this line.
                const int cellsAfterStart = cursorIndex - i;
                cursorX = x + _charWidth * cellsAfterStart;
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
            x = floor(xStart * _charWidth + MARGIN);
            y = (yStart + [dataSource numberOfLines] - height) * _lineHeight;
            i += charsInLine;
        }

        if (!foundCursor && i == cursorIndex) {
            if (justWrapped) {
                cursorX = MARGIN + width * _charWidth;
                cursorY = preWrapY;
            } else {
                cursorX = x;
                cursorY = y;
            }
        }
        const double kCursorWidth = 2.0;
        double rightMargin = MARGIN + [dataSource width] * _charWidth;
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
        if ([self isFindingCursor]) {
            NSPoint cp = [self globalCursorLocation];
            if (!NSEqualPoints(_findCursorView.cursorPosition, cp)) {
                _findCursorView.cursorPosition = cp;
                [_findCursorView setNeedsDisplay:YES];
            }
        }
        [[colorMap dimmedColorForColor:[NSColor colorWithCalibratedRed:1.0
                                                                 green:1.0
                                                                  blue:0
                                                                 alpha:1.0]] set];
        NSRectFill(cursorFrame);
        
        return TRUE;
    }
    return FALSE;
}

- (void)drawCursor {
    DLog(@"drawCursor");
    id<PTYTextViewDataSource> dataSource = self.dataSource;

    int width = [dataSource width];
    int height = [dataSource height];
    int column = [dataSource cursorX] - 1;
    int row = [dataSource cursorY] - 1;

    if (![self cursorInDocumentVisibleRect]) {
        return;
    }

    // Update the last time the cursor moved.
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (column != _oldCursorPosition.x || row != _oldCursorPosition.y) {
        lastTimeCursorMoved_ = now;
    }
    BOOL shouldShowCursor = [self shouldShowCursor];

    // Draw the regular cursor only if there's not an IME open as it draws its
    // own cursor.
    DLog(@"drawCursor: hasMarkedText=%d, cursorVisible=%d, showCursor=%d, column=%d, row=%d, "
         @"width=%d, height=%d",
         (int)[self hasMarkedText], (int)self.cursorVisible, (int)shouldShowCursor, column, row,
         width, height);
    if (![self hasMarkedText] &&
        self.cursorVisible &&
        shouldShowCursor &&
        column <= width &&
        column >= 0 &&
        row >= 0 &&
        row < height) {
        screen_char_t *theLine = [dataSource getLineAtScreenIndex:row];
        BOOL isDoubleWidth;
        screen_char_t screenChar = [self charForCursorAtColumn:column
                                                        inLine:theLine
                                                   doubleWidth:&isDoubleWidth];
        NSSize cursorSize = [self cursorSize];
        NSPoint cursorOrigin =
            NSMakePoint(floor(column * _charWidth + MARGIN),
                        (row + [dataSource numberOfLines] - height + 1) * _lineHeight - cursorSize.height);

        if ([self isFindingCursor]) {
            NSPoint globalCursorLocation = [self globalCursorLocation];
            if (!NSEqualPoints(_findCursorView.cursorPosition, globalCursorLocation)) {
                _findCursorView.cursorPosition = globalCursorLocation;
                [_findCursorView setNeedsDisplay:YES];
            }
        }

        NSColor *bgColor;
        bgColor = [self backgroundColorForCursorOnLine:theLine
                                              atColumn:column
                                            screenChar:screenChar];

        switch (self.cursorType) {
            case CURSOR_BOX:
                [self drawBoxCursorOfSize:cursorSize
                            isDoubleWidth:isDoubleWidth
                                  atPoint:cursorOrigin
                                   column:column
                               screenChar:screenChar
                          backgroundColor:bgColor];

                break;

            case CURSOR_VERTICAL:
                [self drawVerticalBarCursorOfSize:cursorSize atPoint:cursorOrigin color:bgColor];
                break;

            case CURSOR_UNDERLINE:
                [self drawUnderlineCursorOfSize:cursorSize
                                  isDoubleWidth:isDoubleWidth
                                        atPoint:cursorOrigin
                                          color:bgColor];
                break;

            case CURSOR_DEFAULT:
                assert(false);
                break;
        }
    }

    _oldCursorPosition = VT100GridCoordMake(column, row);
    [selectedFont_ release];
    selectedFont_ = nil;
}

// Returns true iff the tab character after a run of TAB_FILLERs starting at
// (x,y) is selected.
- (BOOL)isFutureTabSelectedAfterX:(int)x Y:(int)y {
    id<PTYTextViewDataSource> dataSource = self.dataSource;
    const int realWidth = [dataSource width] + 1;
    screen_char_t buffer[realWidth];
    screen_char_t* theLine = [dataSource getLineAtIndex:y withBuffer:buffer];
    while (x < [dataSource width] && theLine[x].code == TAB_FILLER) {
        ++x;
    }
    if ([self.selection containsCoord:VT100GridCoordMake(x, y)] &&
        theLine[x].code == '\t') {
        return YES;
    } else {
        return NO;
    }
}

// Draw a run of background color/image and foreground text.
- (void)drawRunStartingAtIndex:(const int)firstIndex  // Index into line of first char
                           row:(int)row               // Row number of line
                         endAt:(const int)lastIndex   // Index into line of last char
                       yOrigin:(const double)yOrigin  // Top left corner of rect to draw into
                    hasBGImage:(const BOOL)hasBGImage  // If set, draw a bg image (else solid colors only)
             defaultBgColorPtr:(NSColor **)defaultBgColorPtr  // Pass in default bg color; may be changed.
      alphaIfTransparencyInUse:(const double)alphaIfTransparencyInUse  // Alpha value to use if transparency is on
                       bgColor:(const int)bgColor      // bg color code (or red component if 24 bit)
                   bgColorMode:(const ColorMode)bgColorMode  // bg color mode
                        bgBlue:(const int)bgBlue       // blue component if 24 bit
                       bgGreen:(const int)bgGreen      // green component if 24 bit
                      reversed:(const BOOL)reversed    // reverse video?
                    bgselected:(const BOOL)bgselected  // is selected text?
                       isMatch:(const BOOL)isMatch     // is Find On Page match?
                       stripes:(const BOOL)stripes     // bg is striped?
                          line:(screen_char_t *)theLine  // Whole screen line
                       matches:(NSData *)matches // Bitmask of Find On Page matches
                       context:(CGContextRef)ctx {     // Graphics context
    NSColor *aColor = *defaultBgColorPtr;
    id<PTYTextViewDataSource> dataSource = self.dataSource;
    id<PTYTextViewDelegate> delegate = self.delegate;
    NSRect bgRect = NSMakeRect(floor(MARGIN + firstIndex * _charWidth),
                               yOrigin,
                               ceil((lastIndex - firstIndex) * _charWidth),
                               _lineHeight);

    if (hasBGImage) {
        [delegate textViewDrawBackgroundImageInView:self
                                           viewRect:bgRect
                             blendDefaultBackground:NO];
    }
    if (!hasBGImage ||
        (isMatch && !bgselected) ||
        !(bgColor == ALTSEM_DEFAULT && bgColorMode == ColorModeAlternate) ||
        bgselected) {
        // There's no bg image, or there's a nondefault bg on a bg image.
        // We are not drawing an unmolested background image. Some
        // background fill must be drawn. If there is a background image
        // it will be blended with the bg color.

        if (isMatch && !bgselected) {
            aColor = [NSColor colorWithCalibratedRed:1 green:1 blue:0 alpha:1];
        } else if (bgselected) {
            aColor = [self selectionColorForCurrentFocus];
        } else {
            if (reversed && bgColor == ALTSEM_DEFAULT && bgColorMode == ColorModeAlternate) {
                // Reverse video is only applied to default background-
                // color chars.
                aColor = [self colorForCode:ALTSEM_DEFAULT
                                      green:0
                                       blue:0
                                  colorMode:ColorModeAlternate
                                       bold:NO
                                      faint:NO
                               isBackground:NO];
            } else {
                // Use the regular background color.
                aColor = [self colorForCode:bgColor
                                      green:bgGreen
                                       blue:bgBlue
                                  colorMode:bgColorMode
                                       bold:NO
                                      faint:NO
                               isBackground:YES];
            }
        }
        aColor = [aColor colorWithAlphaComponent:alphaIfTransparencyInUse];
        [aColor set];
        NSRectFillUsingOperation(bgRect,
                                 hasBGImage ? NSCompositeSourceOver : NSCompositeCopy);
    } else if (hasBGImage) {
        // There is a bg image and no special background on it. Blend
        // in the default background color.
        aColor = [self colorForCode:ALTSEM_DEFAULT
                              green:0
                               blue:0
                          colorMode:ColorModeAlternate
                               bold:NO
                              faint:NO
                       isBackground:YES];
        aColor = [aColor colorWithAlphaComponent:1 - self.blend];
        [aColor set];
        NSRectFillUsingOperation(bgRect, NSCompositeSourceOver);
    }
    *defaultBgColorPtr = aColor;
    [self drawBadgeInRect:bgRect];

    // Draw red stripes in the background if sending input to all sessions
    if (stripes) {
        [self _drawStripesInRect:bgRect];
    }

    NSPoint textOrigin;
    textOrigin = NSMakePoint(MARGIN + firstIndex * _charWidth, yOrigin);

    // Highlight cursor line
    int cursorLine = [dataSource cursorY] - 1 + [dataSource numberOfScrollbackLines];
    if (self.highlightCursorLine && row == cursorLine) {
        [[delegate textViewCursorGuideColor] set];
        NSRect rect = NSMakeRect(textOrigin.x,
                                 textOrigin.y,
                                 (lastIndex - firstIndex) * _charWidth,
                                 _lineHeight);
        NSRectFillUsingOperation(rect, NSCompositeSourceOver);

        rect.size.height = 1;
        NSRectFillUsingOperation(rect, NSCompositeSourceOver);

        rect.origin.y += _lineHeight - 1;
        NSRectFillUsingOperation(rect, NSCompositeSourceOver);
    }

    [self _drawCharactersInLine:theLine
                            row:row
                        inRange:NSMakeRange(firstIndex, lastIndex - firstIndex)
                startingAtPoint:textOrigin
                     bgselected:bgselected
                       reversed:reversed
                        bgColor:aColor
                        matches:matches
                        context:ctx];
}

- (CRun *)_constructRuns:(NSPoint)initialPoint
                 theLine:(screen_char_t *)theLine
                     row:(int)row
                reversed:(BOOL)reversed
              bgselected:(BOOL)bgselected
                   width:(const int)width
              indexRange:(NSRange)indexRange
                 bgColor:(NSColor*)bgColor
                 matches:(NSData*)matches
                 storage:(CRunStorage *)storage {
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
    const BOOL dimOnlyText = colorMap.dimOnlyText;
    const double minimumContrast = self.minimumContrast;
    for (int i = indexRange.location; i < indexRange.location + indexRange.length; i++) {
        inUnderlinedRange = (i >= underlineStartsAt && i < underlineEndsAt);
        if (theLine[i].code == DWC_RIGHT) {
            continue;
        }

        BOOL doubleWidth = i < width - 1 && (theLine[i + 1].code == DWC_RIGHT);
        unichar thisCharUnichar = 0;
        NSString* thisCharString = nil;
        CGFloat thisCharAdvance;

        if (!self.useNonAsciiFont || (theLine[i].code < 128 && !theLine[i].complexChar)) {
            attrs.antiAlias = _asciiAntiAlias;
        } else {
            attrs.antiAlias = _nonasciiAntiAlias;
        }
        BOOL isSelection = NO;

        // Figure out the color for this char.
        if (bgselected) {
            // Is a selection.
            isSelection = YES;
            // NOTE: This could be optimized by caching the color.
            CRunAttrsSetColor(&attrs, storage, [colorMap dimmedColorForKey:kColorMapSelectedText]);
        } else {
            // Not a selection.
            if (reversed &&
                theLine[i].foregroundColor == ALTSEM_DEFAULT &&
                theLine[i].foregroundColorMode == ColorModeAlternate) {
                // Has default foreground color so use background color.
                if (!dimOnlyText) {
                    CRunAttrsSetColor(&attrs, storage,
                                      [colorMap dimmedColorForKey:kColorMapBackground]);
                } else {
                    CRunAttrsSetColor(&attrs,
                                      storage,
                                      [colorMap mutedColorForKey:kColorMapBackground]);
                }
            } else {
                if (theLine[i].foregroundColor == lastForegroundColor &&
                    theLine[i].fgGreen == lastFgGreen &&
                    theLine[i].fgBlue == lastFgBlue &&
                    theLine[i].foregroundColorMode == lastForegroundColorMode &&
                    theLine[i].bold == lastBold &&
                    theLine[i].faint == lastFaint) {
                    // Looking up colors with -colorForCode:... is expensive and it's common to
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
                                      [self colorForCode:theLine[i].foregroundColor
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

        if (minimumContrast > 0.001 && bgColor) {
            // TODO: Way too much time spent here. Use previous char's color if it is the same.
            CRunAttrsSetColor(&attrs,
                              storage,
                              [colorMap color:attrs.color withContrastAgainst:bgColor]);
        }
        BOOL drawable;
        if (_blinkingItemsVisible || ![self charBlinks:theLine[i]]) {
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

        if (theLine[i].underline || inUnderlinedRange) {
            // This is not as fast as possible, but is nice and simple. Always draw underlined text
            // even if it's just a blank.
            drawable = YES;
        }
        // Set all other common attributes.
        if (doubleWidth) {
            thisCharAdvance = _charWidth * 2;
        } else {
            thisCharAdvance = _charWidth;
        }

        if (drawable) {
            BOOL fakeBold = theLine[i].bold;
            BOOL fakeItalic = theLine[i].italic;
            attrs.fontInfo = [self getFontForChar:theLine[i].code
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
            if (inUnderlinedRange && !self.currentUnderlineHostname) {
                attrs.color = [colorMap colorForKey:kColorMapLink];
            }
            if (!currentRun) {
                firstRun = currentRun = malloc(sizeof(CRun));
                CRunInitialize(currentRun, &attrs, storage, curX);
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

- (void)_drawRunsAt:(NSPoint)initialPoint
                run:(CRun *)run
            storage:(CRunStorage *)storage
            context:(CGContextRef)ctx {
    CGContextSetTextDrawingMode(ctx, kCGTextFill);
    while (run) {
        [self drawRun:run ctx:ctx initialPoint:initialPoint storage:storage];
        run = run->next;
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
            int firstComplexGlyph = [self _drawSimpleRun:currentRun
                                                     ctx:ctx
                                            initialPoint:initialPoint];
            if (firstComplexGlyph < 0) {
                break;
            }
            CRun *complexRun = CRunSplit(currentRun, firstComplexGlyph);
            [self _advancedDrawRun:complexRun
                                at:NSMakePoint(initialPoint.x + complexRun->x, initialPoint.y)];
            CRunFree(complexRun);
        }
    } else {
        // Complex
        [self _advancedDrawRun:currentRun
                            at:NSMakePoint(initialPoint.x + currentRun->x, initialPoint.y)];
    }

    // Draw underline
    if (currentRun->attrs.underline) {
        [currentRun->attrs.color set];
        NSRectFill(NSMakeRect(startPoint.x,
                              startPoint.y + _lineHeight - 2,
                              runWidth,
                              1));
    }
}

- (BOOL)shouldShowCursor {
    if (self.blinkingCursor &&
        self.isInKeyWindow &&
        [self.delegate textViewIsActiveSession] &&
        [NSDate timeIntervalSinceReferenceDate] - lastTimeCursorMoved_ > 0.5) {
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
    int width = [self.dataSource width];
    if (column == width) {
        screenChar = theLine[column - 1];
        screenChar.code = 0;
        screenChar.complexChar = NO;
    }
    if (screenChar.code) {
        if (screenChar.code == DWC_RIGHT && column > 0) {
            column--;
            screenChar = theLine[column];
        }
        *doubleWidth = (column < width - 1) && (theLine[column+1].code == DWC_RIGHT);
    } else {
        *doubleWidth = NO;
    }
    return screenChar;
}

- (NSSize)cursorSize {
    NSSize size;
    if (_charWidth < _charWidthWithoutSpacing) {
        size.width = _charWidth;
    } else {
        size.width = _charWidthWithoutSpacing;
    }
    size.height = [self cursorHeight];
    return size;
}

// screenChar isn't directly inferrable from theLine because it gets tweaked for various edge cases.
- (NSColor *)backgroundColorForCursorOnLine:(screen_char_t *)theLine
                                   atColumn:(int)column
                                 screenChar:(screen_char_t)screenChar {
    if ([self isFindingCursor]) {
        DLog(@"Use random cursor color");
        return [self _randomColor];
    }

    if (self.useSmartCursorColor) {
        return [[self smartCursorColorForChar:screenChar
                                       column:column
                                  lineOfChars:theLine] colorWithAlphaComponent:1.0];
    } else {
        return [[self.colorMap colorForKey:kColorMapCursor] colorWithAlphaComponent:1.0];
    }
}

- (void)drawBoxCursorOfSize:(NSSize)cursorSize
              isDoubleWidth:(BOOL)double_width
                    atPoint:(NSPoint)cursorOrigin
                     column:(int)column
                 screenChar:(screen_char_t)screenChar
            backgroundColor:(NSColor *)bgColor {
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    [bgColor set];
    // draw the box
    BOOL frameOnly;
    DLog(@"draw cursor box at %f,%f size %fx%f",
         (float)cursorOrigin.x, (float)cursorOrigin.y,
         (float)ceil(cursorSize.width * (double_width ? 2 : 1)), cursorSize.height);
    if (([self isInKeyWindow] && [self.delegate textViewIsActiveSession]) ||
        [self.delegate textViewShouldDrawFilledInCursor]) {
        frameOnly = NO;
        NSRectFill(NSMakeRect(cursorOrigin.x,
                              cursorOrigin.y,
                              ceil(cursorSize.width * (double_width ? 2 : 1)),
                              cursorSize.height));
    } else {
        frameOnly = YES;
        NSFrameRect(NSMakeRect(cursorOrigin.x,
                               cursorOrigin.y,
                               ceil(cursorSize.width * (double_width ? 2 : 1)),
                               cursorSize.height));
    }
    // draw any character on cursor if we need to
    if (screenChar.code) {
        // Have a char at the cursor position.
        if (self.useSmartCursorColor && !frameOnly) {
            // Pick background color for text if is key window, otherwise use fg color for text.
            int fgColor;
            int fgGreen;
            int fgBlue;
            ColorMode fgColorMode;
            BOOL fgBold;
            BOOL fgFaint;
            BOOL isBold;
            BOOL isFaint;
            NSColor* overrideColor = nil;
            if ([self isInKeyWindow]) {
                // Draw a character in background color when
                // window is key.
                fgColor = screenChar.backgroundColor;
                fgGreen = screenChar.bgGreen;
                fgBlue = screenChar.bgBlue;
                fgColorMode = screenChar.backgroundColorMode;
                fgBold = NO;
                fgFaint = NO;
            } else {
                // Draw character in foreground color when there
                // is just a frame around it.
                fgColor = screenChar.foregroundColor;
                fgGreen = screenChar.fgGreen;
                fgBlue = screenChar.fgBlue;
                fgColorMode = screenChar.foregroundColorMode;
                fgBold = screenChar.bold;
                fgFaint = screenChar.faint;
            }
            isBold = screenChar.bold;
            isFaint = screenChar.faint;

            // Ensure text has enough contrast by making it black/white if the char's color would be close to the cursor bg.
            NSColor* proposedForeground = [[self colorForCode:fgColor
                                                        green:fgGreen
                                                         blue:fgBlue
                                                    colorMode:fgColorMode
                                                         bold:fgBold
                                                        faint:fgFaint
                                                 isBackground:NO] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
            CGFloat fgBrightness = [proposedForeground perceivedBrightness];
            CGFloat bgBrightness = [bgColor perceivedBrightness];
            if (!frameOnly && fabs(fgBrightness - bgBrightness) <
                [iTermAdvancedSettingsModel smartCursorColorFgThreshold]) {
                // foreground and background are very similar. Just use black and
                // white.
                if (bgBrightness < 0.5) {
                    overrideColor =
                    [self.colorMap dimmedColorForColor:[NSColor colorWithCalibratedRed:1
                                                                                 green:1
                                                                                  blue:1
                                                                                 alpha:1]];
                } else {
                    overrideColor =
                    [self.colorMap dimmedColorForColor:[NSColor colorWithCalibratedRed:0
                                                                                 green:0
                                                                                  blue:0
                                                                                 alpha:1]];
                }
            }

            BOOL saved = self.useBrightBold;
            self.useBrightBold = NO;
            [self _drawCharacter:screenChar
                         fgColor:fgColor
                         fgGreen:fgGreen
                          fgBlue:fgBlue
                     fgColorMode:fgColorMode
                          fgBold:isBold
                         fgFaint:isFaint
                             AtX:column * _charWidth + MARGIN
                               Y:cursorOrigin.y + cursorSize.height - _lineHeight
                     doubleWidth:double_width
                   overrideColor:overrideColor
                         context:ctx
                 backgroundColor:nil];
            self.useBrightBold = saved;
        } else {
            // Non-inverted cursor or cursor is frame
            int theColor;
            int theGreen;
            int theBlue;
            ColorMode theMode;
            BOOL isBold;
            BOOL isFaint;
            if ([self isInKeyWindow]) {
                theColor = ALTSEM_CURSOR;
                theGreen = 0;
                theBlue = 0;
                theMode = ColorModeAlternate;
            } else {
                theColor = screenChar.foregroundColor;
                theGreen = screenChar.fgGreen;
                theBlue = screenChar.fgBlue;
                theMode = screenChar.foregroundColorMode;
            }
            isBold = screenChar.bold;
            isFaint = screenChar.faint;
            [self _drawCharacter:screenChar
                         fgColor:theColor
                         fgGreen:theGreen
                          fgBlue:theBlue
                     fgColorMode:theMode
                          fgBold:isBold
                         fgFaint:isFaint
                             AtX:column * _charWidth + MARGIN
                               Y:cursorOrigin.y + cursorSize.height - _lineHeight
                     doubleWidth:double_width
                   overrideColor:nil
                         context:ctx
                 backgroundColor:bgColor];  // Pass bgColor so min contrast can apply
        }
    }
}

- (void)drawVerticalBarCursorOfSize:(NSSize)cursorSize
                            atPoint:(NSPoint)cursorOrigin
                              color:(NSColor *)color {
    DLog(@"draw cursor vline at %f,%f size %fx%f",
         (float)cursorOrigin.x, (float)cursorOrigin.y, (float)1, cursorSize.height);
    [color set];
    NSRectFill(NSMakeRect(cursorOrigin.x, cursorOrigin.y, 1, cursorSize.height));
}

- (void)drawUnderlineCursorOfSize:(NSSize)cursorSize
                    isDoubleWidth:(BOOL)double_width
                          atPoint:(NSPoint)cursorOrigin
                            color:(NSColor *)color {
    DLog(@"draw cursor underline at %f,%f size %fx%f",
         (float)cursorOrigin.x, (float)cursorOrigin.y,
         (float)ceil(cursorSize.width * (double_width ? 2 : 1)), 2.0);
    [color set];
    NSRectFill(NSMakeRect(cursorOrigin.x,
                          cursorOrigin.y + _lineHeight - 2,
                          ceil(cursorSize.width * (double_width ? 2 : 1)),
                          2));
}

- (NSColor *)smartCursorColorForChar:(screen_char_t)screenChar
                              column:(int)column
                         lineOfChars:(screen_char_t *)theLine {
    int row = [self.dataSource cursorY] - 1;

    screen_char_t* lineAbove = nil;
    screen_char_t* lineBelow = nil;
    if (row > 0) {
        lineAbove = [self.dataSource getLineAtScreenIndex:row - 1];
    }
    if (row + 1 < [self.dataSource height]) {
        lineBelow = [self.dataSource getLineAtScreenIndex:row + 1];
    }

    NSColor *bgColor;
    if ([[self.dataSource terminal] reverseVideo]) {
        bgColor = [self colorForCode:screenChar.backgroundColor
                               green:screenChar.bgGreen
                                blue:screenChar.bgBlue
                           colorMode:screenChar.backgroundColorMode
                                bold:screenChar.bold
                               faint:screenChar.faint
                        isBackground:NO];
    } else {
        bgColor = [self colorForCode:screenChar.foregroundColor
                               green:screenChar.fgGreen
                                blue:screenChar.fgBlue
                           colorMode:screenChar.foregroundColorMode
                                bold:screenChar.bold
                               faint:screenChar.faint
                        isBackground:NO];
    }

    NSMutableArray* constraints = [NSMutableArray arrayWithCapacity:2];
    CGFloat bgBrightness = [bgColor perceivedBrightness];
    if (column > 0) {
        [constraints addObject:@([self _brightnessOfCharBackground:theLine[column - 1]])];
    }
    if (column < [self.dataSource width]) {
        [constraints addObject:@([self _brightnessOfCharBackground:theLine[column + 1]])];
    }
    if (lineAbove) {
        [constraints addObject:@([self _brightnessOfCharBackground:lineAbove[column]])];
    }
    if (lineBelow) {
        [constraints addObject:@([self _brightnessOfCharBackground:lineBelow[column]])];
    }
    if ([self _minimumDistanceOf:bgBrightness fromAnyValueIn:constraints] <
        [iTermAdvancedSettingsModel smartCursorColorBgThreshold]) {
        CGFloat b = [self _farthestValueFromAnyValueIn:constraints];
        bgColor = [NSColor colorWithCalibratedRed:b green:b blue:b alpha:1];
    }
    return bgColor;
}

- (BOOL)cursorInDocumentVisibleRect {
    NSRect docVisibleRect = [[self enclosingScrollView] documentVisibleRect];
    id<PTYTextViewDataSource> dataSource = self.dataSource;
    int lastVisibleLine = docVisibleRect.origin.y / [self lineHeight] + [dataSource height];
    int cursorLine = ([dataSource numberOfLines] - [dataSource height] + [dataSource cursorY] -
                      [dataSource scrollbackOverflow]);
    if (cursorLine > lastVisibleLine) {
        return NO;
    }
    if (cursorLine < 0) {
        return NO;
    }
    return YES;
}

- (NSSize)drawBadgeInRect:(NSRect)rect {
    NSImage *image = self.badgeImage;
    if (!image) {
        return NSZeroSize;
    }
    NSSize textViewSize = self.bounds.size;
    NSSize visibleSize = [[self enclosingScrollView] documentVisibleRect].size;
    NSSize imageSize = image.size;
    NSRect destination = NSMakeRect(textViewSize.width - imageSize.width - kBadgeRightMargin,
                                    textViewSize.height - visibleSize.height + kiTermIndicatorStandardHeight,
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
    imageSize.width += kBadgeMargin + kBadgeRightMargin;
    return imageSize;
}

- (void)_drawStripesInRect:(NSRect)rect {
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(rect);
    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositeSourceOver];

    const CGFloat kStripeWidth = 40;
    const double kSlope = 1;

    for (CGFloat x = kSlope * -fmod(rect.origin.y, kStripeWidth * 2) -2 * kStripeWidth ;
         x < rect.origin.x + rect.size.width;
         x += kStripeWidth * 2) {
        if (x + 2 * kStripeWidth + rect.size.height * kSlope < rect.origin.x) {
            continue;
        }
        NSBezierPath* thePath = [NSBezierPath bezierPath];

        [thePath moveToPoint:NSMakePoint(x, rect.origin.y + rect.size.height)];
        [thePath lineToPoint:NSMakePoint(x + kSlope * rect.size.height, rect.origin.y)];
        [thePath lineToPoint:NSMakePoint(x + kSlope * rect.size.height + kStripeWidth, rect.origin.y)];
        [thePath lineToPoint:NSMakePoint(x + kStripeWidth, rect.origin.y + rect.size.height)];
        [thePath closePath];

        [[[NSColor redColor] colorWithAlphaComponent:0.15] set];
        [thePath fill];
    }
    [NSGraphicsContext restoreGraphicsState];
}

- (void)_drawCharactersInLine:(screen_char_t *)theLine
                          row:(int)row
                      inRange:(NSRange)indexRange
              startingAtPoint:(NSPoint)initialPoint
                   bgselected:(BOOL)bgselected
                     reversed:(BOOL)reversed
                      bgColor:(NSColor*)bgColor
                      matches:(NSData*)matches
                      context:(CGContextRef)ctx {
    const int width = [self.dataSource width];
    CRunStorage *storage = [CRunStorage cRunStorageWithCapacity:width];
    CRun *run = [self _constructRuns:initialPoint
                             theLine:theLine
                                 row:row
                            reversed:reversed
                          bgselected:bgselected
                               width:width
                          indexRange:indexRange
                             bgColor:bgColor
                             matches:matches
                             storage:storage];

    if (run) {
        [self _drawRunsAt:initialPoint run:run storage:storage context:ctx];
        CRunFree(run);
    }
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
                                                    : [self.dataSource width];
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
                                                    : [self.dataSource width];
        return NSMakeRange(start, end - start);
    } else {
        // No selection on this line.
        return NSMakeRange(0, 0);
    }
}

- (NSColor *)selectionColorForCurrentFocus {
    PTYTextView* frontTextView = [[iTermController sharedInstance] frontTextView];
    if (self == frontTextView) {
        return [self.colorMap mutedColorForKey:kColorMapSelection];
    } else {
        return self.unfocusedSelectionColor;
    }
}

// Note: caller must nil out selectedFont_ after the graphics context becomes invalid.
- (int)_drawSimpleRun:(CRun *)currentRun
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

    double y = initialPoint.y + _lineHeight + currentRun->attrs.fontInfo.baselineOffset;
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

- (void)_advancedDrawRun:(CRun *)complexRun at:(NSPoint)pos {
    if (complexRun->attrs.imageCode > 0) {
        ImageInfo *imageInfo = GetImageInfo(complexRun->attrs.imageCode);
        NSImage *image = [imageInfo imageEmbeddedInRegionOfSize:NSMakeSize(_charWidth * imageInfo.size.width,
                                                                           _lineHeight * imageInfo.size.height)];
        NSSize chunkSize = NSMakeSize(image.size.width / imageInfo.size.width,
                                      image.size.height / imageInfo.size.height);
        [NSGraphicsContext saveGraphicsState];
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:pos.x yBy:pos.y + _lineHeight];
        [transform scaleXBy:1.0 yBy:-1.0];
        [transform concat];

        NSColor *backgroundColor = [self.colorMap mutedColorForKey:kColorMapBackground];
        [backgroundColor set];
        NSRectFill(NSMakeRect(0, 0, _charWidth * complexRun->numImageCells, _lineHeight));

        [image drawInRect:NSMakeRect(0, 0, _charWidth * complexRun->numImageCells, _lineHeight)
                 fromRect:NSMakeRect(chunkSize.width * complexRun->attrs.imageColumn,
                                     image.size.height - _lineHeight - chunkSize.height * complexRun->attrs.imageLine,
                                     chunkSize.width * complexRun->numImageCells,
                                     chunkSize.height)
                operation:NSCompositeSourceOver
                 fraction:1];
        [NSGraphicsContext restoreGraphicsState];
        return;
    }
    NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
    NSColor *color = complexRun->attrs.color;

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
        case ITERM_BOX_DRAWINGS_LIGHT_VERTICAL: {
            NSBezierPath *path = [self bezierPathForBoxDrawingCode:complexRun->key];
            [ctx saveGraphicsState];
            NSAffineTransform *transform = [NSAffineTransform transform];
            [transform translateXBy:pos.x yBy:pos.y];
            [transform concat];
            [color set];
            [path stroke];
            [ctx restoreGraphicsState];
            return;
        }

        default:
            break;
    }
    NSString *str = complexRun->string;
    PTYFontInfo *fontInfo = complexRun->attrs.fontInfo;
    BOOL fakeBold = complexRun->attrs.fakeBold;
    BOOL fakeItalic = complexRun->attrs.fakeItalic;
    BOOL antiAlias = complexRun->attrs.antiAlias;

    NSDictionary* attrs;
    attrs = [NSDictionary dictionaryWithObjectsAndKeys:
             fontInfo.font, NSFontAttributeName,
             color, NSForegroundColorAttributeName,
             nil];
    [ctx saveGraphicsState];
    [ctx setCompositingOperation:NSCompositeSourceOver];
    if (StringContainsCombiningMark(str)) {
        // This renders characters with combining marks better but is slower.
        NSMutableAttributedString* attributedString =
        [[[NSMutableAttributedString alloc] initWithString:str
                                                attributes:attrs] autorelease];
        // This code used to use -[NSAttributedString drawWithRect:options] but
        // it does a lousy job rendering multiple combining marks. This is close
        // to what WebKit does and appears to be the highest quality text
        // rendering available. However, this path is only available in 10.7+.

        CTLineRef lineRef = CTLineCreateWithAttributedString((CFAttributedStringRef)attributedString);
        CFArrayRef runs = CTLineGetGlyphRuns(lineRef);
        CGContextRef cgContext = (CGContextRef) [ctx graphicsPort];
        CGContextSetFillColorWithColor(cgContext, [self cgColorForColor:color]);
        CGContextSetStrokeColorWithColor(cgContext, [self cgColorForColor:color]);

        CGFloat m21 = 0.0;
        if (fakeItalic) {
            m21 = 0.2;
        }

        CGAffineTransform textMatrix = CGAffineTransformMake(1.0,  0.0,
                                                             m21, -1.0,
                                                             pos.x, pos.y + fontInfo.baselineOffset + _lineHeight);
        CGContextSetTextMatrix(cgContext, textMatrix);

        for (CFIndex j = 0; j < CFArrayGetCount(runs); j++) {
            CTRunRef run = CFArrayGetValueAtIndex(runs, j);
            CFRange range;
            range.length = 0;
            range.location = 0;
            size_t length = CTRunGetGlyphCount(run);
            const CGGlyph *buffer = CTRunGetGlyphsPtr(run);
            const CGPoint *positions = CTRunGetPositionsPtr(run);
            CTFontRef runFont = CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);
            CTFontDrawGlyphs(runFont, buffer, (NSPoint *)positions, length, cgContext);
            if (fakeBold) {
                CGContextTranslateCTM(cgContext, antiAlias ? _antiAliasedShift : 1, 0);
                CTFontDrawGlyphs(runFont, buffer, (NSPoint *)positions, length, cgContext);
                CGContextTranslateCTM(cgContext, antiAlias ? -_antiAliasedShift : -1, 0);
            }
        }
        CFRelease(lineRef);
    } else {
        CGFloat width = CRunGetAdvances(complexRun)[0].width;
        NSMutableAttributedString* attributedString =
        [[[NSMutableAttributedString alloc] initWithString:str
                                                attributes:attrs] autorelease];
        // Note that drawInRect doesn't use the right baseline, but drawWithRect
        // does.
        //
        // This technique was picked because it can find glyphs that aren't in the
        // selected font (e.g., tests/radical.txt). It does a fairly nice job on
        // laying out combining marks.  For now, it fails in two known cases:
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
                                                  pos.y + fontInfo.baselineOffset + _lineHeight,
                                                  width * 2,
                                                  _lineHeight)
                               options:0];  // NSStringDrawingUsesLineFragmentOrigin
        if (fakeBold) {
            // If anti-aliased, drawing twice at the same position makes the strokes thicker.
            // If not anti-alised, draw one pixel to the right.
            [attributedString drawWithRect:NSMakeRect(pos.x + (antiAlias ? 0 : 1),
                                                      pos.y + fontInfo.baselineOffset + _lineHeight,
                                                      width*2,
                                                      _lineHeight)
                                   options:0];  // NSStringDrawingUsesLineFragmentOrigin
        }
    }
    [ctx restoreGraphicsState];
}

- (NSColor *)_randomColor {
    double r = arc4random() % 256;
    double g = arc4random() % 256;
    double b = arc4random() % 256;
    return [NSColor colorWithDeviceRed:r/255.0
                                 green:g/255.0
                                  blue:b/255.0
                                 alpha:1];
}

- (void)_drawCharacter:(screen_char_t)screenChar
               fgColor:(int)fgColor
               fgGreen:(int)fgGreen
                fgBlue:(int)fgBlue
           fgColorMode:(ColorMode)fgColorMode
                fgBold:(BOOL)fgBold
               fgFaint:(BOOL)fgFaint
                   AtX:(double)X
                     Y:(double)Y
           doubleWidth:(BOOL)double_width
         overrideColor:(NSColor*)overrideColor
               context:(CGContextRef)ctx
       backgroundColor:(NSColor *)backgroundColor {
    screen_char_t temp = screenChar;
    temp.foregroundColor = fgColor;
    temp.fgGreen = fgGreen;
    temp.fgBlue = fgBlue;
    temp.foregroundColorMode = fgColorMode;
    temp.bold = fgBold;
    temp.faint = fgFaint;

    CRunStorage *storage = [CRunStorage cRunStorageWithCapacity:1];
    // Draw the characters.
    CRun *run = [self _constructRuns:NSMakePoint(X, Y)
                             theLine:&temp
                                 row:(int)Y
                            reversed:NO
                          bgselected:NO
                               width:[self.dataSource width]
                          indexRange:NSMakeRange(0, 1)
                             bgColor:backgroundColor
                             matches:nil
                             storage:storage];
    if (run) {
        CRun *head = run;
        // If an override color is given, change the runs' colors.
        if (overrideColor) {
            while (run) {
                CRunAttrsSetColor(&run->attrs, run->storage, overrideColor);
                run = run->next;
            }
        }
        [self _drawRunsAt:NSMakePoint(X, Y) run:head storage:storage context:ctx];
        CRunFree(head);
    }

    // draw underline
    if (screenChar.underline && screenChar.code) {
        if (overrideColor) {
            [overrideColor set];
        } else {
            [[self colorForCode:fgColor
                          green:fgGreen
                           blue:fgBlue
                      colorMode:ColorModeAlternate
                           bold:fgBold
                          faint:fgFaint
                   isBackground:NO] set];
        }

        NSRectFill(NSMakeRect(X,
                              Y + _lineHeight - 2,
                              double_width ? _charWidth * 2 : _charWidth,
                              1));
    }
}

- (double)_brightnessOfCharBackground:(screen_char_t)c {
    return [[self backgroundColorForChar:c] perceivedBrightness];
}

// Return the value in 'values' closest to target.
- (CGFloat)_minimumDistanceOf:(CGFloat)target fromAnyValueIn:(NSArray*)values {
    CGFloat md = 1;
    for (NSNumber* n in values) {
        CGFloat dist = fabs(target - [n doubleValue]);
        if (dist < md) {
            md = dist;
        }
    }
    return md;
}

// Return the value between 0 and 1 that is farthest from any value in 'constraints'.
- (CGFloat)_farthestValueFromAnyValueIn:(NSArray*)constraints {
    if ([constraints count] == 0) {
        return 0;
    }

    NSArray* sortedConstraints = [constraints sortedArrayUsingSelector:@selector(compare:)];
    double minVal = [[sortedConstraints objectAtIndex:0] doubleValue];
    double maxVal = [[sortedConstraints lastObject] doubleValue];

    CGFloat bestDistance = 0;
    CGFloat bestValue = -1;
    CGFloat prev = [[sortedConstraints objectAtIndex:0] doubleValue];
    for (NSNumber* np in sortedConstraints) {
        CGFloat n = [np doubleValue];
        const CGFloat dist = fabs(n - prev) / 2;
        if (dist > bestDistance) {
            bestDistance = dist;
            bestValue = (n + prev) / 2;
        }
        prev = n;
    }
    if (minVal > bestDistance) {
        bestValue = 0;
        bestDistance = minVal;
    }
    if (1 - maxVal > bestDistance) {
        bestValue = 1;
        bestDistance = 1 - maxVal;
    }
    DLog(@"Best distance is %f", (float)bestDistance);

    return bestValue;
}

- (void)selectFont:(NSFont *)font inContext:(CGContextRef)ctx {
    if (font != selectedFont_) {
        // This method is really slow so avoid doing it when it's not necessary
        CGContextSelectFont(ctx,
                            [[font fontName] UTF8String],
                            [font pointSize],
                            kCGEncodingMacRoman);
        [selectedFont_ release];
        selectedFont_ = [font retain];
    }
}

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
    CGFloat xs[] = { 0, _charWidth / 2, _charWidth };
    CGFloat ys[] = { 0, _lineHeight / 2, _lineHeight };
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

- (NSColor*)backgroundColorForChar:(screen_char_t)c {
    if ([[self.dataSource terminal] reverseVideo]) {
        // reversed
        return [self colorForCode:c.foregroundColor
                            green:c.fgGreen
                             blue:c.fgBlue
                        colorMode:c.foregroundColorMode
                             bold:c.bold
                            faint:c.faint
                     isBackground:YES];
    } else {
        // normal
        return [self colorForCode:c.backgroundColor
                            green:c.bgGreen
                             blue:c.bgBlue
                        colorMode:c.backgroundColorMode
                             bold:NO
                            faint:NO
                     isBackground:YES];
    }
}

- (void)drawTimestamps {
    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];

    for (int y = visibleRect.origin.y / _lineHeight;
         y < (visibleRect.origin.y + visibleRect.size.height) / _lineHeight && y < [self.dataSource numberOfLines];
         y++) {
        [self drawTimestampForLine:y];
    }
}

- (void)drawTimestampForLine:(int)line
{
    NSDate *timestamp = [self.dataSource timestampForLine:line];
    NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
    const NSTimeInterval day = -86400;
    const NSTimeInterval timeDelta = [timestamp timeIntervalSinceNow];
    if (timeDelta < day * 365) {
        // More than a year ago: include year
        [fmt setDateFormat:[NSDateFormatter dateFormatFromTemplate:@"yyyyMMMd hh:mm:ss"
                                                           options:0
                                                            locale:[NSLocale currentLocale]]];
    } else if (timeDelta < day * 7) {
        // 1 week to 1 year ago: include date without year
        [fmt setDateFormat:[NSDateFormatter dateFormatFromTemplate:@"MMMd hh:mm:ss"
                                                           options:0
                                                            locale:[NSLocale currentLocale]]];
    } else if (timeDelta < day) {
        // 1 day to 1 week ago: include day of week
        [fmt setDateFormat:[NSDateFormatter dateFormatFromTemplate:@"EEE hh:mm:ss"
                                                           options:0
                                                            locale:[NSLocale currentLocale]]];

    } else {
        // In last 24 hours, just show time
        [fmt setDateFormat:[NSDateFormatter dateFormatFromTemplate:@"hh:mm:ss"
                                                           options:0
                                                            locale:[NSLocale currentLocale]]];
    }

    NSString *s = [fmt stringFromDate:timestamp];
    if (!timestamp || ![timestamp timeIntervalSinceReferenceDate]) {
        s = @"";
    }

    NSSize size = [s sizeWithAttributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:10] }];
    int w = size.width + MARGIN;
    int x = MAX(0, self.frame.size.width - w);
    CGFloat y = line * _lineHeight;
    NSColor *bgColor = [self.colorMap colorForKey:kColorMapBackground];
    NSColor *fgColor = [self.colorMap mutedColorForKey:kColorMapForeground];
    NSColor *shadowColor;
    if ([fgColor isDark]) {
        shadowColor = [NSColor whiteColor];
    } else {
        shadowColor = [NSColor blackColor];
    }

    const CGFloat alpha = 0.75;
    NSGradient *gradient =
    [[[NSGradient alloc] initWithStartingColor:[bgColor colorWithAlphaComponent:0]
                                   endingColor:[bgColor colorWithAlphaComponent:alpha]] autorelease];
    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositeSourceOver];
    [gradient drawInRect:NSMakeRect(x - 20, y, 20, _lineHeight) angle:0];

    [[bgColor colorWithAlphaComponent:alpha] set];
    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositeSourceOver];
    NSRectFillUsingOperation(NSMakeRect(x, y, w, _lineHeight), NSCompositeSourceOver);

    NSShadow *shadow = [[[NSShadow alloc] init] autorelease];
    shadow.shadowColor = shadowColor;
    shadow.shadowBlurRadius = 0.2f;
    shadow.shadowOffset = CGSizeMake(0.5, -0.5);

    NSDictionary *attributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:10],
                                  NSForegroundColorAttributeName: fgColor,
                                  NSShadowAttributeName: shadow };
    CGFloat offset = (_lineHeight - size.height) / 2;
    [s drawAtPoint:NSMakePoint(x, y + offset) withAttributes:attributes];
}

@end
