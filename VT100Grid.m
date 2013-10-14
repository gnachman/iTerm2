//
//  VT100Grid.m
//  iTerm
//
//  Created by George Nachman on 10/9/13.
//
//

#import "VT100Grid.h"

VT100GridRun VT100GridRunFromCoords(VT100GridCoord start,
                                    VT100GridCoord end,
                                    int width) {
    VT100GridRun run;
    run.origin = start;
    if (start.y == end.y) {
        run.length = end.x - start.x;
    } else {
        run.length = size_.width - start.x + end.x + size_.width * (end.y - start.y - 1);
    }
    return run;
}

@implementation NSValue (VT100Grid)

+ (NSValue *)valueWithGridCoord:(VT100GridCoord)coord {
    return [[[NSValue alloc] initWithBytes:&coord objCType:@encode(VT10GridCoord)] autorelease];
}

+ (NSValue *)valueWithGridSize:(VT100GridSize)size {
    return [[[NSValue alloc] initWithBytes:&size objCType:@encode(VT10GridSize)] autorelease];
}

+ (NSValue *)valueWithGridRange:(VT100GridRange)range {
    return [[[NSValue alloc] initWithBytes:&range objCType:@encode(VT10GridRange)] autorelease];
}

+ (NSValue *)valueWithGridRect:(VT100GridRect)rect {
    return [[[NSValue alloc] initWithBytes:&rect objCType:@encode(VT10GridRect)] autorelease];
}

+ (NSValue *)valueWithGridRun:(VT100GridRun)run {
    return [[[NSValue alloc] initWithBytes:&run objCType:@encode(VT10GridRun)] autorelease];
}

- (VT100GridCoord)gridCoordValue {
    VT100GridCoord coord;
    [self getValue:&coord];
    return coord;
}

- (VT100GridSize)gridSizeValue {
    VT100GridSize size;
    [self getValue:&size];
    return size;
}

- (VT100GridRange)gridRangeValue {
    VT100GridRange range;
    [self getValue:&range];
    return range;
}

- (VT100GridRect)gridRectValue {
    VT100GridRect rect;
    [self getValue:&rect];
    return rect;
}

- (VT100GridRun)gridRunValue {
    VT100GridRun run;
    [self getValue:&run];
    return run;
}

@end

@implementation VT100Grid

@synthesize size = size_;
@synthesize scrollRegionRows = scrollRegionRows_;
@synthesize scrollRegionCols = scrollRegionCols_;
@synthesize useScrollRegionCols = useScrollRegionCols_;
@synthesize savedCursor = savedCursor_;
@synthesize charset = charset_;
@synthesize savedCharset = savedCharset_;
@synthesize allDirty = allDirty_;
@synthesize lines = lines_;
@synthesize savedDefaultChar = savedDefaultChar_;

- (id)initWithSize:(VT100GridSize)size {
    self = [super init];
    if (self) {
        [self setSize:size];
        scrollRegionRows_ = VT100GridRangeMake(0, size_.height);
        scrollRegionCols_ = VT100GridRangeMake(0, size_.width);
        terminal_ = [terminal retain];
    }
    return self;
}

- (void)dealloc {
    [lines_ release];
    [dirty_ release];
    [terminal_ release];
    [cachedDefaultLine_ release];
    [super dealloc];
}

- (NSMutableData *)lineDataAtLineNumber:(int)lineNumber {
    return [lines_ objectAtIndex:(screenTop_ + lineNumber) % size_.height];
}

- (screen_char_t *)screenCharsAtLineNumber:(int)lineNumber {
    return [[lines_ objectAtIndex:(screenTop_ + lineNumber) % size_.height] mutableBytes];
}

- (char *)dirtyArrayAtLineNumber:(int)lineNumber {
    return [[dirty_ objectAtIndex:(screenTop_ + lineNumber) % size_.height] mutableBytes];
}

- (void)markCharDirty:(BOOL)dirty at:(VT100GridCoord)coord {
    if (!dirty) {
        allDirty_ = NO;
    }
    char *dirty = [self dirtyArrayAtLineNumber:coord.y];
    dirty[coord.x] = dirty ? 1 : 0;
}

- (void)markCharsDirty:(BOOL)dirty inRectFrom:(VT100GridCoord)from to:(VT100GridCoord)to {
    if (!dirty) {
        allDirty_ = NO;
    }
    char c = dirty ? 1 : 0;
    for (int y = from.y; y <= to.y; y++) {
        char *dirty = [self dirtyArrayAtLineNumber:y];
        memset(dirty + from.x, c, to.x - from.x + 1);
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
        [self markCharsDirty:dirty inRectFrom:rect.origin to:VT100GridRectGetMax(rect)];
    }
}

