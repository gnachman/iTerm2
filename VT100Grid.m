//
//  VT100Grid.m
//  iTerm
//
//  Created by George Nachman on 10/9/13.
//
//

#import "VT100Grid.h"

#import "DebugLogging.h"
#import "LineBuffer.h"
#import "RegexKitLite.h"
#import "VT100GridTypes.h"
#import "VT100LineInfo.h"
#import "VT100Terminal.h"

@interface VT100Grid ()
@property(nonatomic, readonly) NSArray *lines;  // Warning: not in order found on screen!
@end

@implementation VT100Grid

@synthesize size = size_;
@synthesize scrollRegionRows = scrollRegionRows_;
@synthesize scrollRegionCols = scrollRegionCols_;
@synthesize useScrollRegionCols = useScrollRegionCols_;
@synthesize allDirty = allDirty_;
@synthesize lines = lines_;
@synthesize savedDefaultChar = savedDefaultChar_;
@synthesize cursor = cursor_;
@synthesize delegate = delegate_;

- (id)initWithSize:(VT100GridSize)size delegate:(id<VT100GridDelegate>)delegate {
    self = [super init];
    if (self) {
        delegate_ = delegate;
        [self setSize:size];
        scrollRegionRows_ = VT100GridRangeMake(0, size_.height);
        scrollRegionCols_ = VT100GridRangeMake(0, size_.width);
    }
    return self;
}

- (void)dealloc {
    [lines_ release];
    [lineInfos_ release];
    [cachedDefaultLine_ release];
    [super dealloc];
}

- (NSMutableData *)lineDataAtLineNumber:(int)lineNumber {
    if (lineNumber >= 0 && lineNumber < size_.height) {
        return [lines_ objectAtIndex:(screenTop_ + lineNumber) % size_.height];
    } else {
        return nil;
    }
}

- (screen_char_t *)screenCharsAtLineNumber:(int)lineNumber {
    assert(lineNumber >= 0);
    return [[lines_ objectAtIndex:(screenTop_ + lineNumber) % size_.height] mutableBytes];
}

- (VT100LineInfo *)lineInfoAtLineNumber:(int)lineNumber {
    if (lineNumber >= 0 && lineNumber < size_.height) {
        return [lineInfos_ objectAtIndex:(screenTop_ + lineNumber) % size_.height];
    } else {
        return nil;
    }
}

- (void)markCharDirty:(BOOL)dirty at:(VT100GridCoord)coord updateTimestamp:(BOOL)updateTimestamp {
    if (!dirty) {
        allDirty_ = NO;
    }
    VT100LineInfo *lineInfo = [self lineInfoAtLineNumber:coord.y];
    [lineInfo setDirty:dirty
               inRange:VT100GridRangeMake(coord.x, 1)
       updateTimestamp:updateTimestamp];
}

- (void)markCharsDirty:(BOOL)dirty inRectFrom:(VT100GridCoord)from to:(VT100GridCoord)to {
    if (!dirty) {
        allDirty_ = NO;
    }
    for (int y = from.y; y <= to.y; y++) {
        VT100LineInfo *lineInfo = [self lineInfoAtLineNumber:y];
        [lineInfo setDirty:dirty
                   inRange:VT100GridRangeMake(from.x, to.x - from.x + 1)
           updateTimestamp:YES];
    }
}

- (void)markAllCharsDirty:(BOOL)dirty {
    allDirty_ = dirty;
    [self markCharsDirty:dirty
              inRectFrom:VT100GridCoordMake(0, 0)
                      to:VT100GridCoordMake(size_.width - 1, size_.height - 1)];
}

- (void)markCharsDirty:(BOOL)dirty inRun:(VT100GridRun)run {
    if (!dirty) {
        allDirty_ = NO;
    }
    for (NSValue *value in [self rectsForRun:run]) {
        VT100GridRect rect = [value gridRectValue];
        [self markCharsDirty:dirty inRectFrom:rect.origin to:VT100GridRectMax(rect)];
    }
}

- (BOOL)isCharDirtyAt:(VT100GridCoord)coord {
    if (allDirty_) {
        return YES;
    }
    VT100LineInfo *lineInfo = [self lineInfoAtLineNumber:coord.y];
    return [lineInfo isDirtyAtOffset:coord.x];
}

- (BOOL)isAnyCharDirty {
    if (allDirty_) {
        return YES;
    }
    for (int y = 0; y < size_.height; y++) {
        VT100LineInfo *lineInfo = [self lineInfoAtLineNumber:y];
        if ([lineInfo anyCharIsDirty]) {
            return YES;
        }
    }
    return NO;
}

- (VT100GridRange)dirtyRangeForLine:(int)y {
    VT100LineInfo *lineInfo = [self lineInfoAtLineNumber:y];
    return [lineInfo dirtyRange];
}

- (int)cursorX {
    return cursor_.x;
}

- (int)cursorY {
    return cursor_.y;
}

- (void)setCursorX:(int)cursorX {
    cursor_.x = MIN(size_.width, MAX(0, cursorX));
}

- (void)setCursorY:(int)cursorY {
    cursor_.y = MIN(size_.height - 1, MAX(0, cursorY));
}

- (void)setCursor:(VT100GridCoord)coord {
    cursor_.x = MIN(size_.width, MAX(0, coord.x));
    cursor_.y = MIN(size_.height - 1, MAX(0, coord.y));
}

- (int)numberOfLinesUsed {
    int numberOfLinesUsed = size_.height;

    for(; numberOfLinesUsed > cursor_.y + 1; numberOfLinesUsed--) {
        screen_char_t *line = [self screenCharsAtLineNumber:numberOfLinesUsed - 1];
        int i;
        for (i = 0; i < size_.width; i++) {
            if (line[i].code) {
                break;
            }
        }
        if (i < size_.width) {
            break;
        }
    }

    return numberOfLinesUsed;
}

- (int)appendLines:(int)numLines
      toLineBuffer:(LineBuffer *)lineBuffer {
    assert(numLines <= size_.height);

    // Set numLines to the number of lines on the screen that are in use.
    int i;

    // Push the current screen contents into the scrollback buffer.
    // The maximum number of lines of scrollback are temporarily ignored because this
    // loop doesn't call dropExcessLinesWithWidth.
    int lengthOfNextLine;
    if (numLines > 0) {
        lengthOfNextLine = [self lengthOfLineNumber:0];
    }
    for (i = 0; i < numLines; ++i) {
        screen_char_t* line = [self screenCharsAtLineNumber:i];
        int currentLineLength = lengthOfNextLine;
        if (i + 1 < size_.height) {
            lengthOfNextLine = [self lengthOfLine:[self screenCharsAtLineNumber:i+1]];
        } else {
            lengthOfNextLine = -1;
        }

        int continuation = line[size_.width].code;
        if (i == cursor_.y) {
            [lineBuffer setCursor:cursor_.x];
        } else if ((cursor_.x == 0) &&
                   (i == cursor_.y - 1) &&
                   (lengthOfNextLine == 0) &&
                   line[size_.width].code != EOL_HARD) {
            // This line is continued, the next line is empty, and the cursor is
            // on the first column of the next line. Pull it up.
            // NOTE: This was cursor_.x + 1, but I'm pretty sure that's wrong as it would always be 1.
            [lineBuffer setCursor:currentLineLength];
        }

        [lineBuffer appendLine:line
                        length:currentLineLength
                       partial:(continuation != EOL_HARD)
                         width:size_.width
                     timestamp:[[self lineInfoAtLineNumber:i] timestamp]];
#ifdef DEBUG_RESIZEDWIDTH
        NSLog(@"Appended a line. now have %d lines for width %d\n",
              [lineBuffer numLinesWithWidth:size_.width], size_.width);
#endif
    }

    return numLines;
}

- (NSTimeInterval)timestampForLine:(int)y {
    return [[self lineInfoAtLineNumber:y] timestamp];
}

- (int)lengthOfLineNumber:(int)lineNumber {
    screen_char_t *line = [self screenCharsAtLineNumber:lineNumber];
    return [self lengthOfLine:line];
}

- (int)lengthOfLine:(screen_char_t *)line {
    int lineLength = 0;
    // Figure out the line length.
    if (line[size_.width].code == EOL_SOFT) {
        lineLength = size_.width;
    } else if (line[size_.width].code == EOL_DWC) {
        lineLength = size_.width - 1;
    } else {
        for (lineLength = size_.width - 1; lineLength >= 0; --lineLength) {
            if (line[lineLength].code && line[lineLength].code != DWC_SKIP) {
                break;
            }
        }
        ++lineLength;
    }
    return lineLength;
}

- (int)continuationMarkForLineNumber:(int)lineNumber {
    screen_char_t *line = [self screenCharsAtLineNumber:lineNumber];
    return line[size_.width].code;
}

