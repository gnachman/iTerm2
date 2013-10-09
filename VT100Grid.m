//
//  VT100Grid.m
//  iTerm
//
//  Created by George Nachman on 10/9/13.
//
//

#import "VT100Grid.h"

@implementation VT100Grid

@synthesize size = size_;
@synthesize scrollRegionRows = scrollRegionRows_;
@synthesize scrollRegionCols = scrollRegionCols_;
@synthesize useScrollRegionCols = useScrollRegionCols_;

- (id)initWithSize:(VT100GridSize)size terminal:(VT100Terminal *)terminal {
    self = [super init];
    if (self) {
        size_ = size;
        lines_ = [[self linesWithSize:size] retain];
        dirty_ = [[self dirtyBufferWithSize:size] retain];
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

- (screen_char_t *)screenCharsAtLineNumber:(int)lineNumber {
}

- (void)markCharDirtyAt:(VT100GridCoord)coord {
}

- (void)markCharsDirtyFrom:(VT100GridCoord)from to:(VT100GridCoord)to; {
}

- (int)cursorX {
}

- (int)cursorY {
}

- (void)setCursorX:(int)cursorX {
}

- (void)setCursorY:(int)cursorY {
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
            lengthOfNextLine = [self _getLineLength:[self screenCharsAtLineNumber:i+1]];
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

- (void)restoreUpTo:(int)maxLines linesFromLineBuffer:(LineBuffer *)lineBuffer
{
    int numLinesInLineBuffer = [linebuffer numLinesWithWidth:size_.width];
    int destY;
    if (numLinesInLineBuffer >= size_.height) {
        destY = size_.height - 1;
    } else {
        destY = numLinesInLineBuffer - 1;
    }
    destY = MIN(destY, maxLines - 1);

    BOOL foundCursor = NO;
    BOOL prevLineStartsWithDoubleWidth = NO;
    NSMutableData *defaultLineData = [self defaultLineOfWidth:size_.width];
    screen_char_t *defaultLine = [defaultLineData mutableBytes];
    while (destY >= 0) {
        screen_char_t* dest = [self screenCharsAtLineNumber:destY];
        memcpy(dest, defaultLine, sizeof(screen_char_t) * size_.width);
        if (!foundCursor) {
            int tempCursor = cursor_.x;
            foundCursor = [linebuffer getCursorInLastLineWithWidth:size_.width atX:&tempCursor];
            if (foundCursor) {
                cursor_ = VT100GridCoordMake(tempCursor % size_.width,
                                             destY + tempCursor / size_.width);
            }
        }
        int continuationCode;
        [linebuffer popAndCopyLastLineInto:dest
                                     width:size_.width
                         includesEndOfLine:&continuationCode];
        if (continuationCode && dest[size_.width - 1].code == 0 && prevLineStartsWithDoubleWidth) {
            // If you pop a soft-wrapped line that's a character short and the
            // line below it starts with a DWC, it's safe to conclude that a DWC
            // was wrapped.
            dest[size_.width - 1].code = DWC_SKIP;
            continuationCode = EOL_DWC;
        }
        if (dest[1].code == DWC_RIGHT) {
            prevLineStartsWithDoubleWidth = YES;
        } else {
            prevLineStartsWithDoubleWidth = NO;
        }
        dest[size_.width].code = continuationCode;
        if (continuationCode == EOL_DWC) {
            dest[size_.width - 1].code = DWC_SKIP;
        }
        --destY;
    }
}

- (int)lengthOfLineNumber:(int)lineNumber {
    screen_char_t *line = [self screenCharsAtLineNumber:lineNumber];
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

- (void)moveCursorDownOneLineScrollingIntoLineBuffer:(LineBuffer *)lineBuffer {
    screen_char_t *aLine;
    BOOL wrap = NO;
    int scrollBottom = VT100GridRangeMax(scrollRegionRows);
    int scrollTop = scrollRegionRows.location;
    int scrollLeft = scrollRegionCols.location;
    int scrollRight = VT100GridRangeMax(scrollRegionCols);

    if (cursor_.y < scrollBottom ||
        (cursor_.y < (size_.height - 1) &&
         cursor_.y > scrollBottom)) {
            // Do not scroll the screen; just move the cursor.
            self.cursorY = cursor_.y + 1;
            DebugLog(@"advance cursor");
        } else if ((scrollTop == 0 && scrollBottom == size_.height - 1) &&
                   (!useScrollRegionCols_ || (scrollLeft == 0 && scrollRight == size_.width - 1))) {
            // Scroll the whole screen.

            // Mark the cursor's previous location dirty. This fixes a rare race condition where
            // the cursor is not erased.
            [self markCharDirtyAt:cursor_];

            // Top line can move into scroll area; we need to draw only bottom line.
            NSMutableData *firstDirtyLine = [[[dirty_ objectAtIndex:screenTop_] retain] autorelease];
            // CONTINUE WORKING HERE
            [self moveDirtyRangeFromX:0 Y:1 toX:0 Y:0 size:size_.width*(size_.height - 1)];
            [self setRangeDirty:NSMakeRange(size_.width * (size_.height - 1), size_.width)];

            // Add the top line to the scrollback
            [self addLineToScrollback];

            // Increment screen_top pointer
            screen_top = incrementLinePointer(buffer_lines, screen_top, size_.height, size_.width, &wrap);

            // set last screen line default
            aLine = [self getLineAtScreenIndex: (size_.height - 1)];

            memcpy(aLine,
                   [self _getDefaultLineWithWidth:size_.width],
                   (size_.width + 1) * sizeof(screen_char_t));

            // Mark everything dirty if we're not using the scrollback buffer
            if (showingAltScreen) {
                [self setDirty];
            }
            
            DebugLog(@"setNewline scroll screen");
        } else {
            // We are scrolling within a strict subset of the screen.
            [self scrollUp];
            DebugLog(@"setNewline weird case");
        }
}

@pragma mark - Private

- (NSMutableArray *)linesWithSize:(VT100GridSize)size {
    NSMutableArray *lines = [[[NSMutableArray alloc] init] autorelease];
    for (int i = 0; i < size.height; i++) {
        [lines appendObject:[[[self defaultLineOfWidth:size.width] copy] autorelease]];
    }
    return lines;
}

- (NSMutableArray *)dirtyBufferWithSize:(VT100GridSize)size {
    NSMutableArray *dirty =  = [[[NSMutableArray alloc] init] autorelease];
    for (int i = 0; i < size.height; i++) {
        [dirty appendObject:[[NSMutableData alloc] initWithLength:size.width]];
    }
    return dirty;
}

- (NSMutableData *)defaultLineOfWidth:(int)width {
  size_t length = (width + 1) * sizeof(screen_char_t);
  screen_char_t fg = [TERMINAL foregroundColorCodeReal];
  screen_char_t bg = [TERMINAL backgroundColorCodeReal];

  if (cachedDefaultLine_ &&
      [cachedDefaultLine_ length] == length &&
      ForegroundAttributesEqual(cachedDefaultLineForeground_, [terminal_ foregroundColorCodeReal]) &&
      BackgroundColorsEqual(cachedDefaultLineBackground_, [terminal_ backgroundColorCodeReal])) {
      return cachedDefaultLine_;
  }

  NSMutableData *line = [NSMutableData dataWithLength:length];
  screen_char_t *chars = [line mutableBytes];

  for (int i = 0; i < width; i++) {
    chars[i].code = 0;
    chars[i].complexChar = NO;
    CopyForegroundColor(&chars[i], default_fg_code);
    CopyBackgroundColor(&chars[i], default_bg_code);
  }

  chars[width].code = EOL_HARD;

  [cachedDefaultLine_ release];
  cachedDefaultLine_ = [line retain];
  cachedDefaultLineForeground_ = fg;
  cachedDefaultLineBackground_ = bg;

  return line;
}

@end