- (BOOL)isCharDirtyAt:(VT100GridCoord)coord {
    char *dirty = allDirty_ || [self dirtyArrayAtLineNumber:coord.y];
    return dirty[coord.x];
}

- (BOOL)isAnyCharDirty {
    if (allDirty_) {
        return YES;
    }
    for (int y = 0; y < size_.height; y++) {
        char *dirty = [self dirtyArrayAtLineNumber:y];
        for (int x = 0; x < size_.width; x++) {
            if (dirty[x]) {
                return YES;
            }
        }
    }
    return NO;
}

- (int)cursorX {
    return cursor_.x;
}

- (int)cursorY {
    return cursor_.y;
}

- (void)setCursorX:(int)cursorX {
    cursor_.x = MIN(size_.width + 1, MAX(0, cursorX));
}

- (void)setCursorY:(int)cursorY {
    cursor_.y = MIN(size_.height, MAX(0, cursorY));
}

- (int)numberOfLinesUsed {
    int numberOfLinesUsed = size_.height;

    for(; numberOfLinesUsed > cursor_.y + 1; numberOfLinesUsed--) {
        screen_char_t *line = [self screenCharsAtLineNumber:numberOfLinesUsed - 1];
        int i;
        for (i = 0; i < WIDTH; i++) {
            if (line[i].code) {
                break;
            }
        }
        if (i < WIDTH) {
            break;
        }
    }

    return numberOfLinesUsed;
}

- (int)appendLines:(int)numLines toLineBuffer:(LineBuffer *)lineBuffer {
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
            [lineBuffer setCursor:cursor_.x + 1];
        }

        [lineBuffer appendLine:line
                        length:currentLineLength
                       partial:(continuation != EOL_HARD)
                         width:size_.width];
#ifdef DEBUG_RESIZEDWIDTH
        NSLog(@"Appended a line. now have %d lines for width %d\n",
              [lineBuffer numLinesWithWidth:size_.width], size_.width);
#endif
    }

    return numLines;
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
    } else if (line[size_.width.width].code == EOL_DWC) {
        lineLength = WIDTH - 1;
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
    screen_char_t *line = [self screnCharsAtLineNumber:lineNumber];
    return line[size_.width];
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
    [self markCharDirtyAt:cursor_];

    // Add the top line to the scrollback
    int numLinesDropped = [self appendLineToLineBuffer:lineBuffer
                                   unlimitedScrollback:unlimitedScrollback];

    // Increment screenTop_, effectively scrolling the screen up by one line.
    screenTop_ = (screenTop_ + 1) % size_.height;

    // Empty contents of last line on screen.
    [self clearLineData:[self lineDataAtLineNumber:(size_.height - 1)]];

    if (lineBuffer) {
        // Mark new line at bottom of screen dirty.
        [self markCharsDirtyFrom:VT100GridCoordMake(0, size_.height - 1)
                              to:VT100GridCoordMake(size_.width - 1, size_.height - 1)];
    } else {
        // Mark everything dirty if we're not using the scrollback buffer.
        [self markCharsDirtyFrom:VT100GridCoordMake(0, 0)
                              to:VT100GridCoordMake(size_.width - 1, size_.height - 1)];
    }

    DebugLog(@"scrolled screen up by 1 line");
    return numLinesDropped;
}