- (int)indexOfLineNumber:(int)lineNumber {
    while (lineNumber < 0) {
        lineNumber += size_.height;
    }
    return (screenTop_ + lineNumber) % size_.height;
}

- (int)scrollWholeScreenUpIntoLineBuffer:(LineBuffer *)lineBuffer
                     unlimitedScrollback:(BOOL)unlimitedScrollback {
    // Mark the cursor's previous location dirty. This fixes a rare race condition where
    // the cursor is not erased.
    // TODO: I'm not sure this still exists post-refactoring.
    if (cursor_.x < size_.width) {
      [self markCharDirty:YES at:cursor_ updateTimestamp:YES];
    }

    // Add the top line to the scrollback
    int numLinesDropped = [self appendLineToLineBuffer:lineBuffer
                                   unlimitedScrollback:unlimitedScrollback];

    // Increment screenTop_, effectively scrolling the lines & dirty up by one line.
    screenTop_ = (screenTop_ + 1) % size_.height;

    // Empty contents of last line on screen.
    [self clearLineData:[self lineDataAtLineNumber:(size_.height - 1)]];

    if (lineBuffer) {
        // Mark new line at bottom of screen dirty.
        [self markCharsDirty:YES
                  inRectFrom:VT100GridCoordMake(0, size_.height - 1)
                          to:VT100GridCoordMake(size_.width - 1, size_.height - 1)];
    } else {
        // Mark everything dirty if we're not using the scrollback buffer.
        // TODO: Test what happens when the alt screen scrolls while it has a selection.
        [self markCharsDirty:YES
                  inRectFrom:VT100GridCoordMake(0, 0)
                          to:VT100GridCoordMake(size_.width - 1, size_.height - 1)];
    }

    DLog(@"scrolled screen up by 1 line");
    return numLinesDropped;
}

- (int)scrollUpIntoLineBuffer:(LineBuffer *)lineBuffer
          unlimitedScrollback:(BOOL)unlimitedScrollback
      useScrollbackWithRegion:(BOOL)useScrollbackWithRegion {
    const int scrollTop = self.topMargin;
    const int scrollBottom = self.bottomMargin;
    const int scrollLeft = self.leftMargin;
    const int scrollRight = self.rightMargin;

    assert(scrollTop >= 0 && scrollTop < size_.height);
    assert(scrollBottom >= 0 && scrollBottom < size_.height);
    assert(scrollTop <= scrollBottom );

    if (![self haveScrollRegion]) {
        // Scroll the whole screen. This is the fast path.
        return [self scrollWholeScreenUpIntoLineBuffer:lineBuffer
                                   unlimitedScrollback:unlimitedScrollback];
    } else {
        int numLinesDropped = 0;
        // Not scrolling the whole screen.
        if (scrollTop == 0 && useScrollbackWithRegion && ![self haveColumnScrollRegion]) {
            // A line is being scrolled off the top of the screen so add it to
            // the scrollback buffer.
            numLinesDropped = [self appendLineToLineBuffer:lineBuffer
                                       unlimitedScrollback:unlimitedScrollback];
        }
        // TODO: formerly, scrollTop==scrollBottom was a no-op but I think that's wrong. See what other terms do.
        [self scrollRect:VT100GridRectMake(scrollLeft,
                                           scrollTop,
                                           scrollRight - scrollLeft + 1,
                                           scrollBottom - scrollTop + 1)
                    downBy:-1];

        return numLinesDropped;
    }
}

- (int)resetWithLineBuffer:(LineBuffer *)lineBuffer
        unlimitedScrollback:(BOOL)unlimitedScrollback
        preserveCursorLine:(BOOL)preserveCursorLine {
    self.scrollRegionRows = VT100GridRangeMake(0, size_.height);
    self.scrollRegionCols = VT100GridRangeMake(0, size_.width);
    int numLinesToScroll;
    if (preserveCursorLine) {
        numLinesToScroll = cursor_.y;
    } else {
        numLinesToScroll = [self lineNumberOfLastNonEmptyLine] + 1;
    }
    int numLinesDropped = 0;
    for (int i = 0; i < numLinesToScroll; i++) {
        numLinesDropped += [self scrollUpIntoLineBuffer:lineBuffer
                                    unlimitedScrollback:unlimitedScrollback
                                useScrollbackWithRegion:NO];
    }
    self.cursor = VT100GridCoordMake(0, 0);

    [self setCharsFrom:VT100GridCoordMake(0, preserveCursorLine ? 1 : 0)
                    to:VT100GridCoordMake(size_.width - 1, size_.height - 1)
                toChar:[self defaultChar]];

    return numLinesDropped;
}

- (void)moveWrappedCursorLineToTopOfGrid {
    if (cursor_.y < 0) {
        return;  // Not sure how this would happen, but the old code in -[VT100Screen clearScreen] had this check.
    }
    int sourceLineNumber = [self cursorLineNumberIncludingPrecedingWrappedLines];
    for (int i = 0; i < sourceLineNumber; i++) {
        [self scrollWholeScreenUpIntoLineBuffer:nil unlimitedScrollback:NO];
    }
    self.cursorY = cursor_.y - sourceLineNumber;
}

- (int)moveCursorDownOneLineScrollingIntoLineBuffer:(LineBuffer *)lineBuffer
                                unlimitedScrollback:(BOOL)unlimitedScrollback
                            useScrollbackWithRegion:(BOOL)useScrollbackWithRegion {
    const int scrollBottom = self.bottomMargin;

    if (cursor_.y < scrollBottom ||
        (cursor_.y < (size_.height - 1) && cursor_.y > scrollBottom)) {
        // Do not scroll the screen; just move the cursor.
        self.cursorY = cursor_.y + 1;
        DLog(@"moved cursor down by 1 line");
        return 0;
    } else {
        // We are scrolling within a subset of the screen.
        DebugLog(@"scrolled a subset or whole screen up by 1 line");
        return [self scrollUpIntoLineBuffer:lineBuffer
                        unlimitedScrollback:unlimitedScrollback
                    useScrollbackWithRegion:useScrollbackWithRegion];
    }
}

- (void)moveCursorLeft:(int)n {
    int x = cursor_.x - n;
    const int leftMargin = [self leftMargin];

    x = MAX(leftMargin, x);
    self.cursorX = x;
}

- (void)moveCursorRight:(int)n {
    int x = cursor_.x + n;
    const int rightMargin = [self rightMargin];

    x = MIN(x, rightMargin);
    self.cursorX = x;
}

- (void)moveCursorUp:(int)n {
    const int scrollTop = self.topMargin;
    int y = MAX(0, MIN(size_.height - 1, cursor_.y - n));
    int x = MIN(cursor_.x, size_.width - 1);
    if (cursor_.y >= scrollTop) {
        [self setCursor:VT100GridCoordMake(x,
                                           y < scrollTop ? scrollTop : y)];
    } else {
        [self setCursor:VT100GridCoordMake(x, y)];
    }
}

- (void)moveCursorDown:(int)n {
    const int scrollBottom = self.bottomMargin;
    int y = MAX(0, MIN(size_.height - 1, cursor_.y + n));
    int x = MIN(cursor_.x, size_.width - 1);
    if (cursor_.y <= scrollBottom) {
        [self setCursor:VT100GridCoordMake(x,
                                           y > scrollBottom ? scrollBottom : y)];
    } else {
        [self setCursor:VT100GridCoordMake(x, y)];
    }
}

- (void)setCharsFrom:(VT100GridCoord)from to:(VT100GridCoord)to toChar:(screen_char_t)c {
    if (from.x > to.x || from.y > to.y) {
        return;
    }
    for (int y = MAX(0, from.y); y <= MIN(to.y, size_.height - 1); y++) {
        screen_char_t *line = [self screenCharsAtLineNumber:y];
        [self erasePossibleDoubleWidthCharInLineNumber:y startingAtOffset:from.x - 1 withChar:c];
        [self erasePossibleDoubleWidthCharInLineNumber:y startingAtOffset:to.x withChar:c];
        for (int x = MAX(0, from.x); x <= MIN(to.x, size_.width - 1); x++) {
            line[x] = c;
        }
        if (c.code == 0 && to.x == size_.width - 1) {
            line[size_.width].code = EOL_HARD;
        }
    }
    [self markCharsDirty:YES inRectFrom:from to:to];
}

- (void)setCharsInRun:(VT100GridRun)run toChar:(unichar)code {
    screen_char_t c = [self defaultChar];
    c.code = code;
    c.complexChar = NO;

    VT100GridCoord max = VT100GridRunMax(run, size_.width);
    int y = run.origin.y;

    if (y == max.y) {
        // Whole run is on one line.
        [self setCharsFrom:run.origin to:max toChar:c];
    } else {
        // Fill partial first line
        [self setCharsFrom:run.origin
                        to:VT100GridCoordMake(size_.width - 1, y)
                    toChar:c];
        y++;

        if (y < max.y) {
            // Fill a bunch of full lines
            [self setCharsFrom:VT100GridCoordMake(0, y)
                            to:VT100GridCoordMake(size_.width - 1, max.y - 1)
                        toChar:c];
        }

        // Fill possibly-partial last line
        [self setCharsFrom:VT100GridCoordMake(0, max.y)
                        to:VT100GridCoordMake(max.x, max.y)
                    toChar:c];
    }
}

