//
//  VT100Grid.m
//  iTerm
//
//  Created by George Nachman on 2/14/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "VT100Grid.h"

@implementation VT100Grid

@synthesize size = size_;
@synthesize savedCursor = savedCursor_;
@synthesize cursor = cursor_;
@synthesize lineBuffer = lineBuffer_;
@synthesize selectionStart = selectionStart_;
@synthesize selectionEnd = selectionEnd_;

- (id)initWithSize:(GridSize)size defaultChar:(screen_char_t)defaultChar {
    self = [super init];
    if (self) {
        [self setSize:size withDefaultChar:defaultChar];
        self.lineBuffer = [[LineBuffer alloc] init];
        self.selectionStart = MakeGridPoint(-1, -1);
        self.selectionEnd = MakeGridPoint(-1, -1);
    }
    return self;
}

- (void)dealloc {
    [lineBuffer_ release];
    [super dealloc];
}

- (screen_char_t *)lineAtRow:(int)row {
    return (screen_char_t *) [[lines_ objectAtIndex:row] mutableBytes];
}

- (NSMutableData *)defaultLineOfWidth:(int)width withDefaultChar:(screen_char_t)defaultChar {
    NSMutableData *data = [NSMutableData dataWithCapacity:width * sizeof(defaultChar)];
    for (int i = 0; i < width; i++) {
        [data appendBytes:&defaultChar length:sizeof(defaultChar)];
    }
    return data;
}

- (NSMutableArray *)_lineArrayOfSize:(GridSize)size
                     withDefaultChar:(screen_char_t)defaultChar {
    NSMutableArray *newLines = [NSMutableArray arrayWithCapacity:size.height];
    for (int i = 0; i < size.height; i++) {
        [newLines addObject:[self defaultLineOfWidth:size.width
                                     withDefaultChar:defaultChar]];
    }
    return newLines;
}

- (int)_appendToScrollback:(int)numLines {    
    // Set numLines to the number of lines on the screen that are in use.
    int i;
    
    // Push the current screen contents into the scrollback buffer.
    // The maximum number of lines of scrollback are temporarily ignored because this
    // loop doesn't call dropExcessLinesWithWidth.
    int next_line_length;
    if (numLines > 0) {
        next_line_length = [self usedWidthOfLine:[self lineAtRow:0]];
    }
    for (i = 0; i < numLines; ++i) {
        screen_char_t* line = [self lineAtRow:i];
        int line_length = next_line_length;
        if (i + 1 < size_.height) {
            next_line_length = [self usedWidthOfLine:[self lineAtRow:i+1]];
        } else {
            next_line_length = -1;
        }
        
        int continuation = line[size_.width].code;
        if (i == cursor_.y) {
            [lineBuffer_ setCursor:cursor_.x];
        } else if ((cursor_.x == 0) &&
                   (i == cursor_.y - 1) &&
                   (next_line_length == 0) &&
                   line[size_.width].code != EOL_HARD) {
            // This line is continued, the next line is empty, and the cursor is
            // on the first column of the next line. Pull it up.
            [lineBuffer_ setCursor:cursor_.x + 1];
        }
        
        [lineBuffer_ appendLine:line
                         length:line_length
                        partial:(continuation != EOL_HARD)
                          width:size_.width];
//        NSLog(@"Appended a line. now have %d lines for width %d\n", [linebuffer numLinesWithWidth:WIDTH], WIDTH);
    }
    
    return numLines;
}

- (BOOL)hasSelection {
    return selectionStart_.x >= 0;
}

- (void)_updateSelectionForNewSize:(GridSize)newSize {
    int newSelStartX = -1;
    int newSelStartY = -1;
    int newSelEndX = -1;
    int newSelEndY = -1;
    if ([self hasSelection]) {
        BOOL haveStart;
        int selectionStartPosition;
        haveStart = [lineBuffer_ convertCoordinatesAtX:selectionStart_.x
                                                   atY:selectionStart_.y
                                             withWidth:size_.width
                                            toPosition:&selectionStartPosition
                                                offset:0];
        
        if (haveStart) {
            [lineBuffer_ convertPosition:selectionStartPosition
                               withWidth:newSize.width
                                     toX:&newSelStartX
                                     toY:&newSelStartY];
            BOOL haveEnd;
            int selectionEndPosition;
            haveEnd = [lineBuffer_ convertCoordinatesAtX:selectionEnd_.x
                                                     atY:selectionEnd_.y
                                               withWidth:size_.width
                                              toPosition:&selectionEndPosition
                                                  offset:0];
            if (haveEnd) {
                [lineBuffer_ convertPosition:selectionEndPosition
                                   withWidth:newSize.width
                                         toX:&newSelEndX
                                         toY:&newSelEndY];
            } else {
                newSelEndX = newSize.width;
                newSelEndY = [lineBuffer_ numLinesWithWidth:newSize.width] + size_.height - 1;
            }
        }
    }
    selectionStart_ = MakeGridPoint(newSelStartX, newSelStartY);
    selectionEnd_ = MakeGridPoint(newSelEndX, newSelEndY);
}