- (int)scrollUpIntoLineBuffer:(LineBuffer *)lineBuffer
          unlimitedScrollback:(BOOL)unlimitedScrollback
      useScrollbackWithRegion:(BOOL)useScrollbackWithRegion {
    // TODO: caller should set useScrollbackWithRegion from [[[SESSION addressBookEntry] objectForKey:KEY_SCROLLBACK_WITH_STATUS_BAR] boolValue]
    int scrollTop = scrollRegionRows.location;
    int scrollBottom = VT100GridRangeMax(scrollRegionRows);
    int scrollLeft = useScrollRegionCols_ ? scrollRegionCols.location : 0;
    int scrollRight = useScrollRegionCols_ ? VT100GridRangeMax(scrollRegionCols) : size_.width - 1;
    BOOL haveColumnScrollRegion = (scrollLeft > 0 || scrollRight < size_.width - 1);

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
      preservingLastLine:(BOOL)preservingLastLine {
    self.scrollRegionRows = VT100GridRangeMake(0, size_.height);
    self.scrollRegionCols = VT100GridRangeMake(0, size_.width);
    int numLinesToScroll = preservingLastLine ? [self lineNumberOfLastNonEmptyLine] - 1 : size_.height;
    int numLinesDropped = 0;
    for (int i = 1; i < numLinesToScroll; i++) {
        numLinesDropped += [self scrollUpIntoLineBuffer:lineBuffer
                                    unlimitedScrollback:unlimitedScrollback
                                useScrollbackWithRegion:NO];
    }
    self.savedCursor = VT100GridCoordMake(0, 0);

    return numLinesDropped;
}

- (void)moveWrappedCursorLineToTopOfGrid {
    if (cursor_.y < 0) {
        return;  // Not sure how this would happen, but the old code in -[VT100Screen clearScreen] had this check.
    }
    int sourceLineNumber = [self cursorLineNumberIncludingPrecedingWrappedLines];
    for (int i = 0; i < sourceLineNumber) {
        [self scrollWholeScreenUpIntoLineBuffer:nil unlimitedScrollback:NO];
    }
    self.cursorY = cursor_.y - sourceLineNumber;
}

// TODO: callers need to implement logic formerly in addLineToScrollback
- (int)moveCursorDownOneLineScrollingIntoLineBuffer:(LineBuffer *)lineBuffer
                                unlimitedScrollback:(BOOL)unlimitedScrollback
                            useScrollbackWithRegion:(BOOL)useScrollbackWithRegion {
    int scrollBottom = VT100GridRangeMax(scrollRegionRows);
    int scrollTop = scrollRegionRows.location;
    int scrollLeft = scrollRegionCols.location;
    int scrollRight = VT100GridRangeMax(scrollRegionCols);

    if (cursor_.y < scrollBottom ||
        (cursor_.y < (size_.height - 1) && cursor_.y > scrollBottom)) {
        // Do not scroll the screen; just move the cursor.
        self.cursorY = cursor_.y + 1;
        DebugLog(@"moved cursor down by 1 line");
        return 0;
    } else {
        // We are scrolling within a strict subset of the screen.
        DebugLog(@"scrolled a subset or whole screen up by 1 line");
        return [self scrollUpIntoLineBuffer:lineBuffer
                        unlimitedScrollback:unlimitedScrollback
                    useScrollbackWithRegion:useScrollbackWithRegion];
    }
}

- (void)moveCursorLeft:(int)n {
    int x = cursor_.x - n;
    const int leftMargin = [self leftMargin];
    const int rightMargin = [self rightMargin];

    if (x < leftMargin) {
        x = leftMargin;
    }
    if (x >= leftMargin && x < rightMargin) {
        self.cursorX = x;
    }
}

- (void)moveCursorRight:(int)n {
    int x = cursor_.x + n;
    const int leftMargin = [self leftMargin];
    const int rightMargin = [self rightMargin];

    if (x >= rightMargin) {
        x = rightMargin - 1;
    }
    if (x >= leftMargin && x < rightMargin) {
        self.cursorX = x;
    }
}

- (void)moveCursorUp:(int)n {
    const int scrollTop = scrollRegionRows.location;
    int y = MAX(0, MIN(size_.height - 1, cursor_.y - n));
    int x = MIN(cursor_.x, size._width - 1);
    if (cursor_.y >= scrollTop) {
        [self setCursor:VT100GridMakeCoord(x,
                                           y < scrollTop ? scrollTop : y)];
    } else {
        [self setCursor:VT100GridMakeCoord(x, y)];
    }
}

- (void)moveCursorDown:(int)n {
    const int scrollBottom = VT100GridRangeMax(scrollRegionRows);
    int y = MAX(0, MIN(size_.height - 1, cursorY + n));
    int x = MIN(cursor_.x, size_.width - 1);
    if (cursorY <= scrollBottom) {
        [self setCursor:VT100GridMakeCoord(x,
                                           y > scrollBottom ? scrollBottom : y)];
    } else {
        [self setCursor:VT100GridMakeCoord(x, y)];
    }
}

- (void)setCharsFrom:(VT100GridCoord)from to:(VT100GridCoord)to toChar:(unichar)c {
    screen_char_t fg = [TERMINAL foregroundColorCodeReal];
    screen_char_t bg = [TERMINAL backgroundColorCodeReal];

    for (int y = MAX(0, from.y); y <= MIN(to.y, size_.height - 1); y++) {
        screen_char_t *line = [self screenCharsAtLineNumber:y];
        [self erasePossibleDoubleWidthCharInLineNumber:y startingAtOffset:from.x - 1];
        [self erasePossibleDoubleWidthCharInLineNumber:y startingAtOffset:to.x];
        for (int x = MAX(0, from.x); x <= MIN(to.x, size_.width - 1); x++) {
            line[x].code = c;
            line[x].complexChar = NO;
            CopyForegroundColor(&line[x], fg);
            CopyBackgroundColor(&line[x], bg);
        }
        if (to.x == size_.width - 1) {
            line[size_.width] = EOL_HARD;
        }
    }
    [self markCharsDirtyFrom:from
                          to:to];
}

- (void)setCharsInRun:(VT100GridRun)run toChar:(unichar)c {
    VT100GridCoord max = VT100GridRunMax(run, size_.width);
    int y = run.origin.y;
    int x = run.origin.x;
    if (y == max.y) {
        // Whole run is on one line.
        [self setCharsFrom:run.origin to:max toChar:c];
    } else {
        // Fill partial first line
        [self setCharsFrom:run.origin
                        to:VT100GridCoordMake(size_.width, y)
                    toChar:c];
        y++;

        if (y < max.y) {
            // Fill a bunch of full lines
            [self setCharsFrom:VT100GridCoordMake(0, y)
                            to:VT100GridCoordMake(size_.width, max.y - 1)
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
            CopyForegroundColor(&line[x], fg);
            CopyBackgroundColor(&line[x], bg);
        }
        [self markCharsDirtyFrom:VT100GridCoordMake(from.x, y)
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
    [self markAllCharsDirty];
}

- (int)appendCharsAtCursor:(screen_char_t *)buffer
                    length:(int)len
                isAllAscii:(BOOL)ascii
   scrollingIntoLineBuffer:(LineBuffer *)lineBuffer
       unlimitedScrollback:(BOOL)unlimitedScrollback
   useScrollbackWithRegion:(BOOL)useScrollbackWithRegion {
    int numDropped = 0;
    assert(string);
    int idx;  // Index into buffer
    int charsToInsert;
    int newx;
    int leftMargin, rightMargin;
    screen_char_t *buffer;
    screen_char_t *aLine;
    const int scrollBottom = VT100GridRangeMax(scrollRegionRows);
    const int scrollTop = scrollRegionRows.location;
    const int scrollLeft = scrollRegionCols.location;
    const int scrollRight = VT100GridRangeMax(scrollRegionCols);

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
            if ([terminal_ wraparoundMode]) {
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
                [self setcursor_.x:leftMargin Y:cursorY];
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
                    line[cursor_.x - 1].code = ' ';
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
        if (vsplitMode) {
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

        if ([terminal_ insertMode]) {
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
                    src[-1].code = ' ';
                    src[-1].complexChar = NO;
                    src[0].code = ' ';
                    src[0].complexChar = NO;
                }
                if (src[elements].code == DWC_RIGHT) {
                    // Moving a DWC on top of its right half. Erase the DWC.
                    src[elements - 1].code = ' ';
                    src[elements - 1].complexChar = NO;
                } else if (src[elements].code == DWC_SKIP &&
                           aLine[size_.width].code == EOL_DWC) {
                    // Stomping on a DWC_SKIP. Join the lines normally.
                    aLine[size_.width].code = EOL_SOFT;
                }
                memmove(dst, src, elements * sizeof(screen_char_t));
                [self markCharsDirtyFrom:VT100GridCoordMake(cursor_.x, lineNumber)
                                      to:VT100GridCoordMake(rightMargin, lineNumber)];
            }
        }

        // Overwriting the second-half of a double-width character so turn the
        // DWC into a space.
        if (aLine[cursor_.x].code == DWC_RIGHT) {
#ifdef VERBOSE_STRING
            NSLog(@"Wiping out the right-half DWC at the cursor before writing to screen");
#endif
            NSAssert(cursor_.x > 0, @"DWC split");  // there should never be the second half of a DWC at x=0
            aLine[cursor_.x].code = ' ';
            aLine[cursor_.x].complexChar = NO;
            aLine[cursor_.x-1].code = ' ';
            aLine[cursor_.x-1].complexChar = NO;
            [self markCharDirtyAt:VT100GridCoordMake(cursor_.x, lineNumber)];
            [self markCharDirtyAt:VT100GridCoordMake(cursor_.x - 1, lineNumber)];
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
            [self markCharsDirtyFrom:VT100GridCoordMake(cursor_.x, lineNumber)
                                  to:VT100GridCoordMake(cursor_.x + charsToInsert - 1, lineNumber)];
        }
        if (wrapDwc) {
            aLine[cursor_.x + charsToInsert].code = DWC_SKIP;
        }
        self.cursorX = newx;
        idx += charsToInsert;

        // Overwrote some stuff that was already on the screen leaving behind the
        // second half of a DWC
        if (cursor_.x < size_.width - 1 && aLine[cursor_.x].code == DWC_RIGHT) {
            aLine[cursor_.x].code = ' ';
            aLine[cursor_.x].complexChar = NO;
        }

        // The next char in the buffer shouldn't be DWC_RIGHT because we
        // wouldn't have inserted its first half due to a check at the top.
        assert(!(idx < len && buffer[idx].code == DWC_RIGHT));

        // ANSI terminals will go to a new line after displaying a character at
        // the rightmost column.
        if (cursor_.x >= effective_width && [terminal_ isAnsi]) {
            if ([terminal_ wraparoundMode]) {
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
    int i;
    int leftMargin, rightMargin;
    const int leftMargin = [self leftMargin];
    const int rightMargin = [self rightMargin];

    if (startCoord.x >= leftMargin &&
        startCoord.x < rightMargin &&
        startCoord.y >= 0 &&
        startCoord.y < size_.height) {
        int lineNumber = startCoord.y;
        if (n + startCoord.x > rightMargin) {
            n = rightMargin - startCoord.x;
        }

        // get the appropriate screen line
        aLine = [self screenCharsAtLineNumber:startCoord.y];

        if (n > 0 && startCoord.x + n < rightMargin) {
            // Erase a section in the middle of a line. Shift the stuff to the right of the
            // deletion region left to the startCoord.

            if (startCoord.x > 0 && aLine[startCoord.x].code == DWC_RIGHT) {
                // Erase orphan dwc just before startCoord
                [self setCharsFrom:VT100GridCoordMake(startCoord.x - 1, lineNumber)
                                to:VT100GridCoordMake(startCoord.x - 1, lineNumber)
                            toChar:0];
                startCoord.x++;
                num--;
            }
            if (startCoord.x + n < size_.width && aLine[startCoord.x + n].code == DWC_RIGHT) {
                // Erase orphan dwc just after range to be deleted.
                [self setCharsFrom:VT100GridCoordMake(startCoord.x + n, lineNumber)
                                to:VT100GridCoordMake(startCoord.x + n, lineNumber)
                            toChar:0];
            }
            const int numCharsToMove = (rightMargin - startCoord.x - n);
            memmove(aLine + startCoord.x,
                    aLine + startCoord.x + n,
                    numCharsToMove * sizeof(screen_char_t));
            [self markCharsDirtyFrom:VT100GridCoordMake(startCoord.x, lineNumber)
                                  to:VT100GridCoordMake(statCoord.x + numCharsToMove - 1, lineNumber)];
        }
        // Erase chars on right side of line.
        [self setCharsFrom:VT100GridCoordMake(rightMargin - n, lineNumber)
                        to:VT100GridCoordMake(rightMargin - 1, lineNumber)
                    toChar:0];
    }
}

- (void)scrollDown {
    const int scrollBottom = VT100GridRangeMax(scrollRegionRows);
    const int scrollTop = scrollRegionRows.location;
    const int scrollLeft = useScrollRegionCols_ ? scrollRegionCols.location : 0;
    const int scrollRight = useScrollRegionCols_ ? VT100GridRangeMax(scrollRegionCols) : size_.width;
    [self scrollRect:VT100GridRectMake(scrollLeft,
                                       scrollTop,
                                       scrollRight - scrollLeft + 1,
                                       scrollBottom - scrollTop + 1)
                downBy:1];
}

- (void)scrollRect:(VT100GridRect)rect downBy:(int)direction {
    DebugLog(@"scrollRect:%d,%d %dx%d downBy:%d",
             rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, direction);
    if (direction == 0) {
        return;
    }
    const int scrollTop = rect.origin.y;
    const int scrollBottom = rect.origin.y + rect.size.height - 1;
    const int scrollLeft = rect.origin.x;
    const int scrollRight = rect.origin.x + rect.size.width - 1;
    assert(scrollTop >= 0 && scrollTop < size_.height);
    assert(scrollBottom >= 0 && scrollBottom < size_.height);
    assert(scrollTop <= scrollBottom);

    if (scrollTop < scrollBottom) {
        int sourceHeight = scrollBottom - scrollTop - abs(direction);
        int sourceIndex = direction > 0 ? scrollBottom - direction : scrollTop - direction;
        int destIndex = direction > 0 ? scrollBottom : scrollTop;
        for (int iteration = 0; iteration < sourceHeight; iteration++) {
            screen_char_t *sourceLine = [self screenCharsAtLineNumber:sourceIndex];
            screen_char_t *targetLine = [self screenCharsAtLineNumber:destIndex];

            // clear DWC's that are about to get orphaned
            [self erasePossibleDoubleWidthCharInLineNumber:destIndex startingAtOffset:scrollLeft - 1];
            [self erasePossibleDoubleWidthCharInLineNumber:destIndex startingAtOffset:scrollRight];

            memmove(targetLine + scrollLeft,
                    sourceLine + scrollLeft,
                    (scrollRight - scrollLeft + 1) * sizeof(screen_char_t));

            if (targetLine[scrollLeft].code == DWC_RIGHT) {
                // Moved a DWC_RIGHT without its counterpart into target
                targetLine[scrollLeft].code = 0;
                targetLine[scrollLeft].complexChar = NO;
            }
            if (scrollRight + 1 < size_.width && sourceLine[scrollRight + 1].code == DWC_RIGHT) {
                // Moved a dwc without the corresponding DWC_RIGHT into target
                targetLine[scrollRight].code = 0;
                targetLine[scrollRight].complexChar = NO;
            }

            sourceIndex += step;
            destIndex += step;
        }
        [self markCharsDirtyFrom:VT100GridCoordMake(scrollLeft, scrollTop)
                              to:VT100GridCoordMake(scrollRight, scrollBottom)];

        // Clear region left over.
        if (direction > 0) {
            [self setCharsFrom:VT100GridCoordMake(scrollLeft, scrollTop)
                            to:VT100GridCoordMake(scrollRight, scrollTop + direction - 1)
                        toChar:0];
        } else {
            [self setCharsFrom:VT100GridCoordMake(scrollLeft, scrollBottom + direction + 1)
                            to:VT100GridCoordMake(scrollRight, scrollBottom)
                        toChar:0];
        }
    }
}

// TODO callers must call -VT100Screen setDirty to erase history, etc.
- (void)setContentsFromDVRFrame:(screen_char_t*)s len:(int)len info:(DVRFrameInfo)info
{
    [self setCharsFrom:VT100GridCoordMake(0, 0)
                    to:VT100GridCoordMake(size_.width - 1, size_.height - 1)
                toChar:0];
    int charsToCopyPerLine = MIN(size_.width, info.width);
    for (int y = 0; y < size_.height; y++) {
        screen_char_t *dest = [self screenCharsAtLineNumber:y];
        screen_char_t *src = s + (y * (info.width + 1));
        memmove(dest, src, sizeof(screen_char_t) * charsToCopyPerLine);
        if (size_.width != info.width) {
            dest[size_.width].code = EOL_HARD;
        }
        if (charsToCopyPerLine < info.width && src[charsToCopyPerLine].code == DWC_RIGHT) {
            dest[charsToCopyPerLine - 1].code = 0;
            dest[charsToCopyPerLine - 1].complexChar = NO;
        }
        if (casrToCopyPerLine - 1 < info.width && src[charsToCopyPerLine - 1].code == TAB_FILLER) {
            dest[charsToCopyPerLine - 1].code = '\t';
            dest[charsToCopyPerLine - 1].complexChar = NO;
        }
    }
    [self markAllCharsDirty];

    const int yOffset = info.height - size_.height;
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
            if (dirty[y * size_.width + x]) {
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
        [result appendFormat:@"%04d: %s %s\n", y, line, [self stringForContinuationMark:p[WIDTH].code]];
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
            int start = range.location;
            int end = range.location + range.length;
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
                                                                            length + 1)];
                [runs appendObject:value];
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

    char defaultLine[size_.width];
    for (int i = 0; i < size_.width; i++) {
        defaultLine[i] = defaultChar;
    }

    BOOL foundCursor = NO;
    BOOL prevLineStartsWithDoubleWidth = NO;
    while (destLineNumber >= 0) {
        screen_char_t *dest = [self screenCharsAtLineNumber:destLineNumber];
        memcpy(dest, defaultLine, sizeof(screen_char_t) * size_.width);
        if (!foundCursor) {
            int tempCursor = cursorX;
            foundCursor = [lineBuffer getCursorInLastLineWithWidth:size_.width atX:&tempCursor];
            if (foundCursor) {
                [self setCursor:VT100GridCoordMake(tempCursor % size_.width,
                                                   destLineNumber + tempCursor / size_.width)];
            }
        }
        int cont;
        [lineBuffer popAndCopyLastLineInto:dest width:size_.width includesEndOfLine:&cont];
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


- (VT100GridRun)runByTrimmingNullsFromRun:(VT100GridRun)run {
    VT100GridRun result = run;
    int x = result.origin.x;
    int y = result.origin.y;
    screen_char_t *line = [self screenCharsAtLineNumber:y];
    while (result.length > 0 && line[x].code == 0 && y < size_.height) {
        x++;
        result.length--;
        if (x == size_.width) {
            x = 0;
            y++;
            assert(y < size_.height);
            line = [self screenCharsAtLineNumber:y];
        }
    }
    result.origin = VT100GridCoordMake(x, y);

    VT100GridCoord end = VT100GridRunMax(run, size_.width);
    x = end.x;
    y = end.y;
    while (result.length > 0 && line[x].code == 0 && y < size_.height) {
        x--;
        result.length--;
        if (x == -1) {
            x = size_.width - 1;
            y--;
            assert(y >= 0);
            line = [self screenCharsAtLineNumber:y];
        }
    }

    return result;
}

- (void)clampCursorPositionToValid
{
    if (cursor_.x >= size_.width) {
        self.cursorX = size_.width - 1;
    }
    if (cursorY >= size_.height) {
        self.cursorY = size_.height - 1;
    }
    if (savedCursor_.x >= size_.width) {
        savedCursor_.x = size_.width - 1;
    }
    if (savedCursor_.y >= size_.height) {
        savedCursor_.y = size_.height - 1;
    }
}

- (screen_char_t *)resultLine {
    length = sizeof(screen_char_t) * (size_.width + 1);
    if (resultLine_.length != length) {
        [resultLine_ release];
        resultLine_ = [[NSMutableData alloc] initWithLength:length];
    }
    return [resultLine_ mutableData];
}

- (void)moveCursorToLeftMargin {
    const int leftMargin = [self leftMargin];
    self.cursorX = leftMargin;
}

- (NSArray *)rectsForRun:(VT100GridRun)run {
    NSMutableArray *rects = [NSMutableArray array];
    int length = run.length;
    int x = run.origin.x;
    for (int y = run.origin.y; length > 0; y++, length -= size_.width) {
        int endX = MIN(size_.width - 1, x + length - 1);
        [rects addObject:[NSValue valueWithGridRect:VT100GridRectMake(x, y, endX - x + 1, 1)]];
        length -= (endX - x + 1);
        x = 0;
    }
    return rects;
}

- (int)leftMargin {
    return useScrollRegionCols_ ? scrollRegionCols.location : 0;
}

- (int)rightMargin {
    return useScrollRegionCols_ ? VT100GridRangeMax(scrollRegionCols) : size_.width;
}

- (int)topMargin {
    return scrollRegionRows.location;
}

- (int)bottomMargin {
    return VT100GridRangeMax(scrollRegionRows);
}

- (VT100GridRect)scrollRegionRect {
    return VT100GridRectMake(self.leftMargin,
                             self.topMargin,
                             self.rightMargin - self.leftMargin + 1,
                             self.bottomMargin - self.topMargin + 1);
}

#pragma mark - Private

- (NSMutableArray *)linesWithSize:(VT100GridSize)size {
    NSMutableArray *lines = [[[NSMutableArray alloc] init] autorelease];
    for (int i = 0; i < size.height; i++) {
        [lines appendObject:[[[self defaultLineOfWidth:size.width] copy] autorelease]];
    }
    return lines;
}

- (NSMutableData *)emptyDirtyLine {
}

- (NSMutableArray *)dirtyBufferWithSize:(VT100GridSize)size {
    NSMutableArray *dirty =  = [[[NSMutableArray alloc] init] autorelease];
    for (int i = 0; i < size.height; i++) {
        [dirty appendObject:[self emptyDirtyLine]];
    }
    return dirty;
}

- (screen_char_t)defaultChar {
    screen_char_t c = { 0 };
    screen_char_t fg = [TERMINAL foregroundColorCodeReal];
    screen_char_t bg = [TERMINAL backgroundColorCodeReal];

    c.code = 0;
    c.complexChar = NO;
    CopyForegroundColor(&c, fg);
    CopyBackgroundColor(&c, bg);

    return c;
}

- (NSMutableData *)defaultLineOfWidth:(int)width {
    size_t length = (width + 1) * sizeof(screen_char_t);

    if (cachedDefaultLine_ &&
        [cachedDefaultLine_ length] == length &&
        length > 0 &&
        ((screen_char_t *)[cachedDefaultLine_ mutableBytes])[0] == [self defaultChar]) {
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
    int length = [line length] / sizeof(screen_char_t);
    [self clearScreenChars:[line mutableBytes] inRange:VT100GridRangeMake(0, length)];
    chars[width].code = EOL_HARD;
}

// Returns number of lines dropped from line buffer because it exceeded its size (always 0 or 1).
- (int)appendLineToLineBuffer:(LineBuffer *)lineBuffer
          unlimitedScrollback:(BOOL)unlimitedScrollback {
    // TODO: Caller should set linebuffer to nil if showingAltScreen && !saveToScrollbackInAlternateScreen_
    if (!lineBuffer) {
        return 0;
    }
    screen_char_t *line = [self screenCharsAtLineNumber:0];
    int len = [self lengthOfLine:line];
    int continuationMark = line[size_.width];
    if (continuationMark == EOL_DWC && len == size_.width) {
        --len;
    }
    [lineBuffer appendLine:line
                    length:len
                   partial:(continuationMark != EOL_HARD)
                     width:size_.width];
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
            (scrollLeft != 0 || scrollRight != size_.width - 1));
}

- (BOOL)haveScrollRegion {
    const int scrollBottom = VT100GridRangeMax(scrollRegionRows);
    const int scrollTop = scrollRegionRows.location;
    const int scrollLeft = scrollRegionCols.location;
    const int scrollRight = VT100GridRangeMax(scrollRegionCols);
    const BOOL haveScrollRows = !(scrollTop == 0 && scrollBottom == size_.height - 1);
    return haveScrollRows || [self haveColumnScrollRegion];
}

- (int)cursorLineNumberIncludingPrecedingWrappedLines {
    for (i = cursor_.y - 1; i >= 0; i--) {
        int mark = [self continuationMarkForLineNumberi];
        if (mark == EOL_HARD) {
            return i + 1;
        }
    }
    return 0;
}

- (int)lineNumberOfLastNonEmptyLine {
    int y;
    int x;
    for (y = size_.height - 1; y >= 0; --y) {
        if ([self lengthOfLineNumber:y] > 0) {
            return y;
        }
    }
    return 0;
}

// Warning: does not set dirty.
- (void)setSize:(VT100GridSize)newSize {
    if (newSize.width != size_.width || newSize.height != size_.height) {
        size_ = size;
        [lines_ release];
        [dirty_ release];
        lines_ = [[self linesWithSize:size] retain];
        dirty_ = [[self dirtyBufferWithSize:size] retain];
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

// Add a combining char to the cell at the cursor position if possible. Returns
// YES if it is able to and NO if there is no base character to combine with.
- (BOOL)addCombiningCharAtCursor:(unichar)combiningChar
{
    // set cx, cy to the char before the cursor.
    int cx = cursor_.x;
    int cy = cursor_.y;
    if (cx == 0) {
        cx = size_.width;
        --cy;
    }
    --cx;
    if (cy < 0) {
        // can't affect characters above screen so have it stand alone.
        return NO;
    }
    screen_char_t* theLine = [self screenCharsAtLineNumber:cy];
    if (theLine[cx].code == 0) {
        // Mark is preceeded by an unset char, so make it stand alone.
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

- (BOOL)erasePossibleDoubleWidthCharInLineNumber:(int)lineNumber startingAtOffset:(int)offset
{
    screen_char_t *aLine = [self screenCharsAtLineNumber:lineNumber];
    if (offset >= 0 && offset < size_.width - 1 && aLine[offset + 1].code == DWC_RIGHT) {
        aLine[offset].code = 0;
        aLine[offset].complexChar = NO;
        aLine[offset + 1].code = 0;
        aLine[offset + 1].complexChar = NO;
        [self markCharDirtyAt:VT100GridCoordMake(offset, lineNumber)];
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
    int fromPos = from.x + from.y * size_.width;
    int toPos = to.x + to.y * size_.width;
    return toPos - fromPos + 1;
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

- (screen_char_t *)dvrFormattedFrame {
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    VT100Grid *theCopy = [[VT100Grid alloc] initWithSize:size_ terminal:terminal_];
    [theCopy->lines_ release];
    theCopy->lines_ = [[NSMutableArray alloc] init];
    for (NSObject *line in lines_) {
        [theCopy->lines_ addObject:line];
    }
    theCopy->dirty_ = [[NSMutableArray alloc] init];
    for (NSObject *line in dirty_) {
        [theCopy->dirty_ addObject:line];
    }
    theCopy->screenTop_ = screenTop_;
    theCopy.cursor = cursor_;
    theCopy.savedCursor = savedCursor_;
    theCopy.scrollRegionRows = scrollRegionRows_;
    theCopy.scrollRegionCols = scrollRegionCols_;
    theCopy.useScrollRegionCols = useScrollRegionCols_;
    theCopy.savedDefaultChar = savedDefaultChar_;

    return theCopy;
}

@end