- (void)setBackgroundColor:(screen_char_t)bg
           foregroundColor:(screen_char_t)fg
                inRectFrom:(VT100GridCoord)from
                        to:(VT100GridCoord)to {
    for (int y = from.y; y <= to.y; y++) {
        screen_char_t *line = [self screenCharsAtLineNumber:y];
        for (int x = from.x; x <= to.x; x++) {
            if (fg.foregroundColorMode != ColorModeInvalid) {
                CopyForegroundColor(&line[x], fg);
            }
            if (bg.backgroundColorMode != ColorModeInvalid) {
                CopyBackgroundColor(&line[x], bg);
            }
        }
        [self markCharsDirty:YES
                  inRectFrom:VT100GridCoordMake(from.x, y)
                          to:VT100GridCoordMake(to.x, y)];
    }
}

- (void)copyCharsFromGrid:(VT100Grid *)otherGrid {
    if (otherGrid == self) {
        return;
    }
    [self setSize:otherGrid.size];
    for (int i = 0; i < size_.height; i++) {
        screen_char_t *dest = [self screenCharsAtLineNumber:i];
        screen_char_t *source = [otherGrid screenCharsAtLineNumber:i];
        memmove(dest,
                source,
                sizeof(screen_char_t) * (size_.width + 1));
    }
    [self markAllCharsDirty:YES];
}

- (int)scrollLeft {
    return scrollRegionCols_.location;
}

- (int)scrollRight {
    return VT100GridRangeMax(scrollRegionCols_);
}

- (int)appendCharsAtCursor:(screen_char_t *)buffer
                    length:(int)len
   scrollingIntoLineBuffer:(LineBuffer *)lineBuffer
       unlimitedScrollback:(BOOL)unlimitedScrollback
   useScrollbackWithRegion:(BOOL)useScrollbackWithRegion {
    int numDropped = 0;
    assert(buffer);
    int idx;  // Index into buffer
    int charsToInsert;
    int newx;
    int leftMargin, rightMargin;
    screen_char_t *aLine;
    const int scrollLeft = self.scrollLeft;
    const int scrollRight = self.scrollRight;

    // Iterate over each character in the buffer and copy/insert into screen.
    // Grab a block of consecutive characters up to the remaining length in the
    // line and append them at once.
    for (idx = 0; idx < len; )  {
        int startIdx = idx;
#ifdef VERBOSE_STRING
        NSLog(@"Begin inserting line. cursor_.x=%d, WIDTH=%d", cursor_.x, WIDTH);
#endif
        NSAssert(buffer[idx].code != DWC_RIGHT, @"DWC cut off");

        if (buffer[idx].code == DWC_SKIP) {
            // I'm pretty sure this can never happen and that this code is just a historical leftover.
            // This is an invalid unicode character that iTerm2 has appropriated
            // for internal use. Change it to something invalid but safe.
            buffer[idx].code = BOGUS_CHAR;
        }
        int widthOffset;
        if (idx + 1 < len && buffer[idx + 1].code == DWC_RIGHT) {
            // If we're about to insert a double width character then reduce the
            // line width for the purposes of testing if the cursor is in the
            // rightmost position.
            widthOffset = 1;
#ifdef VERBOSE_STRING
            NSLog(@"The first char we're going to insert is a DWC");
#endif
        } else {
            widthOffset = 0;
        }

        if (useScrollRegionCols_ && cursor_.x <= scrollRight + 1) {
            // If the cursor is at the left of right margin,
            // the text run stops (or wraps) at right margin.
            // And if a text wraps at right margin,
            // the next line starts from left margin.
            //
            // TODO:
            //    Above behavior is compatible with xterm, but incompatible with VT525.
            //    VT525 have curious glitch:
            //        If a text run which starts from the left of left margin
            //        wraps or returns by CR, the next line starts from column 1, but not left margin.
            //        (see Mr. IWAMOTO's gist https://gist.github.com/ttdoda/5902671)
            //    Now we do not implement this behavior because it is hard to emulate that.
            //
            leftMargin = scrollLeft;
            rightMargin = scrollRight + 1;
        } else {
            leftMargin = 0;
            rightMargin = size_.width;
        }
        if (cursor_.x >= rightMargin - widthOffset) {
            if ([delegate_ wraparoundMode]) {
                if (leftMargin == 0 && rightMargin == size_.width) {
                    // Set the continuation marker
                    screen_char_t* prevLine = [self screenCharsAtLineNumber:cursor_.y];
                    BOOL splitDwc = (cursor_.x == size_.width - 1);
                    prevLine[size_.width].code = (splitDwc ? EOL_DWC : EOL_SOFT);
                    if (splitDwc) {
                        prevLine[size_.width].code = EOL_DWC;
                        prevLine[size_.width - 1].code = DWC_SKIP;
                    }
                }
                self.cursorX = leftMargin;
                // Advance to the next line
                numDropped += [self moveCursorDownOneLineScrollingIntoLineBuffer:lineBuffer
                                                             unlimitedScrollback:unlimitedScrollback
                                                         useScrollbackWithRegion:useScrollbackWithRegion];

#ifdef VERBOSE_STRING
                NSLog(@"Advance cursor to next line");
#endif
            } else {
                // Wraparound is off.
                // That means all the characters are effectively inserted at the
                // rightmost position. Move the cursor to the end of the line
                // and insert the last character there.

                // Clear the continuation marker
                [self screenCharsAtLineNumber:cursor_.y][size_.width].code = EOL_HARD;
                // Cause the loop to end after this character.
                int ncx = size_.width - 1;

                idx = len - 1;
                if (buffer[idx].code == DWC_RIGHT && idx > startIdx) {
                    // The last character to insert is double width. Back up one
                    // byte in buffer and move the cursor left one position.
                    idx--;
                    ncx--;
                }
                if (ncx < 0) {
                    ncx = 0;
                }
                self.cursorX = ncx;
                screen_char_t *line = [self screenCharsAtLineNumber:cursor_.y];
                if (line[cursor_.x].code == DWC_RIGHT) {
                    // This would cause us to overwrite the second part of a
                    // double-width character. Convert it to a space.
                    line[cursor_.x - 1].code = 0;
                    line[cursor_.x - 1].complexChar = NO;
                }

#ifdef VERBOSE_STRING
                NSLog(@"Scribbling on last position");
#endif
            }
        }
        const int spaceRemainingInLine = rightMargin - cursor_.x;
        const int charsLeftToAppend = len - idx;

#ifdef VERBOSE_STRING
        DumpBuf(buffer + idx, charsLeftToAppend);
#endif
        BOOL wrapDwc = NO;
#ifdef VERBOSE_STRING
        NSLog(@"There is %d space left in the line and we are appending %d chars",
              spaceRemainingInLine, charsLeftToAppend);
#endif
        int effective_width;
        if (useScrollRegionCols_) {
            effective_width = size_.width;
        } else {
            effective_width = scrollRight + 1;
        }
        if (spaceRemainingInLine <= charsLeftToAppend) {
#ifdef VERBOSE_STRING
            NSLog(@"Not enough space in the line for everything we want to append.");
#endif
            // There is enough text to at least fill the line. Place the cursor
            // at the end of the line.
            int potentialCharsToInsert = spaceRemainingInLine;
            if (idx + potentialCharsToInsert < len &&
                buffer[idx + potentialCharsToInsert].code == DWC_RIGHT) {
                // If we filled the line all the way out to WIDTH a DWC would be
                // split. Wrap the DWC around to the next line.
#ifdef VERBOSE_STRING
                NSLog(@"Dropping a char from the end to avoid splitting a DWC.");
#endif
                wrapDwc = YES;
                newx = rightMargin - 1;
                --effective_width;
            } else {
#ifdef VERBOSE_STRING
                NSLog(@"Inserting up to the end of the line only.");
#endif
                newx = rightMargin;
            }
        } else {
            // This is the last iteration through this loop and we will not
            // advance to another line. Place the cursor at the end of the line
            // where it should be after appending is complete.
            newx = cursor_.x + charsLeftToAppend;
#ifdef VERBOSE_STRING
            NSLog(@"All remaining chars fit.");
#endif
        }

        // Get the number of chars to insert this iteration (no more than fit
        // on the current line).
        charsToInsert = newx - cursor_.x;
#ifdef VERBOSE_STRING
        NSLog(@"Will insert %d chars", charsToInsert);
#endif
        if (charsToInsert <= 0) {
            //NSLog(@"setASCIIString: output length=0?(%d+%d)%d+%d",cursor_.x,charsToInsert,idx2,len);
            break;
        }

        int lineNumber = cursor_.y;
        aLine = [self screenCharsAtLineNumber:cursor_.y];

        if ([delegate_ insertMode]) {
            if (cursor_.x + charsToInsert < rightMargin) {
#ifdef VERBOSE_STRING
                NSLog(@"Shifting old contents to the right");
#endif
                // Shift the old line contents to the right by 'charsToInsert' positions.
                screen_char_t* src = aLine + cursor_.x;
                screen_char_t* dst = aLine + cursor_.x + charsToInsert;
                int elements = rightMargin - cursor_.x - charsToInsert;
                if (cursor_.x > 0 && src[0].code == DWC_RIGHT) {
                    // The insert occurred in the middle of a DWC.
                    src[-1].code = 0;
                    src[-1].complexChar = NO;
                    src[0].code = 0;
                    src[0].complexChar = NO;
                }
                if (src[elements].code == DWC_RIGHT) {
                    // Moving a DWC on top of its right half. Erase the DWC.
                    src[elements - 1].code = 0;
                    src[elements - 1].complexChar = NO;
                } else if (src[elements].code == DWC_SKIP &&
                           aLine[size_.width].code == EOL_DWC) {
                    // Stomping on a DWC_SKIP. Join the lines normally.
                    aLine[size_.width].code = EOL_SOFT;
                }
                memmove(dst, src, elements * sizeof(screen_char_t));
                [self markCharsDirty:YES
                          inRectFrom:VT100GridCoordMake(cursor_.x, lineNumber)
                                  to:VT100GridCoordMake(rightMargin - 1, lineNumber)];
            }
        }

        // Overwriting the second-half of a double-width character so turn the
        // DWC into a space.
        if (aLine[cursor_.x].code == DWC_RIGHT) {
#ifdef VERBOSE_STRING
            NSLog(@"Wiping out the right-half DWC at the cursor before writing to screen");
#endif
            NSAssert(cursor_.x > 0, @"DWC split");  // there should never be the second half of a DWC at x=0
            aLine[cursor_.x].code = 0;
            aLine[cursor_.x].complexChar = NO;
            aLine[cursor_.x-1].code = 0;
            aLine[cursor_.x-1].complexChar = NO;
            [self markCharDirty:YES
                             at:VT100GridCoordMake(cursor_.x, lineNumber)
                updateTimestamp:YES];
            [self markCharDirty:YES
                             at:VT100GridCoordMake(cursor_.x - 1, lineNumber)
                updateTimestamp:YES];
        }

        // This is an ugly little optimization--if we're inserting just one character, see if it would
        // change anything (because the memcmp is really cheap). In particular, this helps vim out because
        // it really likes redrawing pane separators when it doesn't need to.
        if (charsToInsert > 1 ||
            memcmp(aLine + cursor_.x, buffer + idx, charsToInsert * sizeof(screen_char_t))) {
            // copy charsToInsert characters into the line and set them dirty.
            memcpy(aLine + cursor_.x,
                   buffer + idx,
                   charsToInsert * sizeof(screen_char_t));
            [self markCharsDirty:YES
                      inRectFrom:VT100GridCoordMake(cursor_.x, lineNumber)
                              to:VT100GridCoordMake(cursor_.x + charsToInsert - 1, lineNumber)];
        }
        if (wrapDwc) {
            if (cursor_.x + charsToInsert == size_.width - 1) {
                aLine[cursor_.x + charsToInsert].code = DWC_SKIP;
            } else {
                aLine[cursor_.x + charsToInsert].code = 0;
            }
            aLine[cursor_.x + charsToInsert].complexChar = NO;
        }
        self.cursorX = newx;
        idx += charsToInsert;

        // Overwrote some stuff that was already on the screen leaving behind the
        // second half of a DWC
        if (cursor_.x < size_.width - 1 && aLine[cursor_.x].code == DWC_RIGHT) {
            aLine[cursor_.x].code = 0;
            aLine[cursor_.x].complexChar = NO;
        }

        // The next char in the buffer shouldn't be DWC_RIGHT because we
        // wouldn't have inserted its first half due to a check at the top.
        assert(!(idx < len && buffer[idx].code == DWC_RIGHT));

        // ANSI terminals will go to a new line after displaying a character at
        // the rightmost column.
        if (cursor_.x >= effective_width && [delegate_ isAnsi]) {
            if ([delegate_ wraparoundMode]) {
                //set the wrapping flag
                aLine[size_.width].code = ((effective_width == size_.width) ? EOL_SOFT : EOL_DWC);
                self.cursorX = leftMargin;
                numDropped += [self moveCursorDownOneLineScrollingIntoLineBuffer:lineBuffer
                                                             unlimitedScrollback:unlimitedScrollback
                                                         useScrollbackWithRegion:useScrollbackWithRegion];
            } else {
                self.cursorX = rightMargin - 1;
                if (idx < len - 1) {
                    // Iterate once more to draw the last character at the end
                    // of the line.
                    idx = len - 1;
                } else {
                    // Break out of the loop after the last character is drawn.
                    idx = len;
                }
            }
        }
    }

    return numDropped;
}