- (void)_restoreFromScrollbackWithDefaultChar:(screen_char_t)defaultChar {
    NSMutableData *theLine = [self defaultLineOfWidth:size_.width
                                      withDefaultChar:defaultChar];
    screen_char_t* defaultLine = (screen_char_t*)[theLine mutableBytes];
    
    // Move scrollback lines into screen
    int numLinesInScrollback = [lineBuffer_ numLinesWithWidth:size_.width];
    int destY = MIN(size_.height, numLinesInScrollback) - 1;
    
    BOOL foundCursor = NO;
    BOOL prevLineStartsWithDoubleWidth = NO;
    while (destY >= 0) {
        screen_char_t* dest = [self lineAtRow:destY];
        memcpy(dest, defaultLine, sizeof(screen_char_t) * size_.width);
        if (!foundCursor) {
            int tempCursor = cursor_.x;
            foundCursor = [lineBuffer_ getCursorInLastLineWithWidth:size_.width
                                                                atX:&tempCursor];
            if (foundCursor) {
                cursor_.x = tempCursor % size_.width;
                cursor_.y = destY + tempCursor / size_.width;
            }
        }
        int cont;
        
        [lineBuffer_ popAndCopyLastLineInto:dest
                                      width:size_.width
                          includesEndOfLine:&cont];
        if (cont &&
            dest[size_.width - 1].code == 0
            && prevLineStartsWithDoubleWidth) {
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
        --destY;
    }
}

- (void)setSize:(GridSize)newSize withDefaultChar:(screen_char_t)defaultChar {
    if (newSize.width == 0 || newSize.height == 0) {
        return;
    }
    NSMutableArray *newLines = [self _lineArrayOfSize:newSize
                                      withDefaultChar:defaultChar];
    int usedHeight = [self usedHeight];
    if (size_.height - newSize.height >= usedHeight) {
        // Height is decreasing but pushing HEIGHT lines into the buffer would scroll all the used
        // lines off the top, leaving the cursor floating without any text. Keep all used lines that
        // fit onscreen.
        [self _appendToScrollback:MAX(usedHeight, newSize.height)];
    } else {
        // Keep last used line a fixed distance from the bottom of the screen
        [self _appendToScrollback:size_.height];
    }

    [self _updateSelectionForNewSize:newSize];
    size_ = newSize;
    [lines_ release];
    lines_ = [newLines retain];
    [self _restoreFromScrollbackWithDefaultChar:defaultChar];

    savedCursor_.x = MIN(savedCursor_.x, size_.width - 1);
    savedCursor_.y = MIN(savedCursor_.y, size_.height - 1);

    // If the scrollback buffer has gotten too big, drop some lines and update
    // the scroll region to account for it.
    int linesDropped = 0;
    if (!lineBuffer_.unlimited) {
        linesDropped = [lineBuffer_ dropExcessLinesWithWidth:size_.width];
    }
    int lines = [lineBuffer_ numLinesWithWidth:size_.width];
    assert(lines >= 0);
    
    if ([self hasSelection] &&
        selectionStart_.y >= linesDropped &&
        selectionEnd_.y >= linesDropped) {
        selectionStart_.y -= linesDropped;
        selectionEnd_.y -= linesDropped;
    } else {
        selectionStart_  = MakeGridPoint(-1, -1);
        selectionEnd_ = MakeGridPoint(-1, -1);
    }
}

- (int)usedWidthOfLine:(screen_char_t *)theLine {
    for (int i = size_.width - 1; i >= 0; i--) {
        if (theLine[i].code) {
            return i + 1;
        }
    }
    return 0;
}

- (int)usedHeight {
    for (int y = size_.height - 1; y >= 0; y--) {
        screen_char_t *theLine = [self lineAtRow:y];
        if ([self usedWidthOfLine:theLine]) {
            return y;
        }
    }
    return 0;
}

@end