- (void)deleteChars:(int)n
         startingAt:(VT100GridCoord)startCoord {
    DLog(@"deleteChars:%d startingAt:%d,%d", n, startCoord.x, startCoord.y);

    screen_char_t *aLine;
    const int leftMargin = [self leftMargin];
    const int rightMargin = [self rightMargin];
    screen_char_t defaultChar = [self defaultChar];

    if (startCoord.x >= leftMargin &&
        startCoord.x < rightMargin &&
        startCoord.y >= 0 &&
        startCoord.y < size_.height) {
        int lineNumber = startCoord.y;
        if (n + startCoord.x > rightMargin) {
            n = rightMargin - startCoord.x + 1;
        }

        // get the appropriate screen line
        aLine = [self screenCharsAtLineNumber:startCoord.y];

        if (n > 0 && startCoord.x + n <= rightMargin) {
            // Erase a section in the middle of a line. Shift the stuff to the right of the
            // deletion region left to the startCoord.

            // Deleting right half of DWC at startCoord?
            [self erasePossibleDoubleWidthCharInLineNumber:startCoord.y
                                          startingAtOffset:startCoord.x - 1
                                                  withChar:[self defaultChar]];

            // Deleting left half of DWC at end of run to be deleted?
            [self erasePossibleDoubleWidthCharInLineNumber:startCoord.y
                                          startingAtOffset:startCoord.x + n - 1
                                                  withChar:[self defaultChar]];

            // When there's a scroll region, are we moving the left half of a DWC w/o right half?
            [self erasePossibleDoubleWidthCharInLineNumber:startCoord.y
                                          startingAtOffset:self.rightMargin
                                                  withChar:[self defaultChar]];
            const int numCharsToMove = rightMargin - startCoord.x - n + 1;

            // Try to clean up DWC_SKIP+EOL_DWC pair, if needed.
            if (rightMargin == size_.width - 1 &&
                aLine[rightMargin].code == DWC_SKIP) {
                // Moving DWC_SKIP left will break it.
                aLine[rightMargin].code = 0;
            }
            if (rightMargin == size_.width - 1 &&
                aLine[size_.width].code == EOL_DWC) {
                // When the previous if statement is true, this one should also always be true.
                aLine[size_.width].code = EOL_HARD;
            }

            memmove(aLine + startCoord.x,
                    aLine + startCoord.x + n,
                    numCharsToMove * sizeof(screen_char_t));
            [self markCharsDirty:YES
                      inRectFrom:VT100GridCoordMake(startCoord.x, lineNumber)
                              to:VT100GridCoordMake(startCoord.x + numCharsToMove - 1, lineNumber)];
            // Erase chars on right side of line.
        }
        [self setCharsFrom:VT100GridCoordMake(rightMargin - n + 1, lineNumber)
                        to:VT100GridCoordMake(rightMargin, lineNumber)
                    toChar:defaultChar];
    }
}

- (void)scrollDown {
    [self scrollRect:[self scrollRegionRect] downBy:1];
}

- (void)scrollRect:(VT100GridRect)rect downBy:(int)distance {
    DLog(@"scrollRect:%d,%d %dx%d downBy:%d",
             rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, distance);
    if (distance == 0) {
        return;
    }
    int direction = (distance > 0) ? 1 : -1;

    screen_char_t defaultChar = [self defaultChar];

    if (rect.size.width > 0 && rect.size.height > 0) {
        int rightIndex = rect.origin.x + rect.size.width - 1;
        int bottomIndex = rect.origin.y + rect.size.height - 1;
        int sourceHeight = rect.size.height - abs(distance);
        int sourceIndex = (direction > 0 ? bottomIndex - distance :
                           rect.origin.y - distance);
        int destIndex = direction > 0 ? bottomIndex : rect.origin.y;
        int continuation = (rightIndex == size_.width - 1) ? 1 : 0;

        // Fix up split DWCs that will be broken.
        if (continuation) {
            // The last line scrolled may have had a split-dwc. Replace its continuation mark with a hard
            // newline.
            [self erasePossibleSplitDwcAtLineNumber:bottomIndex];
            [self erasePossibleSplitDwcAtLineNumber:rect.origin.y - 1];
        }

        // clear DWC's that are about to get orphaned
        int si = sourceIndex;
        int di = destIndex;
        for (int iteration = 0; iteration < rect.size.height; iteration++) {
            const int lineNumber = iteration + rect.origin.y;
            [self erasePossibleDoubleWidthCharInLineNumber:lineNumber
                                          startingAtOffset:rect.origin.x - 1
                                                  withChar:defaultChar];
            [self erasePossibleDoubleWidthCharInLineNumber:lineNumber
                                          startingAtOffset:rightIndex
                                                  withChar:defaultChar];
            si -= direction;
            di -= direction;
        }

        // Move lines.
        for (int iteration = 0; (iteration < sourceHeight &&
                                 sourceIndex < size_.height &&
                                 destIndex < size_.height &&
                                 sourceIndex >= 0 &&
                                 destIndex >= 0);
             iteration++) {
            screen_char_t *sourceLine = [self screenCharsAtLineNumber:sourceIndex];
            screen_char_t *targetLine = [self screenCharsAtLineNumber:destIndex];

            memmove(targetLine + rect.origin.x,
                    sourceLine + rect.origin.x,
                    (rect.size.width + continuation) * sizeof(screen_char_t));

            sourceIndex -= direction;
            destIndex -= direction;
        }

        [self markCharsDirty:YES
                  inRectFrom:rect.origin
                          to:VT100GridCoordMake(rightIndex, bottomIndex)];

        int lineNumberAboveScrollRegion = rect.origin.y - 1;
        // Fix up broken soft or dwc_skip continuation marks. It could occur on line just above
        // the scroll region.
        if (lineNumberAboveScrollRegion >= 0 &&
            lineNumberAboveScrollRegion < size_.height &&
            rect.origin.x == 0) {
            // Affecting continuation marks on line above/below rect.
            screen_char_t *pred =
                [self screenCharsAtLineNumber:lineNumberAboveScrollRegion];
            if (pred[size_.width].code == EOL_SOFT) {
                pred[size_.width].code = EOL_HARD;
            }
        }
        if (rect.origin.x + rect.size.width == size_.width) {
            // Clean up continuation mark on last line inside scroll region when scrolling down,
            // or last last preserved line when scrolling up.
            int lastLineOfScrollRegion;
            if (direction > 0) {
                lastLineOfScrollRegion = rect.origin.y + rect.size.height - 1;
            } else {
                lastLineOfScrollRegion = rect.origin.y + rect.size.height - 1 + distance;
            }
            // Affecting continuation mark on first/last line in block
            if (lastLineOfScrollRegion >= 0 && lastLineOfScrollRegion < size_.height) {
                screen_char_t *lastLine =
                    [self screenCharsAtLineNumber:lastLineOfScrollRegion];
                if (lastLine[size_.width].code == EOL_SOFT) {
                    lastLine[size_.width].code = EOL_HARD;
                }
            }
        }

        // Clear region left over.
        if (direction > 0) {
            [self setCharsFrom:rect.origin
                            to:VT100GridCoordMake(rightIndex, MIN(bottomIndex, rect.origin.y + distance - 1))
                        toChar:defaultChar];
        } else {
            [self setCharsFrom:VT100GridCoordMake(rect.origin.x, MAX(rect.origin.y, bottomIndex + distance + 1))
                            to:VT100GridCoordMake(rightIndex, bottomIndex)
                        toChar:defaultChar];
        }

        if ((rect.origin.x == 0) ^ continuation) {
            // It's possible that either a continuation mark is being moved or a DWC was moved
            // (but not both!), causing a split-dwc continuation mark to become invalid.
            for (int iteration = 0; iteration < rect.size.height; iteration++) {
                [self erasePossibleSplitDwcAtLineNumber:iteration + rect.origin.y];
            }
        }

        // Clean up split-dwc continuation marker on last line if scrolling down, or line before
        // rectangle if scrolling up.
        if (continuation && rect.origin.x == 0) {
            // Moving whole lines
            if (direction > 0) {
                // scrolling down
                [self erasePossibleSplitDwcAtLineNumber:rect.origin.y + rect.size.height - 1];
            } else {
                // scrolling up
                [self erasePossibleSplitDwcAtLineNumber:rect.origin.y - 1];
            }
        }
    }
}

- (void)setContentsFromDVRFrame:(screen_char_t*)s info:(DVRFrameInfo)info
{
    [self setCharsFrom:VT100GridCoordMake(0, 0)
                    to:VT100GridCoordMake(size_.width - 1, size_.height - 1)
                toChar:[self defaultChar]];
    int charsToCopyPerLine = MIN(size_.width, info.width);
    if (size_.width == info.width) {
        // Ok to copy continuation mark.
        charsToCopyPerLine++;
    }
    int sourceLineOffset = 0;
    if (info.height > size_.height) {
        sourceLineOffset = info.height - size_.height;
    }
    if (info.height < size_.height || info.width < size_.width) {
        [self setCharsFrom:VT100GridCoordMake(0, 0)
                        to:VT100GridCoordMake(size_.width - 1, size_.height - 1)
                    toChar:[self defaultChar]];
    }
    for (int y = 0; y < MIN(info.height, size_.height); y++) {
        screen_char_t *dest = [self screenCharsAtLineNumber:y];
        screen_char_t *src = s + ((y + sourceLineOffset) * (info.width + 1));
        memmove(dest, src, sizeof(screen_char_t) * charsToCopyPerLine);
        if (size_.width != info.width) {
            // Not copying continuation marks, set them all to hard.
            dest[size_.width].code = EOL_HARD;
        }
        if (charsToCopyPerLine < info.width && src[charsToCopyPerLine].code == DWC_RIGHT) {
            dest[charsToCopyPerLine - 1].code = 0;
            dest[charsToCopyPerLine - 1].complexChar = NO;
        }
        if (charsToCopyPerLine - 1 < info.width && src[charsToCopyPerLine - 1].code == TAB_FILLER) {
            dest[charsToCopyPerLine - 1].code = '\t';
            dest[charsToCopyPerLine - 1].complexChar = NO;
        }
    }
    [self markAllCharsDirty:YES];

    const int yOffset = MAX(0, info.height - size_.height);
    self.cursorX = MIN(size_.width - 1, MAX(0, info.cursorX));
    self.cursorY = MIN(size_.height - 1, MAX(0, info.cursorY - yOffset));
}

- (NSString*)debugString
{
    NSMutableString* result = [NSMutableString stringWithString:@""];
    int x, y;
    char line[1000];
    char dirtyline[1000];
    for (y = 0; y < size_.height; ++y) {
        int ox = 0;
        screen_char_t* p = [self screenCharsAtLineNumber:y];
        if (y == screenTop_) {
            [result appendString:@"--- top of buffer ---\n"];
        }
        for (x = 0; x < size_.width; ++x, ++ox) {
            if ([self isCharDirtyAt:VT100GridCoordMake(x, y)]) {
                dirtyline[ox] = '-';
            } else {
                dirtyline[ox] = '.';
            }
            if (y == cursor_.y && x == cursor_.x) {
                if (dirtyline[ox] == '-') {
                    dirtyline[ox] = '=';
                }
                if (dirtyline[ox] == '.') {
                    dirtyline[ox] = ':';
                }
            }
            if (p[x].code && !p[x].complexChar) {
                if (p[x].code > 0 && p[x].code < 128) {
                    line[ox] = p[x].code;
                } else if (p[x].code == DWC_RIGHT) {
                    line[ox] = '-';
                } else if (p[x].code == TAB_FILLER) {
                    line[ox] = ' ';
                } else if (p[x].code == DWC_SKIP) {
                    line[ox] = '>';
                } else {
                    line[ox] = '?';
                }
            } else {
                line[ox] = '.';
            }
        }
        line[x] = 0;
        dirtyline[x] = 0;
        [result appendFormat:@"%04d: %s %@\n", y, line, [self stringForContinuationMark:p[size_.width].code]];
        [result appendFormat:@"dirty %s\n", dirtyline];
    }
    return result;
}

- (NSArray *)runsMatchingRegex:(NSString *)regex {
    NSMutableArray *runs = [NSMutableArray array];

    int y = 0;
    while (y < size_.height) {
        int numLines;
        unichar *backingStore;
        int *deltas;

        NSString *joinedLine = [self joinedLineBeginningAtLineNumber:y
                                                         numLinesPtr:&numLines
                                                     backingStorePtr:&backingStore
                                                           deltasPtr:&deltas];
        NSRange searchRange = NSMakeRange(0, joinedLine.length);
        NSRange range;
        while (1) {
            range = [joinedLine rangeOfRegex:regex
                                     options:0
                                     inRange:searchRange
                                     capture:0
                                       error:nil];
            if (range.location == NSNotFound || range.length == 0) {
                break;
            }
            assert(range.location != NSNotFound);
            int start = (int)(range.location);
            int end = (int)(range.location + range.length - 1);
            start += deltas[start];
            end += deltas[end];
            int startY = y + start / size_.width;
            int startX = start % size_.width;
            int endY = y + end / size_.width;
            int endX = end % size_.width;

            if (endY >= size_.height) {
                endY = size_.height - 1;
                endX = size_.width;
            }
            if (startY < size_.height) {
                int length = [self numCellsFrom:VT100GridCoordMake(startX, startY)
                                             to:VT100GridCoordMake(endX, endY)];
                NSValue *value = [NSValue valueWithGridRun:VT100GridRunMake(startX,
                                                                            startY,
                                                                            length)];
                [runs addObject:value];
            }

            searchRange.location = range.location + range.length;
            searchRange.length = joinedLine.length - searchRange.location;
        }
        y += numLines;
        free(backingStore);
        free(deltas);
    }

    return runs;
}

- (void)restoreScreenFromLineBuffer:(LineBuffer *)lineBuffer
                    withDefaultChar:(screen_char_t)defaultChar
                  maxLinesToRestore:(int)maxLines
{
    // Move scrollback lines into screen
    int numLinesInLineBuffer = [lineBuffer numLinesWithWidth:size_.width];
    int destLineNumber;
    if (numLinesInLineBuffer >= size_.height) {
        destLineNumber = size_.height - 1;
    } else {
        destLineNumber = numLinesInLineBuffer - 1;
    }
    destLineNumber = MIN(destLineNumber, maxLines - 1);

    screen_char_t *defaultLine = [[self lineOfWidth:size_.width
                                     filledWithChar:defaultChar] mutableBytes];

    BOOL foundCursor = NO;
    BOOL prevLineStartsWithDoubleWidth = NO;
    int numPopped = 0;
    while (destLineNumber >= 0) {
        screen_char_t *dest = [self screenCharsAtLineNumber:destLineNumber];
        memcpy(dest, defaultLine, sizeof(screen_char_t) * size_.width);
        if (!foundCursor) {
            int tempCursor = cursor_.x;
            foundCursor = [lineBuffer getCursorInLastLineWithWidth:size_.width atX:&tempCursor];
            if (foundCursor) {
                [self setCursor:VT100GridCoordMake(tempCursor % size_.width,
                                                   destLineNumber + tempCursor / size_.width)];
            }
        }
        int cont;
        NSTimeInterval timestamp;
        ++numPopped;
        assert([lineBuffer popAndCopyLastLineInto:dest
                                            width:size_.width
                                includesEndOfLine:&cont
                                        timestamp:&timestamp]);
        [[self lineInfoAtLineNumber:destLineNumber] setTimestamp:timestamp];
        if (cont && dest[size_.width - 1].code == 0 && prevLineStartsWithDoubleWidth) {
            // If you pop a soft-wrapped line that's a character short and the
            // line below it starts with a DWC, it's safe to conclude that a DWC
            // was wrapped.
            dest[size_.width - 1].code = DWC_SKIP;
            cont = EOL_DWC;
        }
        if (dest[1].code == DWC_RIGHT) {
            prevLineStartsWithDoubleWidth = YES;
        } else {
            prevLineStartsWithDoubleWidth = NO;
        }
        dest[size_.width].code = cont;
        if (cont == EOL_DWC) {
            dest[size_.width - 1].code = DWC_SKIP;
        }
        --destLineNumber;
    }
}


- (void)clampCursorPositionToValid
{
    if (cursor_.x >= size_.width) {
        self.cursorX = size_.width - 1;
    }
    if (cursor_.y >= size_.height) {
        self.cursorY = size_.height - 1;
    }
}

- (screen_char_t *)resultLine {
    const int length = sizeof(screen_char_t) * (size_.width + 1);
    if (resultLine_.length != length) {
        [resultLine_ release];
        resultLine_ = [[NSMutableData alloc] initWithLength:length];
    }
    return (screen_char_t *)[resultLine_ mutableBytes];
}

- (void)moveCursorToLeftMargin {
    const int leftMargin = [self leftMargin];
    self.cursorX = leftMargin;
}

- (NSArray *)rectsForRun:(VT100GridRun)run {
    NSMutableArray *rects = [NSMutableArray array];
    int length = run.length;
    int x = run.origin.x;
    for (int y = run.origin.y; length > 0; y++) {
        int endX = MIN(size_.width - 1, x + length - 1);
        [rects addObject:[NSValue valueWithGridRect:VT100GridRectMake(x, y, endX - x + 1, 1)]];
        length -= (endX - x + 1);
        x = 0;
    }
    assert(length >= 0);
    return rects;
}

- (int)leftMargin {
    return useScrollRegionCols_ ? scrollRegionCols_.location : 0;
}

- (int)rightMargin {
    return useScrollRegionCols_ ? VT100GridRangeMax(scrollRegionCols_) : size_.width - 1;
}

- (int)topMargin {
    return scrollRegionRows_.location;
}

- (int)bottomMargin {
    return VT100GridRangeMax(scrollRegionRows_);
}

- (VT100GridRect)scrollRegionRect {
    return VT100GridRectMake(self.leftMargin,
                             self.topMargin,
                             self.rightMargin - self.leftMargin + 1,
                             self.bottomMargin - self.topMargin + 1);
}

// . = null cell
// ? = non-ascii
// - = righthalf of dwc
// > = split-dwc (in rightmost column only)
// U = complex unicode char
// anything else = literal ascii char
- (NSString *)compactLineDump {
    NSMutableString *dump = [NSMutableString string];
    for (int y = 0; y < size_.height; y++) {
        screen_char_t *line = [self screenCharsAtLineNumber:y];
        for (int x = 0; x < size_.width; x++) {
            char c = line[x].code;
            if (line[x].code == 0) c = '.';
            if (line[x].code > 127) c = '?';
            if (line[x].code == DWC_RIGHT) c = '-';
            if (line[x].code == DWC_SKIP) {
                assert(x == size_.width - 1);
                c = '>';
            }
            if (line[x].complexChar) c = 'U';
            [dump appendFormat:@"%c", c];
        }
        if (y != size_.height - 1) {
            [dump appendString:@"\n"];
        }
    }
    return dump;
}

- (NSString *)compactLineDumpWithTimestamps {
    NSMutableString *dump = [NSMutableString string];
    NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
    [fmt setTimeStyle:NSDateFormatterLongStyle];

    for (int y = 0; y < size_.height; y++) {
        screen_char_t *line = [self screenCharsAtLineNumber:y];
        for (int x = 0; x < size_.width; x++) {
            char c = line[x].code;
            if (line[x].code == 0) c = '.';
            if (line[x].code > 127) c = '?';
            if (line[x].code == DWC_RIGHT) c = '-';
            if (line[x].code == DWC_SKIP) {
                assert(x == size_.width - 1);
                c = '>';
            }
            if (line[x].complexChar) c = 'U';
            [dump appendFormat:@"%c", c];
        }
        NSDate* date = [NSDate dateWithTimeIntervalSinceReferenceDate:[[self lineInfoAtLineNumber:y] timestamp]];
        [dump appendFormat:@"  | %@", [fmt stringFromDate:date]];
        if (y != size_.height - 1) {
            [dump appendString:@"\n"];
        }
    }
    return dump;
}

- (NSString *)compactLineDumpWithContinuationMarks {
    NSMutableString *dump = [NSMutableString string];
    for (int y = 0; y < size_.height; y++) {
        screen_char_t *line = [self screenCharsAtLineNumber:y];
        for (int x = 0; x < size_.width; x++) {
            char c = line[x].code;
            if (line[x].code == 0) c = '.';
            if (line[x].code > 127) c = '?';
            if (line[x].code == DWC_RIGHT) c = '-';
            if (line[x].code == DWC_SKIP) {
                assert(x == size_.width - 1);
                c = '>';
            }
            if (line[x].complexChar) c = 'U';
            [dump appendFormat:@"%c", c];
        }
        switch (line[size_.width].code) {
            case EOL_HARD:
                [dump appendString:@"!"];
                break;
            case EOL_SOFT:
                [dump appendString:@"+"];
                break;
            case EOL_DWC:
                [dump appendString:@">"];
                break;
            default:
                [dump appendString:@"?"];
                break;
        }
        if (y != size_.height - 1) {
            [dump appendString:@"\n"];
        }
    }
    return dump;
}

- (NSString *)compactDirtyDump {
    NSMutableString *dump = [NSMutableString string];
    for (int y = 0; y < size_.height; y++) {
        for (int x = 0; x < size_.width; x++) {
            if ([self isCharDirtyAt:VT100GridCoordMake(x, y)]) {
                [dump appendString:@"d"];
            } else {
                [dump appendString:@"c"];
            }
        }
        if (y != size_.height - 1) {
            [dump appendString:@"\n"];
        }
    }
    return dump;
}

- (void)insertChar:(screen_char_t)c at:(VT100GridCoord)pos times:(int)n {
    if (pos.x > self.rightMargin ||  // TODO: Test right-margin boundary case
        pos.x < self.leftMargin) {
        return;
    }
    if (n + pos.x > self.rightMargin) {
        n = self.rightMargin - pos.x + 1;
    }
    if (n < 1) {
        return;
    }

    screen_char_t *line = [self screenCharsAtLineNumber:pos.y];
    int charsToMove = self.rightMargin - pos.x - n + 1;

    // Splitting a dwc in half?
    [self erasePossibleDoubleWidthCharInLineNumber:pos.y
                                  startingAtOffset:pos.x - 1
                                          withChar:[self defaultChar]];

    // If the last char to be moved is the left half of a DWC, erase it.
    [self erasePossibleDoubleWidthCharInLineNumber:pos.y
                                  startingAtOffset:pos.x + charsToMove - 1
                                          withChar:[self defaultChar]];

    // When there's a scroll region, does the right margin overlap half a dwc?
    [self erasePossibleDoubleWidthCharInLineNumber:pos.y
                                  startingAtOffset:self.rightMargin
                                          withChar:[self defaultChar]];

    memmove(line + pos.x + n,
            line + pos.x,
            charsToMove * sizeof(screen_char_t));

    // Try to clean up DWC_SKIP+EOL_DWC pair, if needed.
    if (self.rightMargin == size_.width - 1 &&
        line[size_.width].code == EOL_DWC) {
        // The line shifting means a split DWC is gone. The wrapping changes to hard if the last
        // code is 0 because soft wrapping doesn't make sense across a null code.
        line[size_.width].code = line[size_.width - 1].code ? EOL_SOFT : EOL_HARD;
    }

    if (size_.width > 0 &&
        self.rightMargin == size_.width - 1 &&
        line[size_.width].code == EOL_SOFT &&
        line[size_.width - 1].code == 0) {
        // If the last char becomes a null, convert to a hard line break.
        line[size_.width].code = EOL_HARD;
    }

    [self markCharsDirty:YES
              inRectFrom:VT100GridCoordMake(MIN(self.rightMargin - 1, pos.x), pos.y)
                      to:VT100GridCoordMake(self.rightMargin, pos.y)];
    [self setCharsFrom:pos to:VT100GridCoordMake(pos.x + n - 1, pos.y) toChar:c];
}

- (NSArray *)orderedLines {
    NSMutableArray *array = [NSMutableArray array];
    for (int i = 0; i < size_.height; i++) {
        [array addObject:[self lineDataAtLineNumber:i]];
    }
    return array;
}

#pragma mark - Private

- (NSMutableArray *)linesWithSize:(VT100GridSize)size {
    NSMutableArray *lines = [[[NSMutableArray alloc] init] autorelease];
    for (int i = 0; i < size.height; i++) {
        [lines addObject:[[[self defaultLineOfWidth:size.width] mutableCopy] autorelease]];
    }
    return lines;
}

- (NSMutableArray *)lineInfosWithSize:(VT100GridSize)size {
    NSMutableArray *dirty = [NSMutableArray array];
    for (int i = 0; i < size.height; i++) {
        [dirty addObject:[[[VT100LineInfo alloc] initWithWidth:size_.width] autorelease]];
    }
    return dirty;
}

- (screen_char_t)defaultChar {
    assert(delegate_);
    screen_char_t c = { 0 };
    screen_char_t fg = [delegate_ foregroundColorCodeReal];
    screen_char_t bg = [delegate_ backgroundColorCodeReal];

    c.code = 0;
    c.complexChar = NO;
    CopyForegroundColor(&c, fg);
    CopyBackgroundColor(&c, bg);

    return c;
}

- (NSMutableData *)lineOfWidth:(int)width filledWithChar:(screen_char_t)c {
    NSMutableData *data = [NSMutableData dataWithLength:sizeof(screen_char_t) * (width + 1)];
    screen_char_t *line = data.mutableBytes;
    for (int i = 0; i < width + 1; i++) {
        line[i] = c;
    }
    return data;
}

- (NSMutableData *)defaultLineOfWidth:(int)width {
    size_t length = (width + 1) * sizeof(screen_char_t);

    screen_char_t *existingCache = (screen_char_t *)[cachedDefaultLine_ mutableBytes];
    screen_char_t currentDefaultChar = [self defaultChar];
    if (cachedDefaultLine_ &&
        [cachedDefaultLine_ length] == length &&
        length > 0 &&
        !memcmp(existingCache, &currentDefaultChar, sizeof(screen_char_t))) {
        return cachedDefaultLine_;
    }

    NSMutableData *line = [NSMutableData dataWithLength:length];

    [self clearLineData:line];

    [cachedDefaultLine_ release];
    cachedDefaultLine_ = [line retain];

    return line;
}

// Not double-width char safe.
- (void)clearScreenChars:(screen_char_t *)chars inRange:(VT100GridRange)range {
    screen_char_t c = [self defaultChar];

    for (int i = range.location; i < range.location + range.length; i++) {
        chars[i] = c;
    }
}

- (void)clearLineData:(NSMutableData *)line {
    int length = (int)([line length] / sizeof(screen_char_t));
    [self clearScreenChars:[line mutableBytes] inRange:VT100GridRangeMake(0, length)];
    screen_char_t *chars = (screen_char_t *)[line mutableBytes];
    int width = [line length] / sizeof(screen_char_t) - 1;
    chars[width].code = EOL_HARD;
}

// Returns number of lines dropped from line buffer because it exceeded its size (always 0 or 1).
- (int)appendLineToLineBuffer:(LineBuffer *)lineBuffer
          unlimitedScrollback:(BOOL)unlimitedScrollback {
    if (!lineBuffer) {
        return 0;
    }
    screen_char_t *line = [self screenCharsAtLineNumber:0];
    int len = [self lengthOfLine:line];
    int continuationMark = line[size_.width].code;
    if (continuationMark == EOL_DWC && len == size_.width) {
        --len;
    }
    [lineBuffer appendLine:line
                    length:len
                   partial:(continuationMark != EOL_HARD)
                     width:size_.width
                 timestamp:[[self lineInfoAtLineNumber:0] timestamp]];
    int dropped;
    if (!unlimitedScrollback) {
        dropped = [lineBuffer dropExcessLinesWithWidth:size_.width];
    } else {
        dropped = 0;
    }

    assert(dropped == 0 || dropped == 1);

    return dropped;
}

- (BOOL)haveColumnScrollRegion {
    return (useScrollRegionCols_ &&
            (self.scrollLeft != 0 || self.scrollRight != size_.width - 1));
}

- (BOOL)haveScrollRegion {
    const BOOL haveScrollRows = !(self.topMargin == 0 && self.bottomMargin == size_.height - 1);
    return haveScrollRows || [self haveColumnScrollRegion];
}

- (int)cursorLineNumberIncludingPrecedingWrappedLines {
    for (int i = cursor_.y - 1; i >= 0; i--) {
        int mark = [self continuationMarkForLineNumber:i];
        if (mark == EOL_HARD) {
            return i + 1;
        }
    }
    return 0;
}

// NOTE: Returns -1 if there are no non-empty lines.
- (int)lineNumberOfLastNonEmptyLine {
    int y;
    for (y = size_.height - 1; y >= 0; --y) {
        if ([self lengthOfLineNumber:y] > 0) {
            return y;
        }
    }
    return -1;
}

// Warning: does not set dirty.
- (void)setSize:(VT100GridSize)newSize {
    if (newSize.width != size_.width || newSize.height != size_.height) {
        size_ = newSize;
        [lines_ release];
        [lineInfos_ release];
        lines_ = [[self linesWithSize:newSize] retain];
        lineInfos_ = [[self lineInfosWithSize:newSize] retain];
        scrollRegionRows_.location = MIN(scrollRegionRows_.location, size_.width - 1);
        scrollRegionRows_.length = MIN(scrollRegionRows_.length,
                                       size_.width - scrollRegionRows_.location);
        scrollRegionCols_.location = MIN(scrollRegionCols_.location, size_.height - 1);
        scrollRegionCols_.length = MIN(scrollRegionCols_.length,
                                       size_.height - scrollRegionRows_.location);
        cursor_.x = MIN(cursor_.x, size_.width - 1);
        cursor_.y = MIN(cursor_.y, size_.height - 1);
    }
}

- (VT100GridCoord)coordinateBefore:(VT100GridCoord)coord {
    // set cx, cy to the char before the given coordinate.
    VT100GridCoord invalid = VT100GridCoordMake(-1, -1);
    int cx = coord.x;
    int cy = coord.y;
    if (cx == self.leftMargin || cx == 0) {
        cx = self.rightMargin + 1;
        --cy;
        if (cy < 0) {
            return invalid;
        }
        if (![self haveColumnScrollRegion]) {
            switch ([self continuationMarkForLineNumber:cy]) {
                case EOL_HARD:
                    return invalid;
                case EOL_SOFT:
                    // Ok to wrap around
                    break;
                case EOL_DWC:
                    // Ok to wrap around, but move back over presumed DWC_SKIP at line[rightMargin-1].
                    cx--;
                    if (cx < 0) {
                        return invalid;
                    }
                    break;
            }
        }
    }
    --cx;
    if (cx < 0 || cy < 0) {
        // can't affect characters above screen so have it stand alone. cx really should never be
        // less than zero, but paranoia.
        return invalid;
    }

    screen_char_t *line = [self screenCharsAtLineNumber:cy];
    if (line[cx].code == DWC_RIGHT) {
        if (cx > 0) {
            cx--;
        } else {
            // This should never happen.
            return invalid;
        }
    }

    return VT100GridCoordMake(cx, cy);
}

// Add a combining char to the cell at the cursor position if possible. Returns
// YES if it is able to and NO if there is no base character to combine with.
- (BOOL)addCombiningChar:(unichar)combiningChar toCoord:(VT100GridCoord)coord
{
    int cx = coord.x;
    int cy = coord.y;
    screen_char_t* theLine = [self screenCharsAtLineNumber:cy];
    if (theLine[cx].code == 0 ||
        (theLine[cx].code >= ITERM2_PRIVATE_BEGIN && theLine[cx].code <= ITERM2_PRIVATE_END) ||
        (IsLowSurrogate(combiningChar) && !IsHighSurrogate(theLine[cx].code)) ||
        (!IsLowSurrogate(combiningChar) && IsHighSurrogate(theLine[cx].code))) {
        // Unable to combine.
        return NO;
    }
    if (theLine[cx].complexChar) {
        theLine[cx].code = AppendToComplexChar(theLine[cx].code,
                                               combiningChar);
    } else {
        theLine[cx].code = BeginComplexChar(theLine[cx].code,
                                            combiningChar);
        theLine[cx].complexChar = YES;
    }
    return YES;
}

void DumpBuf(screen_char_t* p, int n) {
    for (int i = 0; i < n; ++i) {
        NSLog(@"%3d: \"%@\" (0x%04x)", i, ScreenCharToStr(&p[i]), (int)p[i].code);
    }
}

- (void)erasePossibleSplitDwcAtLineNumber:(int)lineNumber {
    if (lineNumber < 0) {
        return;
    }
    screen_char_t *line = [self screenCharsAtLineNumber:lineNumber];
    if (line[size_.width].code == EOL_DWC) {
        line[size_.width].code = EOL_HARD;
        if (line[size_.width - 1].code == DWC_SKIP) {  // This really should always be the case.
            line[size_.width - 1].code = 0;
        } else {
            NSLog(@"Warning! EOL_DWC without DWC_SKIP at line %d", lineNumber);
        }
    }
}
- (BOOL)erasePossibleDoubleWidthCharInLineNumber:(int)lineNumber
                                startingAtOffset:(int)offset
                                        withChar:(screen_char_t)c
{
    screen_char_t *aLine = [self screenCharsAtLineNumber:lineNumber];
    if (offset >= 0 && offset < size_.width - 1 && aLine[offset + 1].code == DWC_RIGHT) {
        aLine[offset] = c;
        aLine[offset + 1] = c;
        [self markCharDirty:YES
                         at:VT100GridCoordMake(offset, lineNumber)
            updateTimestamp:YES];
        [self markCharDirty:YES
                         at:VT100GridCoordMake(offset + 1, lineNumber)
            updateTimestamp:YES];

        if (offset == 0 && lineNumber > 0) {
            [self erasePossibleSplitDwcAtLineNumber:lineNumber - 1];
        }

        return YES;
    } else {
        return NO;
    }
}

- (NSString *)stringForContinuationMark:(int)c {
    switch (c) {
        case EOL_HARD:
            return @"[hard]";
        case EOL_SOFT:
            return @"[soft]";
        case EOL_DWC:
            return @"[dwc]";
        default:
            return @"[?]";
    }
}

// Find all the lines starting at startScreenY that have non-hard EOLs. Combine them into a string and return it.
// Store the number of screen lines in *numLines
// Store an array of UTF-16 codes in backingStorePtr, which the caller must free
// Store an array of offsets between chars in the string and screen_char_t indices in deltasPtr, which the caller must free.
- (NSString *)joinedLineBeginningAtLineNumber:(int)startScreenY
                                  numLinesPtr:(int *)numLines
                              backingStorePtr:(unichar **)backingStorePtr  // caller must free
                                    deltasPtr:(int **)deltasPtr            // caller must free
{
    // Count the number of screen lines that have soft/dwc newlines beginning at
    // line startScreenY.
    int limitY;
    for (limitY = startScreenY; limitY < size_.height; limitY++) {
        screen_char_t *screenLine = [self screenCharsAtLineNumber:limitY];
        if (screenLine[size_.width].code == EOL_HARD) {
            break;
        }
    }
    *numLines = limitY - startScreenY + 1;

    // Create a single array of screen_char_t's that has those screen lines
    // concatenated together in "temp".
    NSMutableData *tempData = [NSMutableData dataWithLength:sizeof(screen_char_t) * size_.width * *numLines];
    screen_char_t *temp = (screen_char_t *)[tempData mutableBytes];
    int i = 0;
    for (int y = startScreenY; y <= limitY; y++, i++) {
        screen_char_t *screenLine = [self screenCharsAtLineNumber:y];
        memcpy(temp + size_.width * i,
               screenLine,
               size_.width * sizeof(screen_char_t));
    }

    // Convert "temp" into an NSString. backingStorePtr and deltasPtr are filled
    // in with malloc'ed pointers that the caller must free.
    NSString *screenLine = ScreenCharArrayToString(temp,
                                                   0,
                                                   size_.width * *numLines,
                                                   backingStorePtr,
                                                   deltasPtr);

    return screenLine;
}

// Number of cells between two coords, including both endpoints For example, with a grid of
// xxyy
// yyxx
// The number of cells from (2,0) to (1,1) is 4 (the cells containing "y").
- (int)numCellsFrom:(VT100GridCoord)from to:(VT100GridCoord)to {
    VT100GridRun run = VT100GridRunFromCoords(from, to, size_.width);
    return run.length;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p size=%d x %d, cursor @ (%d,%d)>",
            [self class], self, size_.width, size_.height, cursor_.x, cursor_.y];
}

// Returns NSString representation of line. This exists to faciliate debugging only.
+ (NSString *)stringForScreenChars:(screen_char_t *)theLine length:(int)length
{
    NSMutableString* result = [NSMutableString stringWithCapacity:length];

    for (int i = 0; i < length; i++) {
        [result appendString:ScreenCharToStr(&theLine[i])];
    }

    if (theLine[length].code) {
        [result appendString:@"\n"];
    }

    return result;
}

- (void)resetScrollRegions {
    scrollRegionRows_ = VT100GridRangeMake(0, size_.height);
    scrollRegionCols_ = VT100GridRangeMake(0, size_.width);
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    VT100Grid *theCopy = [[VT100Grid alloc] initWithSize:size_
                                                delegate:delegate_];
    [theCopy->lines_ release];
    theCopy->lines_ = [[NSMutableArray alloc] init];
    for (NSObject *line in lines_) {
        [theCopy->lines_ addObject:[[line mutableCopy] autorelease]];
    }
    theCopy->lineInfos_ = [[NSMutableArray alloc] init];
    for (VT100LineInfo *line in lineInfos_) {
        [theCopy->lineInfos_ addObject:[[line copy] autorelease]];
    }
    theCopy->screenTop_ = screenTop_;
    theCopy.cursor = cursor_;
    theCopy.scrollRegionRows = scrollRegionRows_;
    theCopy.scrollRegionCols = scrollRegionCols_;
    theCopy.useScrollRegionCols = useScrollRegionCols_;
    theCopy.savedDefaultChar = savedDefaultChar_;

    return theCopy;
}

@end
