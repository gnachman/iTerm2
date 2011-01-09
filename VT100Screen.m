// -*- mode:objc -*-
// $Id: VT100Screen.m,v 1.289 2008-10-22 00:43:30 yfabian Exp $
//
/*
 **  VT100Screen.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **         Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: Implements the VT100 screen.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

// Debug option
#define DEBUG_ALLOC           0
#define DEBUG_METHOD_TRACE    0
//#define DEBUG_CORRUPTION

#import <iTerm/iTerm.h>
#import <iTerm/VT100Screen.h>
#import <iTerm/NSStringITerm.h>
#import "WindowControllerInterface.h"
#import <iTerm/PTYTextView.h>
#import <iTerm/PTYScrollView.h>
#import <iTerm/charmaps.h>
#import <iTerm/PTYSession.h>
#import <iTerm/PTYTask.h>
#import <iTerm/PreferencePanel.h>
#import "iTermApplicationDelegate.h"
#import <iTerm/iTermGrowlDelegate.h>
#import <iTerm/ITAddressBookMgr.h>
#include <string.h>
#include <unistd.h>
#include <LineBuffer.h>
#import "DVRBuffer.h"
#import "PTYTab.h"

#define MAX_SCROLLBACK_LINES 1000000

// we add a character at the end of line to indicate wrapping
#define REAL_WIDTH (WIDTH+1)

/* translates normal char into graphics char */
static void translate(screen_char_t *s, int len)
{
    int i;

    for (i = 0; i < len; i++) {
        assert(!s[i].complexChar);
        s[i].code = charmap[(int)(s[i].code)];
    }
}

// Convert a string into an array of screen characters, dealing with surrogate
// pairs, combining marks, nonspacing marks, and double-width characters.
void StringToScreenChars(NSString *s,
                         screen_char_t *buf,
                         screen_char_t fg,
                         screen_char_t bg,
                         int *len,
                         NSStringEncoding encoding,
                         BOOL ambiguousIsDoubleWidth,
                         int* cursorIndex) {
    unichar *sc;
    int l = [s length];
    int i;
    int j;

    const int kBufferElements = 1024;
    unichar staticBuffer[kBufferElements];
    unichar* dynamicBuffer = 0;
    if ([s length] > kBufferElements) {
        sc = dynamicBuffer = (unichar *) malloc(l * sizeof(unichar));
    } else {
        sc = staticBuffer;
    }

    [s getCharacters:sc];
    int lastInitializedChar = -1;
    BOOL foundCursor = NO;
    for (i = j = 0; i < l; i++, j++) {
        // j may repeat in consecutive iterations of the loop but i increases
        // monotonically, so initialize complexChar with i instead of j.
        buf[i].complexChar = NO;

        if (cursorIndex && !foundCursor && *cursorIndex == i) {
            foundCursor = YES;
            *cursorIndex = j;
        }
        if (j > lastInitializedChar) {
            buf[j].code = sc[i];
            buf[j].complexChar = NO;

            buf[j].foregroundColor = fg.foregroundColor;
            buf[j].alternateForegroundSemantics = fg.alternateForegroundSemantics;
            buf[j].bold = fg.bold;
            buf[j].blink = fg.blink;
            buf[j].underline = fg.underline;

            buf[j].backgroundColor = bg.backgroundColor;
            buf[j].alternateBackgroundSemantics = bg.alternateBackgroundSemantics;

            lastInitializedChar = j;
        }

        if ((sc[i] >= 0xe000 && sc[i] <= 0xf8ff) ||
            sc[i] >= 0xfffd) {
            // Translate private-use characters into a replacement char.
            // Unfortunately, the proper replacement char U+fffd is double-width
            // (at least for some fonts) which screws up formatting.
            buf[j].code = '?';
        } else if (sc[i] > 0xa0 && [NSString isDoubleWidthCharacter:sc[i]
                                                           encoding:encoding
                                             ambiguousIsDoubleWidth:ambiguousIsDoubleWidth]) {
            // This code path is for double-width characters in BMP only.
            j++;
            buf[j].code = DWC_RIGHT;
            buf[j].complexChar = NO;

            buf[j].foregroundColor = fg.foregroundColor;
            buf[j].alternateForegroundSemantics = fg.alternateForegroundSemantics;
            buf[j].bold = fg.bold;
            buf[j].blink = fg.blink;
            buf[j].underline = fg.underline;

            buf[j].backgroundColor = bg.backgroundColor;
            buf[j].alternateBackgroundSemantics = bg.alternateBackgroundSemantics;
        } else if (sc[i] == 0xfeff ||
                   sc[i] == 0x200b ||
                   sc[i] == 0x200c ||
                   sc[i] == 0x200d) {
            j--;
            lastInitializedChar--;
        } else if (IsCombiningMark(sc[i]) || IsLowSurrogate(sc[i])) {
            if (j > 0) {
                j--;
                lastInitializedChar--;
                if (buf[j].complexChar) {
                    // Adding a combining mark to a char that already has one or was
                    // built by surrogates.
                    buf[j].code = AppendToComplexChar(buf[j].code, sc[i]);
                } else {
                    buf[j].code = BeginComplexChar(buf[j].code, sc[i]);
                    buf[j].complexChar = YES;
                }
                if (IsLowSurrogate(sc[i])) {
                    NSString* str = ComplexCharToStr(buf[j].code);
                    if ([NSString isDoubleWidthCharacter:DecodeSurrogatePair([str characterAtIndex:0], [str characterAtIndex:1])
                                                encoding:encoding
                                  ambiguousIsDoubleWidth:ambiguousIsDoubleWidth]) {
                        j++;
                        buf[j].code = DWC_RIGHT;
                        buf[j].complexChar = NO;

                        buf[j].foregroundColor = fg.foregroundColor;
                        buf[j].alternateForegroundSemantics = fg.alternateForegroundSemantics;
                        buf[j].bold = fg.bold;
                        buf[j].blink = fg.blink;
                        buf[j].underline = fg.underline;

                        buf[j].backgroundColor = bg.backgroundColor;
                        buf[j].alternateBackgroundSemantics = bg.alternateBackgroundSemantics;
                    }
                }
            }
        }
    }
    *len = j;
    if (cursorIndex && !foundCursor && *cursorIndex >= i) {
        // We were asked for the position of the cursor to the right
        // of the last character.
        *cursorIndex = j;
    }
    if (dynamicBuffer) {
        free(dynamicBuffer);
    }
}

// increments line pointer accounting for buffer wrap-around
static __inline__ screen_char_t *incrementLinePointer(screen_char_t *buf_start, screen_char_t *current_line,
                                  int max_lines, int line_width, BOOL *wrap)
{
    screen_char_t *next_line;

    //include the wrapping indicator
    line_width++;

    next_line = current_line + line_width;
    if(next_line >= (buf_start + line_width*max_lines))
    {
        next_line = buf_start;
        if(wrap)
            *wrap = YES;
    }
    else if(wrap)
        *wrap = NO;

    return (next_line);
}


@interface VT100Screen (Private)

- (screen_char_t *)_getLineAtIndex:(int)anIndex fromLine:(screen_char_t *)aLine;
- (screen_char_t*)_getDefaultLineWithWidth:(int)width;
- (int)_addLineToScrollback;
- (void)_setInitialTabStops;

@end

@implementation VT100Screen

#define DEFAULT_WIDTH     80
#define DEFAULT_HEIGHT    25
#define DEFAULT_FONTSIZE  14
#define DEFAULT_SCROLLBACK 1000

#define MIN_WIDTH     10
#define MIN_HEIGHT    3

#define TABSIZE     8


- (id)init
{
#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif
    if ((self = [super init]) == nil)
    return nil;

    WIDTH = DEFAULT_WIDTH;
    HEIGHT = DEFAULT_HEIGHT;

    cursorX = cursorY = 0;
    SAVE_CURSOR_X = SAVE_CURSOR_Y = 0;
    ALT_SAVE_CURSOR_X = ALT_SAVE_CURSOR_Y = 0;
    SCROLL_TOP = 0;
    SCROLL_BOTTOM = HEIGHT - 1;

    TERMINAL = nil;
    SHELL = nil;

    buffer_lines = NULL;
    dirty = NULL;
    // Temporary storage for returning lines from the screen or scrollback
    // buffer to hide the details of the encoding of each.
    result_line = NULL;
    screen_top = NULL;

    temp_buffer=NULL;
    findContext.substring = nil;

    max_scrollback_lines = DEFAULT_SCROLLBACK;
    scrollback_overflow = 0;
    tabStops = [[NSMutableSet alloc] init];
    [self _setInitialTabStops];
    linebuffer = [[LineBuffer alloc] init];

    for (int i = 0; i < 4; i++) {
        saveCharset[i] = charset[i] = 0;
    }

    // Need Growl plist stuff
    gd = [iTermGrowlDelegate sharedInstance];

    dvr = [DVR alloc];
    [dvr initWithBufferCapacity:[[PreferencePanel sharedInstance] irMemory] * 1024 * 1024];
    return self;
}

- (void)dealloc
{
#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif
    // free our character buffer
    if (buffer_lines)
        free(buffer_lines);

    // free our "dirty flags" buffer
    if (dirty) {
        free(dirty);
    }
    if (result_line) {
        free(result_line);
    }

    // free our default line
    if (default_line) {
        free(default_line);
    }

    if (temp_buffer) {
        free(temp_buffer);
    }

    [tabStops release];
    [printToAnsiString release];
    [linebuffer release];
    [dvr release];

    [super dealloc];
#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x, done", __PRETTY_FUNCTION__, self);
#endif
}

- (NSString *)description
{
    NSString *basestr;
    NSString *result;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen description]", __FILE__, __LINE__);
#endif
    basestr = [NSString stringWithFormat:@"WIDTH %d, HEIGHT %d, CURSOR (%d,%d)",
           WIDTH, HEIGHT, cursorX, cursorY];
    result = [NSString stringWithFormat:@"%@\n%@", basestr, @""]; //colstr];

    return result;
}

-(screen_char_t *)initScreenWithWidth:(int)width Height:(int)height
{
    int i;
    screen_char_t *aDefaultLine;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen initScreenWithWidth:%d Height:%d]", __FILE__, __LINE__, width, height );
#endif

    NSParameterAssert(width > 0 && height > 0);

    WIDTH = width;
    HEIGHT = height;
    cursorX = cursorY = 0;
    SAVE_CURSOR_X = SAVE_CURSOR_Y = 0;
    ALT_SAVE_CURSOR_X = ALT_SAVE_CURSOR_Y = 0;
    SCROLL_TOP = 0;
    SCROLL_BOTTOM = HEIGHT - 1;
    blinkShow=YES;
    findContext.substring = nil;
    // allocate our buffer to hold both scrollback and screen contents
    buffer_lines = (screen_char_t *)malloc(HEIGHT*REAL_WIDTH*sizeof(screen_char_t));
#ifdef DEBUG_CORRUPTION
    memset(buffer_lines, -1, HEIGHT*REAL_WIDTH*sizeof(screen_char_t));
#endif
    if (!buffer_lines) return NULL;

    // set up our pointers
    screen_top = buffer_lines;

    // set all lines in buffer to default
    default_fg_code = [TERMINAL foregroundColorCodeReal];
    default_bg_code = [TERMINAL backgroundColorCodeReal];
    default_line_width = WIDTH;
    aDefaultLine = [self _getDefaultLineWithWidth:WIDTH];
    for(i = 0; i < HEIGHT; i++) {
        memcpy([self getLineAtScreenIndex: i],
               aDefaultLine,
               REAL_WIDTH*sizeof(screen_char_t));
    }

    // set current lines in scrollback
    current_scrollback_lines = 0;

    // set up our dirty flags buffer
    dirty=(char*)malloc(HEIGHT*WIDTH*sizeof(char));
    result_line = (screen_char_t*) malloc(REAL_WIDTH * sizeof(screen_char_t));

    // force a redraw
    [self setDirty];

    return buffer_lines;
}

// gets line at specified index starting from scrollback_top
- (screen_char_t *)getLineAtIndex: (int) theIndex
{
    return [self getLineAtIndex:theIndex withBuffer:result_line];
}

- (screen_char_t *)getLineAtIndex:(int)theIndex withBuffer:(screen_char_t*)buffer
{
    NSAssert([linebuffer numLinesWithWidth: WIDTH] == current_scrollback_lines, @"Scrollback mismatch");
    if (theIndex >= current_scrollback_lines) {
        // Get a line from the circular screen buffer
        return [self _getLineAtIndex:(theIndex - current_scrollback_lines)
                            fromLine:screen_top];
    } else {
        // Get a line from the scrollback buffer.
        memcpy(buffer, default_line, sizeof(screen_char_t) * WIDTH);
        int cont = [linebuffer copyLineToBuffer:buffer width:WIDTH lineNum:theIndex];
        if (cont == EOL_SOFT &&
            theIndex == current_scrollback_lines - 1 &&
            screen_top[1].code == DWC_RIGHT &&
            buffer[WIDTH - 1].code == 0) {
            // The last line in the scrollback buffer is actually a split DWC
            // if the first line in the screen is double-width.
            cont = EOL_DWC;
        }
        if (cont == EOL_DWC) {
            buffer[WIDTH - 1].code = DWC_SKIP;
            buffer[WIDTH - 1].complexChar = NO;
        }
        buffer[WIDTH].code = cont;

        return buffer;
    }
}

// gets line at specified index starting from screen_top
- (screen_char_t *)getLineAtScreenIndex: (int) theIndex
{
    return ([self _getLineAtIndex:theIndex fromLine:screen_top]);
}

// returns NSString representation of line
- (NSString *)getLineString:(screen_char_t *)theLine
{
    NSMutableString* result = [NSMutableString stringWithCapacity:REAL_WIDTH];

    for (int i = 0; i < WIDTH; i++) {
        [result appendString:ScreenCharToStr(&theLine[i])];
    }

    if (theLine[WIDTH].code) {
        [result appendString:@"\n"];
    }

    return result;
}

- (void)setCursorX:(int)x Y:(int)y
{
    if (cursorX >= 0 && cursorX < WIDTH && cursorY >= 0 && cursorY < HEIGHT) {
        dirty[cursorX + cursorY * WIDTH] = 1;
    }
    if (gDebugLogging) {
      DebugLog([NSString stringWithFormat:@"Move cursor to %d,%d", x, y]);
    }
    cursorX = x;
    cursorY = y;
    if (cursorX >= 0 && cursorX < WIDTH && cursorY >= 0 && cursorY < HEIGHT) {
        dirty[cursorX + cursorY * WIDTH] = 1;
    }
}

- (void)setWidth:(int)width height:(int)height
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen setWidth:%d height:%d]",
          __FILE__, __LINE__, width, height);
#endif

    if (width >= MIN_WIDTH && height >= MIN_HEIGHT) {
        WIDTH = width;
        HEIGHT = height;
        [self setCursorX:0 Y:0];
        SAVE_CURSOR_X = SAVE_CURSOR_Y = 0;
        ALT_SAVE_CURSOR_X = ALT_SAVE_CURSOR_Y = 0;
        SCROLL_TOP = 0;
        SCROLL_BOTTOM = HEIGHT - 1;
    }
}

static char* FormatCont(int c)
{
    switch (c) {
        case EOL_HARD:
            return "[hard]";
        case EOL_SOFT:
            return "[soft]";
        case EOL_DWC:
            return "[dwc]";
        default:
            return "[?]";
    }
}

- (NSString*)debugString
{
    NSMutableString* result = [NSMutableString stringWithString:@""];
    int x, y;
    char line[1000];
    char dirtyline[1000];
    for (y = 0; y < HEIGHT; ++y) {
        int ox = 0;
        screen_char_t* p = [self getLineAtScreenIndex: y];
        if (p == buffer_lines) {
            [result appendString:@"--- top of buffer ---\n"];
        }
        for (x = 0; x < WIDTH; ++x, ++ox) {
            if (dirty[y * WIDTH + x]) {
                dirtyline[ox] = '-';
            } else {
                dirtyline[ox] = '.';
            }
            if (y == cursorY && x == cursorX) {
                if (dirtyline[ox] == '-') {
                    dirtyline[ox] = '=';
                }
                if (dirtyline[ox] == '.') {
                    dirtyline[ox] = ':';
                }
            }
            if (p+x > buffer_lines + HEIGHT*REAL_WIDTH) {
                line[ox++] = '!';
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
        [result appendFormat:@"%04d @ buffer+%2d lines: %s %s\n", y, ((p - buffer_lines) / REAL_WIDTH), line, FormatCont(p[WIDTH].code)];
        [result appendFormat:@"%04d @ buffer+%2d dirty: %s\n", y, ((p - buffer_lines) / REAL_WIDTH), dirtyline];
    }
    return result;
}

// NSLog the screen contents for debugging.
- (void)dumpScreen
{
    NSLog(@"%@", [self debugString]);
}

- (void) dumpDebugLog
{
    int x, y;
    char line[1000];
    char dirtyline[1000];
    DebugLog([NSString stringWithFormat:@"width=%d height=%d cursor_x=%d cursor_y=%d scroll_top=%d scroll_bottom=%d max_scrollback_lines=%d current_scrollback_lines=%d scrollback_overflow=%d",
              WIDTH, HEIGHT, cursorX, cursorY, SCROLL_TOP, SCROLL_BOTTOM, max_scrollback_lines, current_scrollback_lines, scrollback_overflow]);

    for (y = 0; y < HEIGHT; ++y) {
        int ox = 0;
        screen_char_t* p = [self getLineAtScreenIndex: y];
        if (p == buffer_lines) {
            DebugLog(@"--- top of buffer ---\n");
        }
        for (x = 0; x < WIDTH; ++x, ++ox) {
            if (y == cursorY && x == cursorX) {
                line[ox++] = '<';
                line[ox++] = '*';
                line[ox++] = '>';
            }
            if (p+x > buffer_lines + HEIGHT*REAL_WIDTH) {
                line[ox++] = '!';
            }
            if (p[x].code && !p[x].complexChar) {
                line[ox] = p[x].code;
            } else {
                line[ox] = '.';
            }
            if (dirty[y*WIDTH+x]) {
                dirtyline[x] = '*';
            } else {
                dirtyline[x] = ' ';
            }
        }
        dirtyline[x] = 0;
        line[x] = 0;
        DebugLog([NSString stringWithFormat:@"%04d @ buffer+%2d lines: %s %s", y, ((p - buffer_lines) / REAL_WIDTH), line, FormatCont(p[WIDTH].code)]);
        DebugLog([NSString stringWithFormat:@"                 dirty: %s", dirtyline]);
    }
}

- (int)_getLineLength:(screen_char_t*)line
{
    int line_length = 0;
    // Figure out the line length.
    if (line[WIDTH].code == EOL_SOFT) {
        line_length = WIDTH;
    } else if (line[WIDTH].code == EOL_DWC) {
        line_length = WIDTH - 1;
    } else {
        for (line_length = WIDTH - 1; line_length >= 0; --line_length) {
            if (line[line_length].code && line[line_length].code != DWC_SKIP) {
                break;
            }
        }
        ++line_length;
    }
    return line_length;
}

// Returns the number of lines appended.
- (int)_appendScreenToScrollback
{
    // Set used_height to the number of lines on the screen that are in use.
    int i;
    int used_height = HEIGHT;

    for(; used_height > cursorY + 1; used_height--) {
        screen_char_t* aLine = [self getLineAtScreenIndex: used_height-1];
        for (i = 0; i < WIDTH; i++)
            if (aLine[i].code) {
                break;
            }
        if (i < WIDTH) {
            break;
        }
    }

    // Push the current screen contents into the scrollback buffer.
    // The maximum number of lines of scrollback are temporarily ignored because this
    // loop doesn't call dropExcessLinesWithWidth.
    int next_line_length;
    if (used_height > 0) {
        next_line_length  = [self _getLineLength:[self getLineAtScreenIndex: 0]];
    }
    for (i = 0; i < used_height; ++i) {
        screen_char_t* line = [self getLineAtScreenIndex: i];
        int line_length = next_line_length;
        if (i+1 < HEIGHT) {
            next_line_length = [self _getLineLength:[self getLineAtScreenIndex:i+1]];
        } else {
            next_line_length = -1;
        }

        int continuation = line[WIDTH].code;
        if (i == cursorY) {
            [linebuffer setCursor:cursorX];
        } else if ((cursorX == 0) &&
                   (i == cursorY - 1) &&
                   (next_line_length == 0) &&
                   line[WIDTH].code != EOL_HARD) {
            // This line is continued, the next line is empty, and the cursor is
            // on the first column of the next line. Pull it up.
            [linebuffer setCursor:cursorX + 1];
        }

        [linebuffer appendLine:line length:line_length partial:(continuation != EOL_HARD) width:WIDTH];
#ifdef DEBUG_RESIZEDWIDTH
        NSLog(@"Appended a line. now have %d lines for width %d\n", [linebuffer numLinesWithWidth:WIDTH], WIDTH);
#endif
    }

    return used_height;
}

- (void)resizeWidth:(int)new_width height:(int)new_height
{
    int i;
    screen_char_t *new_buffer_lines;

#ifdef DEBUG_RESIZEDWIDTH
    NSLog(@"Resize from %dx%d to %dx%d\n", WIDTH, HEIGHT, new_width, new_height);
    [self dumpScreen];
#endif

#if DEBUG_METHOD_TRACE
    NSLog(@"%s:%d :%d]", __PRETTY_FUNCTION__, new_width, new_height);
#endif

    if (WIDTH == 0 || HEIGHT == 0 || (new_width==WIDTH && new_height==HEIGHT)) {
        return;
    }

    // create a new buffer and fill it with the default line.
    new_buffer_lines = (screen_char_t*)malloc(new_height*(new_width+1)*sizeof(screen_char_t));
#ifdef DEBUG_CORRUPTION
    memset(new_buffer_lines, -1, new_height*(new_width+1)*sizeof(screen_char_t));
#endif
    screen_char_t* defaultLine = [self _getDefaultLineWithWidth:new_width];
    for (i = 0; i < new_height; ++i) {
        memcpy(new_buffer_lines + (new_width + 1) * i, defaultLine, sizeof(screen_char_t) * (new_width+1));
    }

    int selectionStartPosition = -1;
    int selectionEndPosition = -1;
    BOOL hasSelection = [display selectionStartX] != -1;
    [self _appendScreenToScrollback];
    if (hasSelection) {
        [linebuffer convertCoordinatesAtX:[display selectionStartX]
                                      atY:[display selectionStartY]
                                withWidth:WIDTH
                               toPosition:&selectionStartPosition
                                   offset:0];
        [linebuffer convertCoordinatesAtX:[display selectionEndX]
                                      atY:[display selectionEndY]
                                withWidth:WIDTH
                               toPosition:&selectionEndPosition
                                   offset:0];
    }

    int newSelStartX = -1, newSelStartY = -1;
    int newSelEndX = -1, newSelEndY = -1;
    if (hasSelection) {
        [linebuffer convertPosition:selectionStartPosition
                          withWidth:new_width
                                toX:&newSelStartX
                                toY:&newSelStartY];
        [linebuffer convertPosition:selectionEndPosition
                          withWidth:new_width
                                toX:&newSelEndX
                                toY:&newSelEndY];
    }

#ifdef DEBUG_RESIZEDWIDTH
    NSLog(@"After push:\n");
        [linebuffer dump];
#endif

    // reassign our pointers
    if (buffer_lines) {
        free(buffer_lines);
    }
    buffer_lines = new_buffer_lines;
    screen_top = new_buffer_lines;
    if (dirty) {
        free(dirty);
    }
    if (result_line) {
        free(result_line);
    }
    dirty = (char*)malloc(new_height*new_width*sizeof(char));
    result_line = (screen_char_t*)malloc((new_width + 1) * sizeof(screen_char_t));

    // Move scrollback lines into screen
    int num_lines_in_scrollback = [linebuffer numLinesWithWidth: new_width];
    int dest_y;
    if (num_lines_in_scrollback >= new_height) {
        dest_y = new_height - 1;
    } else {
        dest_y = num_lines_in_scrollback - 1;
    }

    // new height and width
    WIDTH = new_width;
    HEIGHT = new_height;


    int source_line_num = num_lines_in_scrollback;
    BOOL found_cursor = NO;
    BOOL prevLineStartsWithDoubleWidth = NO;
    while (dest_y >= 0) {
        screen_char_t* dest = [self getLineAtScreenIndex: dest_y];
        memcpy(dest, defaultLine, sizeof(screen_char_t) * WIDTH);
        if (!found_cursor) {
            int tempCursor = cursorX;
            found_cursor = [linebuffer getCursorInLastLineWithWidth: new_width atX:&tempCursor];
            if (found_cursor) {
                [self setCursorX:tempCursor % new_width
                               Y:dest_y + tempCursor / new_width];
            }
        }
        int cont;
        [linebuffer popAndCopyLastLineInto:dest width:WIDTH includesEndOfLine:&cont];
        if (cont && dest[WIDTH - 1].code == 0 && prevLineStartsWithDoubleWidth) {
            // If you pop a soft-wrapped line that's a character short and the
            // line below it starts with a DWC, it's safe to conclude that a DWC
            // was wrapped.
            dest[WIDTH - 1].code = DWC_SKIP;
            cont = EOL_DWC;
        }
        if (dest[1].code == DWC_RIGHT) {
            prevLineStartsWithDoubleWidth = YES;
        } else {
            prevLineStartsWithDoubleWidth = NO;
        }
        dest[WIDTH].code = cont;
        if (cont == EOL_DWC) {
            dest[WIDTH - 1].code = DWC_SKIP;
        }
        --dest_y;
        --source_line_num;
    }

#ifdef DEBUG_RESIZEDWIDTH
    NSLog(@"After pops\n");
    [linebuffer dump];
#endif

    // reset terminal scroll top and bottom
    SCROLL_TOP = 0;
    SCROLL_BOTTOM = HEIGHT - 1;

    // adjust X coordinate of cursor
    if (cursorX >= WIDTH) {
        [self setCursorX:WIDTH - 1 Y:cursorY];
    }
    if (cursorY >= new_height) {
        [self setCursorX:cursorX Y:new_height - 1];
    }
    if (SAVE_CURSOR_X >= WIDTH) {
        SAVE_CURSOR_X = WIDTH-1;
    }
    if (ALT_SAVE_CURSOR_X >= WIDTH) {
        ALT_SAVE_CURSOR_X = WIDTH-1;
    }
    if (SAVE_CURSOR_Y >= new_height) {
        SAVE_CURSOR_Y = new_height-1;
    }
    if (ALT_SAVE_CURSOR_Y >= new_height) {
        ALT_SAVE_CURSOR_Y = new_height-1;
    }

    // if we did the resize in SAVE_BUFFER mode, too bad, get rid of it
    if (temp_buffer) {
        screen_char_t* aDefaultLine = [self _getDefaultLineWithWidth:WIDTH];
        free(temp_buffer);
        temp_buffer = (screen_char_t*)malloc(REAL_WIDTH * HEIGHT * (sizeof(screen_char_t)));
        for(i = 0; i < HEIGHT; i++) {
            memcpy(temp_buffer+i*REAL_WIDTH, aDefaultLine, REAL_WIDTH*sizeof(screen_char_t));
        }
    }

    // The linebuffer may have grown. Ensure it doesn't have too many lines.
#ifdef DEBUG_RESIZEDWIDTH
    NSLog(@"Before dropExcessLines have %d\n", [linebuffer numLinesWithWidth: WIDTH]);
#endif
    int linesDropped = [linebuffer dropExcessLinesWithWidth: WIDTH];
    int lines = [linebuffer numLinesWithWidth: WIDTH];
    NSAssert(lines >= 0, @"Negative lines");
    current_scrollback_lines = lines;

    // An immediate refresh is needed so that the size of TEXTVIEW can be
    // adjusted to fit the new size
    DebugLog(@"resizeWidth setDirty");
    [display refresh];

    if (hasSelection &&
        newSelStartY >= linesDropped &&
        newSelEndY >= linesDropped) {
        [display setSelectionFromX:newSelStartX
                             fromY:newSelStartY - linesDropped
                               toX:newSelEndX
                               toY:newSelEndY - linesDropped];
    } else {
        [display deselect];
    }

    [SESSION updateScroll];
#ifdef DEBUG_RESIZEDWIDTH
    NSLog(@"After resizeWidth\n");
    [self dumpScreen];
#endif
}

- (void)reset
{
    // Save screen contents before resetting.
    [self scrollScreenIntoScrollbackBuffer:1];

    // reset terminal scroll top and bottom
    [self setCursorX:cursorX Y:SCROLL_TOP];
    SCROLL_TOP = 0;
    SCROLL_BOTTOM = HEIGHT - 1;

    [self clearScreen];
    [self _setInitialTabStops];
    SAVE_CURSOR_X = 0;
    ALT_SAVE_CURSOR_X = 0;
    [self setCursorX:cursorX Y:0];
    SAVE_CURSOR_Y = 0;
    ALT_SAVE_CURSOR_Y = 0;

    for (int i = 0; i < 4; i++) {
        saveCharset[i] = charset[i] = 0;
    }

    [self showCursor:YES];
}

- (int)width
{
    return WIDTH;
}

- (int)height
{
    return HEIGHT;
}

- (unsigned int)scrollbackLines
{
    return max_scrollback_lines;
}

// sets scrollback lines.
- (void)setScrollback:(unsigned int)lines;
{
    max_scrollback_lines = lines;
    [linebuffer setMaxLines: lines];
    [linebuffer dropExcessLinesWithWidth: WIDTH];
    current_scrollback_lines = [linebuffer numLinesWithWidth: WIDTH];
}

- (PTYSession *)session
{
    return SESSION;
}

- (void)setSession:(PTYSession *)session
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif
    SESSION=session;
}

- (void)setTerminal:(VT100Terminal *)terminal
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen setTerminal:%@]",
      __FILE__, __LINE__, terminal);
#endif
    TERMINAL = terminal;
}

- (VT100Terminal *)terminal
{
    return TERMINAL;
}

- (void)setShellTask:(PTYTask *)shell
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen setShellTask:%@]",
      __FILE__, __LINE__, shell);
#endif
    SHELL = shell;
}

- (PTYTask *)shellTask
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen shellTask]", __FILE__, __LINE__);
#endif
    return SHELL;
}

- (PTYTextView *) display
{
    return (display);
}

- (void) setDisplay: (PTYTextView *) aDisplay
{
    display = aDisplay;
}

- (BOOL) blinkingCursor
{
    return (blinkingCursor);
}

- (void) setBlinkingCursor: (BOOL) flag
{
    blinkingCursor = flag;
}

- (void)putToken:(VT100TCC)token
{
    NSString *newTitle;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen putToken:%d]",__FILE__, __LINE__, token);
#endif
    int i,j,k;
    screen_char_t *aLine;

    switch (token.type) {
    // our special code
    case VT100_STRING:
    case VT100_ASCIISTRING:
        // check if we are in print mode
        if ([self printToAnsi] == YES) {
            [self printStringToAnsi:token.u.string];
        } else {
            // else display string on screen
            [self setString:token.u.string ascii:(token.type == VT100_ASCIISTRING)];
        }
        break;

    case VT100_UNKNOWNCHAR: break;
    case VT100_NOTSUPPORT: break;

    //  VT100 CC
    case VT100CC_ENQ: break;
    case VT100CC_BEL: [self activateBell]; break;
    case VT100CC_BS:  [self backSpace]; break;
    case VT100CC_HT:  [self setTab]; break;
    case VT100CC_LF:
    case VT100CC_VT:
    case VT100CC_FF:
        if([self printToAnsi] == YES)
            [self printStringToAnsi: @"\n"];
        else
            [self setNewLine];
        break;
    case VT100CC_CR:  [self setCursorX:0 Y:cursorY]; break;
    case VT100CC_SO:  break;
    case VT100CC_SI:  break;
    case VT100CC_DC1: break;
    case VT100CC_DC3: break;
    case VT100CC_CAN:
    case VT100CC_SUB: break;
    case VT100CC_DEL: [self deleteCharacters:1];break;

    // VT100 CSI
    case VT100CSI_CPR: break;
    case VT100CSI_CUB: [self cursorLeft:token.u.csi.p[0]]; break;
    case VT100CSI_CUD: [self cursorDown:token.u.csi.p[0]]; break;
    case VT100CSI_CUF: [self cursorRight:token.u.csi.p[0]]; break;
    case VT100CSI_CUP: [self cursorToX:token.u.csi.p[1]
                                     Y:token.u.csi.p[0]];
        break;
    case VT100CSI_CUU: [self cursorUp:token.u.csi.p[0]]; break;
    case VT100CSI_DA:   [self deviceAttribute:token]; break;
    case VT100CSI_DECALN:
        for (i = 0; i < HEIGHT; i++) {
            aLine = [self getLineAtScreenIndex:i];
            for (j = 0; j < WIDTH; j++) {
                aLine[j].code ='E';
                aLine[j].complexChar = NO;
                CopyForegroundColor(&aLine[j], [TERMINAL foregroundColorCodeReal]);
                CopyBackgroundColor(&aLine[j], [TERMINAL backgroundColorCodeReal]);
            }
            aLine[WIDTH].code = EOL_HARD;
        }
        DebugLog(@"putToken DECALN");
        [self setDirty];
        break;
    case VT100CSI_DECDHL: break;
    case VT100CSI_DECDWL: break;
    case VT100CSI_DECID: break;
    case VT100CSI_DECKPAM: break;
    case VT100CSI_DECKPNM: break;
    case VT100CSI_DECLL: break;
    case VT100CSI_DECRC: [self restoreCursorPosition]; break;
    case VT100CSI_DECREPTPARM: break;
    case VT100CSI_DECREQTPARM: break;
    case VT100CSI_DECSC: [self saveCursorPosition]; break;
    case VT100CSI_DECSTBM: [self setTopBottom:token]; break;
    case VT100CSI_DECSWL: break;
    case VT100CSI_DECTST: break;
    case VT100CSI_DSR:  [self deviceReport:token]; break;
    case VT100CSI_ED:   [self eraseInDisplay:token]; break;
    case VT100CSI_EL:   [self eraseInLine:token]; break;
    case VT100CSI_HTS:
        if (cursorX < WIDTH) {
            [self setTabStopAt:cursorX];
        }
        break;
    case VT100CSI_HVP: [self cursorToX:token.u.csi.p[1]
                                     Y:token.u.csi.p[0]];
        break;
    case VT100CSI_NEL:
        [self setCursorX:0 Y:cursorY];
        // fall through
    case VT100CSI_IND:
        if (cursorY == SCROLL_BOTTOM) {
            [self scrollUp];
        } else {
            [self setCursorX:cursorX Y:cursorY + 1];
            if (cursorY >= HEIGHT) {
                [self setCursorX:cursorX Y:HEIGHT - 1];
            }
        }
        break;
    case VT100CSI_RI:
        if (cursorY == SCROLL_TOP) {
            [self scrollDown];
        } else {
            [self setCursorX:cursorX Y:cursorY - 1];
            if (cursorY < 0) {
                [self setCursorX:cursorX Y:0];
            }
        }
        break;
    case VT100CSI_RIS: break;
    case VT100CSI_RM: break;
    case VT100CSI_SCS0: charset[0]=(token.u.code=='0'); break;
    case VT100CSI_SCS1: charset[1]=(token.u.code=='0'); break;
    case VT100CSI_SCS2: charset[2]=(token.u.code=='0'); break;
    case VT100CSI_SCS3: charset[3]=(token.u.code=='0'); break;
    case VT100CSI_SGR:  [self selectGraphicRendition:token]; break;
    case VT100CSI_SM: break;
    case VT100CSI_TBC:
        switch (token.u.csi.p[0]) {
            case 3:
                [self clearTabStop];
                break;

            case 0:
                if (cursorX < WIDTH) {
                    [self removeTabStopAt:cursorX];
                }
        }
        break;

    case VT100CSI_DECSET:
    case VT100CSI_DECRST:
        if (token.u.csi.p[0] == 3 &&
            [TERMINAL allowColumnMode] == YES &&
            ![[[SESSION addressBookEntry] objectForKey:KEY_DISABLE_WINDOW_RESIZING] boolValue]) {
            // set the column
            [[SESSION tab] sessionInitiatedResize:SESSION
                                            width:([TERMINAL columnMode] ? 132 : 80)
                                           height:HEIGHT];
            token.u.csi.p[0]=2; [self eraseInDisplay:token]; //erase the screen
            token.u.csi.p[0]=token.u.csi.p[1]=0; [self setTopBottom:token]; // reset scroll;
        }

        break;

    // ANSI CSI
    case ANSICSI_CBT:
        [self backTab];
        break;
    case ANSICSI_CHA:
        [self cursorToX: token.u.csi.p[0]];
        break;
    case ANSICSI_VPA:
        [self cursorToX:cursorX + 1 Y:token.u.csi.p[0]];
        break;
    case ANSICSI_VPR:
        [self cursorToX:cursorX + 1 Y:token.u.csi.p[0] + cursorY + 1];
        break;
    case ANSICSI_ECH:
        if (cursorX < WIDTH) {
            i = WIDTH * cursorY + cursorX;
            j = token.u.csi.p[0];
            if (j + cursorX > WIDTH) {
                j = WIDTH - cursorX;
            }
            aLine = [self getLineAtScreenIndex:cursorY];
            for (k = 0; k < j; k++) {
                aLine[cursorX + k].code = 0;
                CopyForegroundColor(&aLine[cursorX + k], [TERMINAL foregroundColorCodeReal]);
                CopyBackgroundColor(&aLine[cursorX + k], [TERMINAL backgroundColorCodeReal]);
            }
            memset(dirty+i,1,j);
            DebugLog(@"putToken ECH");
        }
        break;

    case STRICT_ANSI_MODE:
        [TERMINAL setStrictAnsiMode: ![TERMINAL strictAnsiMode]];
        break;

    case ANSICSI_PRINT:
        switch (token.u.csi.p[0]) {
            case 4:
                // print our stuff!!
                [self doPrint];
                break;
            case 5:
                // allocate a string for the stuff to be printed
                if (printToAnsiString != nil)
                    [printToAnsiString release];
                printToAnsiString = [[NSMutableString alloc] init];
                [self setPrintToAnsi: YES];
                break;
            default:
                //print out the whole screen
                if (printToAnsiString != nil)
                    [printToAnsiString release];
                printToAnsiString = nil;
                [self setPrintToAnsi: NO];
                [self doPrint];
        }
        break;
    case ANSICSI_SCP:
        [self saveCursorPosition];
        break;
    case ANSICSI_RCP:
        [self restoreCursorPosition];
        break;

    // XTERM extensions
    case XTERMCC_WIN_TITLE:
        newTitle = [[token.u.string copy] autorelease];
        if ([[[SESSION addressBookEntry] objectForKey:KEY_SYNC_TITLE] boolValue]) {
            newTitle = [NSString stringWithFormat:@"%@: %@", [SESSION joblessDefaultName], newTitle];
        }
        [SESSION setWindowTitle:newTitle];
        break;
    case XTERMCC_WINICON_TITLE:
        newTitle = [[token.u.string copy] autorelease];
        if ([[[SESSION addressBookEntry] objectForKey:KEY_SYNC_TITLE] boolValue]) {
            newTitle = [NSString stringWithFormat:@"%@: %@", [SESSION joblessDefaultName], newTitle];
        }
        [SESSION setWindowTitle: newTitle];
        [SESSION setName: newTitle];
        break;
    case XTERMCC_ICON_TITLE:
        newTitle = [[token.u.string copy] autorelease];
        if ([[[SESSION addressBookEntry] objectForKey:KEY_SYNC_TITLE] boolValue]) {
            newTitle = [NSString stringWithFormat:@"%@: %@", [SESSION joblessDefaultName], newTitle];
        }
        [SESSION setName: newTitle];
        break;
    case XTERMCC_INSBLNK: [self insertBlank:token.u.csi.p[0]]; break;
    case XTERMCC_INSLN: [self insertLines:token.u.csi.p[0]]; break;
    case XTERMCC_DELCH: [self deleteCharacters:token.u.csi.p[0]]; break;
    case XTERMCC_DELLN: [self deleteLines:token.u.csi.p[0]]; break;
    case XTERMCC_WINDOWSIZE:
        //NSLog(@"setting window size from (%d, %d) to (%d, %d)", WIDTH, HEIGHT, token.u.csi.p[1], token.u.csi.p[2]);
        if (![[[SESSION addressBookEntry] objectForKey:KEY_DISABLE_WINDOW_RESIZING] boolValue] &&
            ![[[SESSION tab] parentWindow] fullScreen]) {
            // set the column
            [[SESSION tab] sessionInitiatedResize:SESSION
                                            width:token.u.csi.p[2]
                                           height:token.u.csi.p[1]];

        }
        break;
    case XTERMCC_WINDOWSIZE_PIXEL:
        if (![[[SESSION addressBookEntry] objectForKey:KEY_DISABLE_WINDOW_RESIZING] boolValue] &&
            ![[[SESSION tab] parentWindow] fullScreen]) {
            // TODO: Only allow this if there is a single session in the tab.
            [[SESSION tab] sessionInitiatedResize:SESSION
                                            width:(token.u.csi.p[2] / [display charWidth])
                                           height:(token.u.csi.p[1] / [display lineHeight])];
        }
        break;
    case XTERMCC_WINDOWPOS:
        //NSLog(@"setting window position to Y=%d, X=%d", token.u.csi.p[1], token.u.csi.p[2]);
        if (![[[SESSION addressBookEntry] objectForKey:KEY_DISABLE_WINDOW_RESIZING] boolValue] &&
            ![[[SESSION tab] parentWindow] fullScreen])
            // TODO: Only allow this if there is a single session in the tab.
            [[[SESSION tab] parentWindow] windowSetFrameTopLeftPoint:NSMakePoint(token.u.csi.p[2],
                                                                                 [[[[SESSION tab] parentWindow] windowScreen] frame].size.height - token.u.csi.p[1])];
        break;
    case XTERMCC_ICONIFY:
        // TODO: Only allow this if there is a single session in the tab.
        if (![[[SESSION tab] parentWindow] fullScreen])
            [[[SESSION tab] parentWindow] windowPerformMiniaturize:nil];
        break;
    case XTERMCC_DEICONIFY:
        // TODO: Only allow this if there is a single session in the tab.
        [[[SESSION tab] parentWindow] windowDeminiaturize:nil];
        break;
    case XTERMCC_RAISE:
        // TODO: Only allow this if there is a single session in the tab.
        [[[SESSION tab] parentWindow] windowOrderFront:nil];
        break;
    case XTERMCC_LOWER:
        // TODO: Only allow this if there is a single session in the tab.
        if (![[[SESSION tab] parentWindow] fullScreen])
            [[[SESSION tab] parentWindow] windowOrderBack: nil];
        break;
    case XTERMCC_SU:
        for (i=0; i<token.u.csi.p[0]; i++) [self scrollUp];
        break;
    case XTERMCC_SD:
        for (i=0; i<token.u.csi.p[0]; i++) [self scrollDown];
        break;
    case XTERMCC_REPORT_WIN_STATE:
        {
            char buf[64];
            snprintf(buf, sizeof(buf), "\033[%dt", [[[SESSION tab] parentWindow] windowIsMiniaturized] ? 2 : 1);
            [SHELL writeTask:[NSData dataWithBytes:buf
                                            length:strlen(buf)]];
        }
        break;
    case XTERMCC_REPORT_WIN_POS:
        {
            char buf[64];
            NSRect frame = [[[SESSION tab] parentWindow] windowFrame];
            // TODO: Figure out wtf to do if there are multiple sessions in one tab.
            snprintf(buf, sizeof(buf), "\033[3;%d;%dt", (int) frame.origin.x, (int) frame.origin.y);
            [SHELL writeTask: [NSData dataWithBytes:buf length:strlen(buf)]];
        }
        break;
    case XTERMCC_REPORT_WIN_PIX_SIZE:
        {
            char buf[64];
            NSRect frame = [[[SESSION tab] parentWindow] windowFrame];
            // TODO: Some kind of adjustment for panes?
            snprintf(buf, sizeof(buf), "\033[4;%d;%dt", (int) frame.size.height, (int) frame.size.width);
            [SHELL writeTask: [NSData dataWithBytes:buf length:strlen(buf)]];
        }
        break;
    case XTERMCC_REPORT_WIN_SIZE:
        {
            char buf[64];
            // TODO: Some kind of adjustment for panes
            snprintf(buf, sizeof(buf), "\033[8;%d;%dt", HEIGHT, WIDTH);
            [SHELL writeTask: [NSData dataWithBytes:buf length:strlen(buf)]];
        }
        break;
    case XTERMCC_REPORT_SCREEN_SIZE:
        {
            char buf[64];
            // TODO: This isn't really right since a window couldn't be made this large given the
            // window decorations.
            NSRect screenSize = [[[[SESSION tab] parentWindow] windowScreen] frame];
            //  TODO: WTF do we do with panes here?
            float nch = [[[SESSION tab] parentWindow] windowFrame].size.height - [[[[[SESSION tab] parentWindow] currentSession] SCROLLVIEW] documentVisibleRect].size.height;
            float wch = [[[SESSION tab] parentWindow] windowFrame].size.width - [[[[[SESSION tab] parentWindow] currentSession] SCROLLVIEW] documentVisibleRect].size.width;
            int h = (screenSize.size.height - nch) / [display lineHeight];
            int w =  (screenSize.size.width - wch - MARGIN * 2) / [display charWidth];

            snprintf(buf, sizeof(buf), "\033[9;%d;%dt", h, w);
            [SHELL writeTask: [NSData dataWithBytes:buf length:strlen(buf)]];
        }
        break;
    case XTERMCC_REPORT_ICON_TITLE:
        {
            char buf[64];
            snprintf(buf, sizeof(buf), "\033]L%s\033\\", [[SESSION name] UTF8String]);
            [SHELL writeTask: [NSData dataWithBytes:buf length:strlen(buf)]];
        }
        break;
    case XTERMCC_REPORT_WIN_TITLE:
        {
            char buf[64];
            snprintf(buf, sizeof(buf), "\033]l%s\033\\", [[SESSION windowTitle] UTF8String]);
            [SHELL writeTask: [NSData dataWithBytes:buf length:strlen(buf)]];
        }
        break;

    // Our iTerm specific codes
    case ITERM_GROWL:
        if (GROWL) {
            [gd growlNotify:NSLocalizedStringFromTableInBundle(@"Alert",
                                                               @"iTerm",
                                                               [NSBundle bundleForClass:[self class]],
                                                               @"Growl Alerts")
            withDescription:[NSString stringWithFormat:@"Session %@ #%d: %@",
                             [SESSION name],
                             [[SESSION tab] realObjectCount],
                             token.u.string]
            andNotification:@"Customized Message"];
        }
        break;

    default:
        /*NSLog(@"%s(%d): bug?? token.type = %d",
            __FILE__, __LINE__, token.type);*/
        break;
    }
//    NSLog(@"Done");
}

- (void)clearBuffer
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen clearBuffer]",  __FILE__, __LINE__ );
#endif

    [self clearScreen];
    [self clearScrollbackBuffer];

}

- (void)clearScrollbackBuffer
{
    [linebuffer release];
    linebuffer = [[LineBuffer alloc] init];

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen clearScrollbackBuffer]",  __FILE__, __LINE__ );
#endif

    current_scrollback_lines = 0;
    scrollback_overflow = 0;

    DebugLog(@"clearScrollbackBuffer setDirty");

    [self setDirty];
}

- (void)saveBuffer
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif

    if (temp_buffer) free(temp_buffer);

    int size = REAL_WIDTH*HEIGHT;
    int n = (screen_top - buffer_lines)/REAL_WIDTH;
    temp_buffer = (screen_char_t*)malloc(size*(sizeof(screen_char_t)));
    if (n <= 0)
        memcpy(temp_buffer, screen_top, size*sizeof(screen_char_t));
    else {
        memcpy(temp_buffer, screen_top, (HEIGHT-n)*REAL_WIDTH*sizeof(screen_char_t));
        memcpy(temp_buffer+(HEIGHT-n)*REAL_WIDTH, buffer_lines, n*REAL_WIDTH*sizeof(screen_char_t));
    }
}

- (void)restoreBuffer
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif

    if (!temp_buffer) return;

    int n = (screen_top - buffer_lines) / REAL_WIDTH;
    if (n <= 0)
        memcpy(screen_top, temp_buffer, REAL_WIDTH*HEIGHT*sizeof(screen_char_t));
    else {
        memcpy(screen_top, temp_buffer, (HEIGHT-n)*REAL_WIDTH*sizeof(screen_char_t));
        memcpy(buffer_lines, temp_buffer+(HEIGHT-n)*REAL_WIDTH, n*REAL_WIDTH*sizeof(screen_char_t));
    }

    DebugLog(@"restoreBuffer setDirty");
    [self setDirty];

    free(temp_buffer);
    temp_buffer = NULL;
}

- (BOOL) printToAnsi
{
    return (printToAnsi);
}

- (void) setPrintToAnsi: (BOOL) aFlag
{
    printToAnsi = aFlag;
}

- (void) printStringToAnsi: (NSString *) aString
{
    if ([aString length] > 0)
        [printToAnsiString appendString: aString];
}

static void DumpBuf(screen_char_t* p, int n) {
    for (int i = 0; i < n; ++i) {
        NSLog(@"%3d: \"%@\" (0x%04x)", i, ScreenCharToStr(&p[i]), (int)p[i].code);
    }
}

// Add a combining char to the cell at the cursor position if possible. Returns
// YES if it is able to and NO if there is no base character to combine with.
- (BOOL)addCombiningCharAtCursor:(unichar)combiningChar
{
    // set cx, cy to the char before the cursor.
    int cx = cursorX;
    int cy = cursorY;
    if (cx == 0) {
        cx = WIDTH;
        --cy;
    }
    --cx;
    if (cy < 0) {
        // can't affect characters above screen so have it stand alone.
        return NO;
    }
    screen_char_t* theLine = [self getLineAtScreenIndex:cy];
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

// ascii: True if string contains only ascii characters.
- (void)setString:(NSString *)string ascii:(BOOL)ascii
{
    assert(self);
    assert(string);
    int idx, screenIdx;
    int charsToInsert;
    int len;
    int newx;
    screen_char_t *buffer;
    screen_char_t *aLine;

    if (gDebugLogging) {
        DebugLog([NSString stringWithFormat:@"setString: %d chars starting with %c at x=%d, y=%d, line=%d",
                  [string length], [string characterAtIndex:0],
                  cursorX, cursorY, cursorY + current_scrollback_lines]);
    }

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen setString:%@ at %d]",
          __FILE__, __LINE__, string, cursorX);
#endif

    if ((len=[string length]) < 1 || !string) {
        //NSLog(@"%s: invalid string '%@'", __PRETTY_FUNCTION__, string);
        return;
    }

    // Allocate a buffer of screen_char_t and place the new string in it.
    const int kStaticBufferElements = 1024;
    screen_char_t staticBuffer[kStaticBufferElements];
    screen_char_t* dynamicBuffer = 0;

    if (ascii) {
        // Only Unicode code points 0 through 127 occur in the string.
        const int kStaticTempElements = 1024;
        unichar staticTemp[kStaticTempElements];
        unichar* dynamicTemp = 0;
        unichar *sc;
        if ([string length] > kStaticTempElements) {
            dynamicTemp = sc = (unichar *) malloc(len*sizeof(unichar));
            assert(dynamicTemp);
        } else {
            sc = staticTemp;
        }
        assert(TERMINAL);
        screen_char_t fg = [TERMINAL foregroundColorCode];
        screen_char_t bg = [TERMINAL backgroundColorCode];

        if ([string length] > kStaticBufferElements) {
            buffer = dynamicBuffer = (screen_char_t *) malloc([string length] * sizeof(screen_char_t));
            assert(dynamicBuffer);
            if (!buffer) {
                NSLog(@"%s: Out of memory", __PRETTY_FUNCTION__);
                return;
            }
        } else {
            buffer = staticBuffer;
        }

        [string getCharacters:sc];
        for (int i = 0; i < len; i++) {
            buffer[i].code = sc[i];
            buffer[i].complexChar = NO;
            CopyForegroundColor(&buffer[i], fg);
            CopyBackgroundColor(&buffer[i], bg);
        }

        // If a graphics character set was selected then translate buffer
        // characters into graphics charaters.
        if (charset[[TERMINAL charset]]) {
            translate(buffer,len);
        }
        if (dynamicTemp) {
            free(dynamicTemp);
        }
    } else {
        string = [string precomposedStringWithCanonicalMapping];
        len = [string length];
        if (2 * len > kStaticBufferElements) {
            buffer = dynamicBuffer = (screen_char_t *) malloc(2 * len * sizeof(screen_char_t) );
            assert(buffer);
            if (!buffer) {
                NSLog(@"%s: Out of memory", __PRETTY_FUNCTION__);
                return;
            }
        } else {
            buffer = staticBuffer;
        }

        // Pick off leading combining marks and low surrogates and modify the
        // character at the cursor position with them.
        unichar firstChar = [string characterAtIndex:0];
        while ([string length] > 0 &&
               (IsCombiningMark(firstChar) || IsLowSurrogate(firstChar))) {
            if (![self addCombiningCharAtCursor:firstChar]) {
                // Combining mark will need to stand alone rather than combine
                // because nothing precedes it.
                if (IsCombiningMark(firstChar)) {
                    // Prepend a space to it so the combining mark has something
                    // to combine with.
                    string = [NSString stringWithFormat:@" %@", string];
                } else {
                    // Got a low surrogate but can't find the matching high
                    // surrogate. Turn the low surrogate into a replacement
                    // char. This should never happen because decode_string
                    // ought to detect the broken unicode and substitute a
                    // replacement char.
                    string = [NSString stringWithFormat:@"%@%@",
                              ReplacementString(),
                              [string substringFromIndex:1]];
                }
                len = [string length];
                break;
            }
            string = [string substringFromIndex:1];
            if ([string length] > 0) {
                firstChar = [string characterAtIndex:0];
            }
        }

        // Add DWC_RIGHT after each double-byte character.
        assert(TERMINAL);
        StringToScreenChars(string,
                            buffer,
                            [TERMINAL foregroundColorCode],
                            [TERMINAL backgroundColorCode],
                            &len,
                            [TERMINAL encoding],
                            [SESSION doubleWidth],
                            NULL);
    }

    if (len < 1) {
        // The string is empty so do nothing.
        if (dynamicBuffer) {
            free(dynamicBuffer);
        }
        return;
    }

    // Iterate over each character in the buffer and copy/insert into screen.
    // Grab a block of consecutive characters up to the remaining length in the
    // line and append them at once.
    for (idx = 0; idx < len; )  {
        int startIdx = idx;
#ifdef VERBOSE_STRING
        NSLog(@"Begin inserting line. cursorX=%d, WIDTH=%d", cursorX, WIDTH);
#endif
        NSAssert(buffer[idx].code != DWC_RIGHT, @"DWC cut off");

        if (buffer[idx].code == DWC_SKIP) {
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
        if (cursorX >= WIDTH - widthOffset) {
            if ([TERMINAL wraparoundMode]) {
                // Set the continuation marker
                screen_char_t* prevLine = [self getLineAtScreenIndex:cursorY];
                BOOL splitDwc = (cursorX == WIDTH - 1);
                prevLine[WIDTH].code = (splitDwc ? EOL_DWC : EOL_SOFT);
                if (splitDwc) {
                    prevLine[WIDTH].code = EOL_DWC;
                    prevLine[WIDTH-1].code = DWC_SKIP;
                }
                [self setCursorX:0 Y:cursorY];
                // Advance to the next line
                [self setNewLine];
#ifdef VERBOSE_STRING
                NSLog(@"Advance cursor to next line");
#endif
            } else {
                // Wraparound is off.
                // That means all the characters are effectively inserted at the
                // rightmost position. Move the cursor to the end of the line
                // and insert the last character there.

                // Clear the continuation marker
                [self getLineAtScreenIndex:cursorY][WIDTH].code = EOL_HARD;
                // Cause the loop to end after this character.
                int ncx = WIDTH - 1;

                idx = len-1;
                if (buffer[idx].code == DWC_RIGHT && idx > startIdx) {
                    // The last character to insert is double width. Back up one
                    // byte in buffer and move the cursor left one position.
                    idx--;
                    ncx--;
                }
                if (ncx < 0) {
                    ncx = 0;
                }
                [self setCursorX:ncx Y:cursorY];
                screen_char_t* line = [self getLineAtScreenIndex:cursorY];
                if (line[cursorX].code == DWC_RIGHT) {
                    // This would cause us to overwrite the second part of a
                    // double-width character. Convert it to a space.
                    line[cursorX - 1].code = ' ';
                    line[cursorX - 1].complexChar = NO;
                }

#ifdef VERBOSE_STRING
                NSLog(@"Scribbling on last position");
#endif
            }
        }
        const int spaceRemainingInLine = WIDTH - cursorX;
        const int charsLeftToAppend = len - idx;

#ifdef VERBOSE_STRING
        DumpBuf(buffer + idx, charsLeftToAppend);
#endif
        BOOL wrapDwc = NO;
#ifdef VERBOSE_STRING
        NSLog(@"There is %d space left in the line and we are appending %d chars",
              spaceRemainingInLine, charsLeftToAppend);
#endif
        int effective_width = WIDTH;
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
                newx = WIDTH - 1;
                --effective_width;
            } else {
#ifdef VERBOSE_STRING
                NSLog(@"Inserting up to the end of the line only.");
#endif
                newx = WIDTH;
            }
        } else {
            // This is the last iteration through this loop and we will not
            // advance to another line. Place the cursor at the end of the line
            // where it should be after appending is complete.
            newx = cursorX + charsLeftToAppend;
#ifdef VERBOSE_STRING
            NSLog(@"All remaining chars fit.");
#endif
        }

        // Get the number of chars to insert this iteration (no more than fit
        // on the current line).
        charsToInsert = newx - cursorX;
#ifdef VERBOSE_STRING
        NSLog(@"Will insert %d chars", charsToInsert);
#endif
        if (charsToInsert <= 0) {
            //NSLog(@"setASCIIString: output length=0?(%d+%d)%d+%d",cursorX,charsToInsert,idx2,len);
            break;
        }

        screenIdx = cursorY * WIDTH;
        aLine = [self getLineAtScreenIndex:cursorY];

        if ([TERMINAL insertMode]) {
            if (cursorX + charsToInsert < WIDTH) {
#ifdef VERBOSE_STRING
                NSLog(@"Shifting old contents to the right");
#endif
                // Shift the old line contents to the right by 'charsToInsert' positions.
                screen_char_t* src = aLine + cursorX;
                screen_char_t* dst = aLine + cursorX + charsToInsert;
                int elements = WIDTH - cursorX - charsToInsert;
                if (cursorX > 0 && src[0].code == DWC_RIGHT) {
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
                           aLine[WIDTH].code == EOL_DWC) {
                    // Stomping on a DWC_SKIP. Join the lines normally.
                    aLine[WIDTH].code = EOL_SOFT;
                }
                memmove(dst, src, elements * sizeof(screen_char_t));
                memset(dirty + screenIdx + cursorX,
                       1,
                       WIDTH - cursorX);
            }
        }

        // Overwriting the second-half of a double-width character so turn the
        // DWC into a space.
        if (aLine[cursorX].code == DWC_RIGHT) {
#ifdef VERBOSE_STRING
            NSLog(@"Wiping out the right-half DWC at the cursor before writing to screen");
#endif
            NSAssert(cursorX > 0, @"DWC split");  // there should never be the second half of a DWC at x=0
            aLine[cursorX].code = ' ';
            aLine[cursorX].complexChar = NO;
            aLine[cursorX-1].code = ' ';
            aLine[cursorX-1].complexChar = NO;
            dirty[screenIdx + cursorX] = 1;
            dirty[screenIdx + cursorX - 1] = 1;
        }

        // copy charsToInsert characters into the line and set them dirty.
        memcpy(aLine + cursorX,
               buffer + idx,
               charsToInsert * sizeof(screen_char_t));
        memset(dirty + screenIdx + cursorX,
               1,
               charsToInsert);
        if (wrapDwc) {
            aLine[cursorX + charsToInsert].code = DWC_SKIP;
        }
        [self setCursorX:newx Y:cursorY];
        idx += charsToInsert;

        // Overwrote some stuff that was already on the screen leaving behind the
        // second half of a DWC
        if (cursorX < WIDTH-1 && aLine[cursorX].code == DWC_RIGHT) {
            aLine[cursorX].code = ' ';
            aLine[cursorX].complexChar = NO;
        }

        // The next char in the buffer shouldn't be DWC_RIGHT because we
        // wouldn't have inserted its first half due to a check at the top.
        assert(!(idx < len && buffer[idx].code == DWC_RIGHT));

        // ANSI terminals will go to a new line after displaying a character at
        // the rightmost column.
        if (cursorX >= effective_width && [TERMINAL isAnsi]) {
            if ([TERMINAL wraparoundMode]) {
                //set the wrapping flag
                aLine[WIDTH].code = ((effective_width == WIDTH) ? EOL_SOFT : EOL_DWC);
                [self setCursorX:0 Y:cursorY];
                [self setNewLine];
            } else {
                [self setCursorX:WIDTH - 1
                               Y:cursorY];
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

    if (dynamicBuffer) {
        free(dynamicBuffer);
    }
}

- (void)setStringToX:(int)x
                   Y:(int)y
              string:(NSString *)string
               ascii:(BOOL)ascii
{
    int sx, sy;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen setStringToX:%d Y:%d string:%@]",
          __FILE__, __LINE__, x, y, string);
#endif

    sx = cursorX;
    sy = cursorY;
    [self setCursorX:x Y:y];
    [self setString:string ascii:ascii];
    [self setCursorX:sx Y:sy];
}

- (void)setNewLine
{
    screen_char_t *aLine;
    BOOL wrap = NO;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen setNewLine](%d,%d)-[%d,%d]", __FILE__, __LINE__, cursorX, cursorY, SCROLL_TOP, SCROLL_BOTTOM);
#endif

    if (cursorY < SCROLL_BOTTOM ||
        (cursorY < (HEIGHT - 1) &&
         cursorY > SCROLL_BOTTOM)) {
        [self setCursorX:cursorX Y:cursorY + 1];
        if (cursorX < WIDTH) {
            dirty[cursorY * WIDTH + cursorX] = 1;
        }
        DebugLog(@"setNewline advance cursor");
    } else if (SCROLL_TOP == 0 && SCROLL_BOTTOM == HEIGHT - 1) {
        // Mark the cursor's previous location dirty. This fixes a rare race condition where
        // the cursor is not erased.
        dirty[WIDTH * (cursorY - 1) * sizeof(char) + cursorX - 1] = 1;

        // Top line can move into scroll area; we need to draw only bottom line.
        memmove(dirty, dirty+WIDTH*sizeof(char), WIDTH*(HEIGHT-1)*sizeof(char));
        memset(dirty+WIDTH*(HEIGHT-1)*sizeof(char),1,WIDTH*sizeof(char));

        // try to add top line to scroll area
        int overflowCount = [self _addLineToScrollback];
        if (overflowCount) {
            scrollback_overflow += overflowCount;
            cumulative_scrollback_overflow += overflowCount;
        }

        // Increment screen_top pointer
        screen_top = incrementLinePointer(buffer_lines, screen_top, HEIGHT, WIDTH, &wrap);

        // set last screen line default
        aLine = [self getLineAtScreenIndex: (HEIGHT - 1)];
        memcpy(aLine,
               [self _getDefaultLineWithWidth:WIDTH],
               REAL_WIDTH*sizeof(screen_char_t));
        DebugLog(@"setNewline scroll screen");
    }
    else
    {
        [self scrollUp];
        DebugLog(@"setNewline weird case");
    }
}

- (long long)totalScrollbackOverflow
{
    return cumulative_scrollback_overflow;
}

- (void)deleteCharacters:(int) n
{
    screen_char_t *aLine;
    int i;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen deleteCharacter]: %d", __FILE__, __LINE__, n);
#endif

    if (cursorX >= 0 && cursorX < WIDTH &&
        cursorY >= 0 && cursorY < HEIGHT) {
        int idx;

        idx = cursorY * WIDTH;
        if (n + cursorX > WIDTH) {
            n = WIDTH - cursorX;
        }

        // get the appropriate screen line
        aLine = [self getLineAtScreenIndex:cursorY];

        if (n<WIDTH) {
            memmove(aLine + cursorX,
                    aLine + cursorX + n,
                    (WIDTH - cursorX - n) * sizeof(screen_char_t));
        }
        for (i = 0; i < n; i++) {
            aLine[WIDTH-n+i].code = 0;
            CopyForegroundColor(&aLine[WIDTH-n+i], [TERMINAL foregroundColorCodeReal]);
            CopyBackgroundColor(&aLine[WIDTH-n+i], [TERMINAL backgroundColorCodeReal]);
        }
        DebugLog(@"deleteCharacters");

        memset(dirty + idx + cursorX, 1, WIDTH - cursorX);
    }
}

- (void)backSpace
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen backSpace]", __FILE__, __LINE__);
#endif
    if (cursorX > 0) {
        if (cursorX >= WIDTH) {
            [self setCursorX:cursorX - 2 Y:cursorY];
        } else {
            [self setCursorX:cursorX - 1 Y:cursorY];
        }
    }
}

- (void)backTab
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen backTab]", __FILE__, __LINE__);
#endif

    [self setCursorX:cursorX - 1 Y:cursorY];
    for (;
         ![self haveTabStopAt:cursorX] && cursorX > 0;
         [self setCursorX:cursorX - 1 Y:cursorY]) {
        ;
    }

    if (cursorX < 0) {
        [self setCursorX:0 Y:cursorY];
    }
}

- (void)setTab
{

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen setTab]", __FILE__, __LINE__);
#endif

    screen_char_t* aLine = [self getLineAtScreenIndex:cursorY];
    int positions = 0;
    BOOL allNulls = YES;

    // Advance cursor to next tab stop. Count the number of positions advanced
    // and record whether they were all nulls.
    if (aLine[cursorX].code != 0) {
        allNulls = NO;
    }

    ++positions;
    // ensure we go to the next tab in case we are already on one
    [self setCursorX:cursorX + 1 Y:cursorY];
    for (; ; [self setCursorX:cursorX + 1 Y:cursorY], ++positions) {
        if (cursorX == WIDTH) {
            // Wrap around to the next line.
            if (aLine[cursorX].code == EOL_HARD) {
                aLine[cursorX].code = EOL_SOFT;
            }
            [self setNewLine];
            [self setCursorX:0 Y:cursorY];
            aLine = [self getLineAtScreenIndex:cursorY];
        }
        if ([self haveTabStopAt:cursorX]) {
            break;
        }
        if (aLine[cursorX].code != 0) {
            allNulls = NO;
        }
    }
    dirty[cursorX + cursorY * REAL_WIDTH] = 1;
    if (allNulls) {
        // If only nulls were advanced over, convert them to tab fillers
        // and place a tab character at the end of the run.
        int x = cursorX;
        int y = cursorY;
        --x;
        if (x < 0) {
            x = WIDTH - 1;
            --y;
        }
        unichar replacement = '\t';
        while (positions--) {
            aLine = [self getLineAtScreenIndex:y];
            aLine[x].code = replacement;
            replacement = TAB_FILLER;
            --x;
            if (x < 0) {
                x = WIDTH - 1;
                --y;
            }
        }
    }
}

- (void)clearScreen
{
    screen_char_t *aLine, *aDefaultLine;
    int i, j;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen clearScreen]; cursorY = %d", __FILE__, __LINE__, cursorY);
#endif

    if (cursorY < 0) {
        return;
    }

    // make the current line the first line and clear everything else
    for (i = cursorY - 1; i >= 0; i--) {
        aLine = [self getLineAtScreenIndex:i];
        if (aLine[WIDTH].code == EOL_HARD) {
            break;
        }
    }
    // i is the index of the lowest nonempty line above the cursor
    // copy the lines between that and the cursor to the top of the screen
    for (j = 0, i++; i <= cursorY; i++, j++) {
        aLine = [self getLineAtScreenIndex:i];
        memcpy(screen_top + j * REAL_WIDTH,
               aLine,
               REAL_WIDTH * sizeof(screen_char_t));
    }

    [self setCursorX:cursorX Y:j - 1];
    aDefaultLine = [self _getDefaultLineWithWidth:WIDTH];
    for (i = j; i < HEIGHT; i++) {
        aLine = [self getLineAtScreenIndex:i];
        memcpy(aLine, aDefaultLine, REAL_WIDTH*sizeof(screen_char_t));
    }

    // all the screen is dirty
    DebugLog(@"clearScreen setDirty");

    [self setDirty];

}

- (int)_lastNonEmptyLine
{
    int y;
    int x;
    for (y = HEIGHT - 1; y >= 0; --y) {
        screen_char_t* aLine = [self getLineAtScreenIndex: y];
        for (x = 0; x < WIDTH; ++x) {
            if (aLine[x].code) {
                return y;
            }
        }
    }
    return y;
}

- (void)scrollScreenIntoScrollbackBuffer:(int)leaving
{
    // Move the current screen into the scrollback buffer unless it's empty.
    int cx = cursorX;
    int cy = cursorY;
    int st = SCROLL_TOP;
    int sb = SCROLL_BOTTOM;

    SCROLL_TOP = 0;
    SCROLL_BOTTOM = HEIGHT - 1;
    [self setCursorX:cursorX Y:HEIGHT - 1];
    int last_line = [self _lastNonEmptyLine];
    for (int j = 0; j <= last_line - leaving; ++j) {
        [self setNewLine];
    }
    [self setCursorX:cx Y:cy];
    SCROLL_TOP = st;
    SCROLL_BOTTOM = sb;
}

- (void)eraseInDisplay:(VT100TCC)token
{
    int x1, yStart, x2, y2;
    int i;
    screen_char_t *aScreenChar;
    //BOOL wrap;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen eraseInDisplay:(param=%d); X = %d; Y = %d]",
          __FILE__, __LINE__, token.u.csi.p[0], cursorX, cursorY);
#endif
    switch (token.u.csi.p[0]) {
    case 1:
        x1 = 0;
        yStart = 0;
        x2 = cursorX < WIDTH ? cursorX + 1 : WIDTH;
        y2 = cursorY;
        break;

    case 2:
        [self scrollScreenIntoScrollbackBuffer:0];
        x1 = 0;
        yStart = 0;
        x2 = 0;
        y2 = HEIGHT;
        break;

    case 0:
    default:
        x1 = cursorX;
        yStart = cursorY;
        x2 = 0;
        y2 = HEIGHT;
        break;
    }

    int idx1, idx2;

    idx1=yStart*REAL_WIDTH+x1;
    idx2=y2*REAL_WIDTH+x2;

    // clear the contents between idx1 and idx2
    for(i = idx1, aScreenChar = screen_top + idx1; i < idx2; i++, aScreenChar++) {
        if (aScreenChar >= (buffer_lines + HEIGHT*REAL_WIDTH)) {
            aScreenChar -= HEIGHT * REAL_WIDTH; // wrap around to top of buffer
            assert(aScreenChar < (buffer_lines + HEIGHT*REAL_WIDTH));  // Tried to go way past the end of the screen
        }
        aScreenChar->code = 0;
        CopyForegroundColor(aScreenChar, [TERMINAL foregroundColorCodeReal]);
        CopyBackgroundColor(aScreenChar, [TERMINAL backgroundColorCodeReal]);
    }

    memset(dirty + yStart * WIDTH + x1,
           1,
           ((y2 - yStart) * WIDTH + (x2 - x1)) * sizeof(char));
    DebugLog(@"eraseInDisplay");
}

- (void)eraseInLine:(VT100TCC)token
{
    screen_char_t *aLine;
    int i;
    int idx, x1 ,x2;
    screen_char_t fgCode;
    screen_char_t bgCode;

    x1 = x2 = 0;
    switch (token.u.csi.p[0]) {
        case 1:
            x1 = 0;
            x2 = cursorX < WIDTH ? cursorX + 1 : WIDTH;
            break;
        case 2:
            x1 = 0;
            x2 = WIDTH;
            break;
        case 0:
            x1 = cursorX;
            x2 = WIDTH;
            break;
    }
    aLine = [self getLineAtScreenIndex:cursorY];

    fgCode = [TERMINAL foregroundColorCodeReal];
    bgCode = [TERMINAL backgroundColorCodeReal];

    for (i = x1; i < x2; i++) {
        aLine[i].code = 0;
        aLine[i].complexChar = NO;
        CopyForegroundColor(&aLine[i], fgCode);
        CopyBackgroundColor(&aLine[i], bgCode);
    }

    idx = cursorY * WIDTH + x1;
    memset(dirty + idx, 1, (x2 - x1) * sizeof(char));
    DebugLog(@"eraseInLine");
}

- (void)selectGraphicRendition:(VT100TCC)token
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen selectGraphicRendition:...]",
      __FILE__, __LINE__);
#endif

}

- (void)cursorLeft:(int)n
{
    int x = cursorX - (n > 0 ? n : 1);

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen cursorLeft:%d]",
      __FILE__, __LINE__, n);
#endif
    if (x < 0)
        x = 0;
    if (x >= 0 && x < WIDTH) {
        [self setCursorX:x Y:cursorY];
    }

    dirty[cursorY * WIDTH + cursorX] = 1;
    DebugLog(@"cursorLeft");
}

- (void)cursorRight:(int)n
{
    int x = cursorX + (n > 0 ? n : 1);

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen cursorRight:%d]",
          __FILE__, __LINE__, n);
#endif
    if (x >= WIDTH)
        x =  WIDTH - 1;
    if (x >= 0 && x < WIDTH) {
        [self setCursorX:x Y:cursorY];
    }

    dirty[cursorY * WIDTH + cursorX] = 1;
    DebugLog(@"cursorRight");
}

- (void)cursorUp:(int)n
{
    int y = cursorY - (n > 0 ? n : 1);

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen cursorUp:%d]",
          __FILE__, __LINE__, n);
#endif
    if (cursorY >= SCROLL_TOP) {
        [self setCursorX:cursorX Y:y < SCROLL_TOP ? SCROLL_TOP : y];
    } else {
        [self setCursorX:cursorX Y:y];
    }
    if (cursorX < WIDTH) {
        dirty[cursorY * WIDTH + cursorX] = 1;
        DebugLog(@"cursorUp");
    }
}

- (void)cursorDown:(int)n
{
    int y = cursorY + (n > 0 ? n : 1);

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen cursorDown:%d, Y = %d; SCROLL_BOTTOM = %d]",
          __FILE__, __LINE__, n, cursorY, SCROLL_BOTTOM);
#endif
    if (cursorY <= SCROLL_BOTTOM) {
        [self setCursorX:cursorX Y:y > SCROLL_BOTTOM ? SCROLL_BOTTOM : y];
    } else {
        [self setCursorX:cursorX Y:y];
    }

    if (cursorX < WIDTH) {
        dirty[cursorY * WIDTH + cursorX] = 1;
        DebugLog(@"cursorDown");
    }
}

- (void) cursorToX: (int) x
{
    int x_pos;


#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen cursorToX:%d]",
          __FILE__, __LINE__, x);
#endif
    x_pos = (x-1);

    if (x_pos < 0) {
        x_pos = 0;
    } else if (x_pos >= WIDTH) {
        x_pos = WIDTH - 1;
    }

    [self setCursorX:x_pos Y:cursorY];

    dirty[cursorY * WIDTH + cursorX] = 1;
    DebugLog(@"cursorToX");

}

- (void)cursorToX:(int)x Y:(int)y
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen cursorToX:%d Y:%d]",
          __FILE__, __LINE__, x, y);
#endif
    int x_pos, y_pos;


    x_pos = x - 1;
    y_pos = y - 1;

    if ([TERMINAL originMode]) y_pos += SCROLL_TOP;

    if (x_pos < 0) {
        x_pos = 0;
    } else if (x_pos >= WIDTH) {
        x_pos = WIDTH - 1;
    }
    if (y_pos < 0) {
        y_pos = 0;
    } else if (y_pos >= HEIGHT) {
        y_pos = HEIGHT - 1;
    }

    [self setCursorX:x_pos Y:y_pos];

    dirty[cursorY * WIDTH + cursorX] = 1;
    DebugLog(@"cursorToX:Y");
}

- (void)saveCursorPosition
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen saveCursorPosition]", __FILE__, __LINE__);
#endif

    int nx = cursorX;
    int ny = cursorY;
    if (nx < 0) {
        nx = 0;
    }
    if (nx >= WIDTH) {
        nx = WIDTH - 1;
    }
    if (ny < 0) {
        ny = 0;
    }
    if (ny >= HEIGHT) {
        ny = HEIGHT;
    }
    [self setCursorX:nx Y:ny];

    if (temp_buffer) {
        ALT_SAVE_CURSOR_X = cursorX;
        ALT_SAVE_CURSOR_Y = cursorY;
    } else {
        SAVE_CURSOR_X = cursorX;
        SAVE_CURSOR_Y = cursorY;
    }

    for (int i = 0; i < 4; i++) {
        saveCharset[i] = charset[i];
    }
}

- (void)restoreCursorPosition
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen restoreCursorPosition]", __FILE__, __LINE__);
#endif

    if(temp_buffer) {
        [self setCursorX:ALT_SAVE_CURSOR_X Y:ALT_SAVE_CURSOR_Y];
    } else {
        [self setCursorX:SAVE_CURSOR_X Y:SAVE_CURSOR_Y];
    }

    for (int i = 0; i < 4; i++) {
        charset[i] = saveCharset[i];
    }

    NSParameterAssert(cursorX >= 0 && cursorX < WIDTH);
    NSParameterAssert(cursorY >= 0 && cursorY < HEIGHT);
}

- (void)setTopBottom:(VT100TCC)token
{
    int top, bottom;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen setTopBottom:(%d,%d)]",
      __FILE__, __LINE__, token.u.csi.p[0], token.u.csi.p[1]);
#endif

    top = token.u.csi.p[0] == 0 ? 0 : token.u.csi.p[0] - 1;
    bottom = token.u.csi.p[1] == 0 ? HEIGHT - 1 : token.u.csi.p[1] - 1;
    if (top >= 0 && top < HEIGHT &&
        bottom >= 0 && bottom < HEIGHT &&
        bottom >= top)
    {
        SCROLL_TOP = top;
        SCROLL_BOTTOM = bottom;

        if ([TERMINAL originMode]) {
            [self setCursorX:0 Y:SCROLL_TOP];
        } else {
            [self setCursorX:0 Y:0];
        }
    }
}

- (void)scrollUp
{
    int i;
    screen_char_t *sourceLine, *targetLine;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen scrollUp]", __FILE__, __LINE__);
#endif

    NSParameterAssert(SCROLL_TOP >= 0 && SCROLL_TOP < HEIGHT);
    NSParameterAssert(SCROLL_BOTTOM >= 0 && SCROLL_BOTTOM < HEIGHT);
    NSParameterAssert(SCROLL_TOP <= SCROLL_BOTTOM );

    if (SCROLL_TOP == 0 && SCROLL_BOTTOM == HEIGHT -1)
    {
        [self setNewLine];
    }
    else if (SCROLL_TOP<SCROLL_BOTTOM)
    {
        // SCROLL_TOP is not top of screen; move all lines between SCROLL_TOP and SCROLL_BOTTOM one line up
        // check if the screen area is wrapped
        sourceLine = [self getLineAtScreenIndex: SCROLL_TOP];
        targetLine = [self getLineAtScreenIndex: SCROLL_BOTTOM];
        if(sourceLine < targetLine)
        {
            // screen area is not wrapped; direct memmove
            memmove(sourceLine, sourceLine+REAL_WIDTH, (SCROLL_BOTTOM-SCROLL_TOP)*REAL_WIDTH*sizeof(screen_char_t));
        }
        else
        {
            // screen area is wrapped; copy line by line
            for(i = SCROLL_TOP; i < SCROLL_BOTTOM; i++)
            {
                sourceLine = [self getLineAtScreenIndex:i+1];
                targetLine = [self getLineAtScreenIndex: i];
                memmove(targetLine, sourceLine, REAL_WIDTH*sizeof(screen_char_t));
            }
        }
        // new line at SCROLL_BOTTOM with default settings
        targetLine = [self getLineAtScreenIndex:SCROLL_BOTTOM];
        memcpy(targetLine,
               [self _getDefaultLineWithWidth:WIDTH],
               REAL_WIDTH*sizeof(screen_char_t));

        // everything between SCROLL_TOP and SCROLL_BOTTOM is dirty
        memset(dirty+SCROLL_TOP*WIDTH,1,(SCROLL_BOTTOM-SCROLL_TOP+1)*WIDTH*sizeof(char));
        DebugLog(@"scrollUp");
    }
}

- (void)scrollDown
{
    int i;
    screen_char_t *sourceLine, *targetLine;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen scrollDown]", __FILE__, __LINE__);
#endif

    NSParameterAssert(SCROLL_TOP >= 0 && SCROLL_TOP < HEIGHT);
    NSParameterAssert(SCROLL_BOTTOM >= 0 && SCROLL_BOTTOM < HEIGHT);
    NSParameterAssert(SCROLL_TOP <= SCROLL_BOTTOM );

    if (SCROLL_TOP<SCROLL_BOTTOM)
    {
        // move all lines between SCROLL_TOP and SCROLL_BOTTOM one line down
        // check if screen is wrapped
        sourceLine = [self getLineAtScreenIndex:SCROLL_TOP];
        targetLine = [self getLineAtScreenIndex:SCROLL_BOTTOM];
        if(sourceLine < targetLine)
        {
            // screen area is not wrapped; direct memmove
            memmove(sourceLine+REAL_WIDTH, sourceLine, (SCROLL_BOTTOM-SCROLL_TOP)*REAL_WIDTH*sizeof(screen_char_t));
        }
        else
        {
            // screen area is wrapped; move line by line
            for(i = SCROLL_BOTTOM - 1; i >= SCROLL_TOP; i--)
            {
                sourceLine = [self getLineAtScreenIndex:i];
                targetLine = [self getLineAtScreenIndex:i+1];
                memmove(targetLine, sourceLine, REAL_WIDTH*sizeof(screen_char_t));
            }
        }
    }
    // new line at SCROLL_TOP with default settings
    targetLine = [self getLineAtScreenIndex:SCROLL_TOP];
    memcpy(targetLine,
           [self _getDefaultLineWithWidth:WIDTH],
           REAL_WIDTH*sizeof(screen_char_t));

    // everything between SCROLL_TOP and SCROLL_BOTTOM is dirty
    memset(dirty+SCROLL_TOP*WIDTH,1,(SCROLL_BOTTOM-SCROLL_TOP+1)*WIDTH*sizeof(char));
    DebugLog(@"scrollDown");
}

- (void) insertBlank: (int)n
{
    screen_char_t *aLine;
    int i;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen insertBlank; %d]", __FILE__, __LINE__, n);
#endif


//    NSLog(@"insertBlank[%d@(%d,%d)]",n,cursorX,cursorY);

    if (cursorX >= WIDTH) {
        return;
    }

    if (n + cursorX > WIDTH) {
        n = WIDTH - cursorX;
    }

    // get the appropriate line
    aLine = [self getLineAtScreenIndex:cursorY];

    memmove(aLine + cursorX + n,
            aLine + cursorX,
            (WIDTH - cursorX - n) * sizeof(screen_char_t));

    for (i = 0; i < n; i++) {
        aLine[cursorX + i].code = 0;
        aLine[cursorX + i].complexChar = NO;
        CopyForegroundColor(&aLine[cursorX + i], [TERMINAL foregroundColorCode]);
        CopyBackgroundColor(&aLine[cursorX + i], [TERMINAL backgroundColorCode]);
    }

    // everything from cursorX to end of line is dirty
    int screenIdx = cursorY * WIDTH + cursorX;
    memset(dirty + screenIdx, 1, WIDTH - cursorX);
    DebugLog(@"insertBlank");
}

- (void) insertLines: (int)n
{
    int i, num_lines_moved;
    screen_char_t *sourceLine, *targetLine, *aDefaultLine;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen insertLines; %d]", __FILE__, __LINE__, n);
#endif


//    NSLog(@"insertLines %d[%d,%d]",n, cursorX,cursorY);
    if (n + cursorY <= SCROLL_BOTTOM) {
        // number of lines we can move down by n before we hit SCROLL_BOTTOM
        num_lines_moved = SCROLL_BOTTOM - (cursorY + n);
        // start from lower end
        for (i = num_lines_moved ; i >= 0; i--) {
            sourceLine = [self getLineAtScreenIndex:cursorY + i];
            targetLine = [self getLineAtScreenIndex:cursorY + i + n];
            memcpy(targetLine, sourceLine, REAL_WIDTH * sizeof(screen_char_t));
        }

    }
    if (n + cursorY > SCROLL_BOTTOM) {
        n  = SCROLL_BOTTOM - cursorY + 1;
    }

    // clear the n lines
    aDefaultLine = [self _getDefaultLineWithWidth:WIDTH];
    for (i = 0; i < n; i++) {
        sourceLine = [self getLineAtScreenIndex:cursorY + i];
        memcpy(sourceLine, aDefaultLine, REAL_WIDTH*sizeof(screen_char_t));
    }

    // everything between cursorY and SCROLL_BOTTOM is dirty
    memset(dirty + cursorY * WIDTH, 1, (SCROLL_BOTTOM - cursorY + 1) * WIDTH);
    DebugLog(@"insertLines");
}

- (void)deleteLines: (int)n
{
    int i, num_lines_moved;
    screen_char_t *sourceLine, *targetLine, *aDefaultLine;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen deleteLines; %d]", __FILE__, __LINE__, n);
#endif

    //    NSLog(@"insertLines %d[%d,%d]",n, cursorX,cursorY);
    if (n + cursorY <= SCROLL_BOTTOM) {
        // number of lines we can move down by n before we hit SCROLL_BOTTOM
        num_lines_moved = SCROLL_BOTTOM - (cursorY + n);

        for (i = 0; i <= num_lines_moved; i++) {
            sourceLine = [self getLineAtScreenIndex:cursorY + i + n];
            targetLine = [self getLineAtScreenIndex:cursorY + i];
            memcpy(targetLine, sourceLine, REAL_WIDTH*sizeof(screen_char_t));
        }

    }
    if (n + cursorY > SCROLL_BOTTOM) {
        n = SCROLL_BOTTOM - cursorY + 1;
    }
    // clear the n lines
    aDefaultLine = [self _getDefaultLineWithWidth:WIDTH];
    for (i = 0; i < n; i++) {
        sourceLine = [self getLineAtScreenIndex:SCROLL_BOTTOM-n+1+i];
        memcpy(sourceLine, aDefaultLine, REAL_WIDTH*sizeof(screen_char_t));
    }

    // everything between cursorY and SCROLL_BOTTOM is dirty
    memset(dirty + cursorY * WIDTH, 1, (SCROLL_BOTTOM - cursorY + 1) * WIDTH);
    DebugLog(@"deleteLines");

}

- (void)setPlayBellFlag:(BOOL)flag
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):+[VT100Screen setPlayBellFlag:%s]",
          __FILE__, __LINE__, flag == YES ? "YES" : "NO");
#endif
    PLAYBELL = flag;
}

- (void)setShowBellFlag:(BOOL)flag
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):+[VT100Screen setShowBellFlag:%s]",
          __FILE__, __LINE__, flag == YES ? "YES" : "NO");
#endif
    SHOWBELL = flag;
}

- (void)setFlashBellFlag:(BOOL)flag
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):+[VT100Screen setFlashBellFlag:%s]",
          __FILE__, __LINE__, flag == YES ? "YES" : "NO");
#endif
    FLASHBELL = flag;
}

- (void)activateBell
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen playBell]",  __FILE__, __LINE__);
#endif
    if (PLAYBELL) {
        NSBeep();
    }
    if (SHOWBELL) {
        [SESSION setBell:YES];
    }
    if (FLASHBELL) {
        [display beginFlash];
    }
}

- (void)setGrowlFlag:(BOOL)flag
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):+[VT100Screen setGrowlFlag:%s]",
          __FILE__, __LINE__, flag == YES ? "YES" : "NO");
#endif
    GROWL = flag;
}

- (void)deviceReport:(VT100TCC)token
{
    NSData *report = nil;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen deviceReport:%d]",
          __FILE__, __LINE__, token.u.csi.p[0]);
#endif
    if (SHELL == nil)
        return;

    switch (token.u.csi.p[0]) {
        case 3: // response from VT100 -- Malfunction -- retry
            break;

        case 5: // Command from host -- Please report status
            report = [TERMINAL reportStatus];
            break;

        case 6: // Command from host -- Please report active position
        {
            int x, y;

            if ([TERMINAL originMode]) {
                x = cursorX + 1;
                y = cursorY - SCROLL_TOP + 1;
            }
            else {
                x = cursorX + 1;
                y = cursorY + 1;
            }
            report = [TERMINAL reportActivePositionWithX:x Y:y withQuestion:token.u.csi.question];
        }
            break;

        case 0: // Response from VT100 -- Ready, No malfuctions detected
        default:
            break;
    }

    if (report != nil) {
        [SHELL writeTask:report];
    }
}

- (void)deviceAttribute:(VT100TCC)token
{
    NSData *report = nil;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[VT100Screen deviceAttribute:%d, modifier = '%c']",
          __FILE__, __LINE__, token.u.csi.p[0], token.u.csi.modifier);
#endif
    if (SHELL == nil)
        return;

    if(token.u.csi.modifier == '>')
        report = [TERMINAL reportSecondaryDeviceAttribute];
    else
        report = [TERMINAL reportDeviceAttribute];

    if (report != nil) {
        [SHELL writeTask:report];
    }
}

- (void)showCursor:(BOOL)show
{
    if (show)
        [display showCursor];
    else
        [display hideCursor];
}

- (void)blink
{
    if (memchr(dirty, 1, WIDTH*HEIGHT)) {
        [display refresh];
    }
}

- (int) cursorX
{
    return cursorX+1;
}

- (int) cursorY
{
    return cursorY+1;
}

- (void)clearTabStop
{
    [tabStops removeAllObjects];
}

- (BOOL)haveTabStopAt:(int)x
{
    return [tabStops containsObject:[NSNumber numberWithInt:x]];
}

- (void)setTabStopAt:(int)x
{
    [tabStops addObject:[NSNumber numberWithInt:x]];
}

- (void)removeTabStopAt:(int)x
{
    [tabStops removeObject:[NSNumber numberWithInt:x]];
}

- (int)numberOfLines
{
    return current_scrollback_lines + HEIGHT;
}

- (int)scrollbackOverflow
{
    return scrollback_overflow;
}

- (void)resetScrollbackOverflow
{
    scrollback_overflow = 0;
}

- (char *)dirty
{
    return dirty;
}


- (void)resetDirty
{
    DebugLog(@"resetDirty");
    memset(dirty,0,WIDTH*HEIGHT*sizeof(char));
    DebugLog(@"resetDirty");
}

- (void)setDirty
{
//    memset(dirty,1,WIDTH*HEIGHT*sizeof(char));
    [self resetScrollbackOverflow];
    [display deselect];
    [display setNeedsDisplay:YES];
    DebugLog(@"setDirty (doesn't actually set dirty)");
}

- (void) doPrint
{
    if([printToAnsiString length] > 0)
        [[SESSION TEXTVIEW] printContent: printToAnsiString];
    else
        [[SESSION TEXTVIEW] print: nil];
    [printToAnsiString release];
    printToAnsiString = nil;
    [self setPrintToAnsi: NO];
}

- (BOOL)isDoubleWidthCharacter:(unichar)c
{
    return [NSString isDoubleWidthCharacter:c
                                   encoding:[TERMINAL encoding]
                     ambiguousIsDoubleWidth:[SESSION doubleWidth]];
}

- (void)_popScrollbackLines:(int)linesPushed
{
    // Undo the appending of the screen to scrollback
    int i;
    screen_char_t* dummy = malloc(WIDTH * sizeof(screen_char_t));
    for (i = 0; i < linesPushed; ++i) {
        int cont;
        BOOL isOk = [linebuffer popAndCopyLastLineInto: dummy width: WIDTH includesEndOfLine: &cont];
        NSAssert(isOk, @"Pop shouldn't fail");
    }
    free(dummy);
}

- (FindContext*)findContext
{
    return &findContext;
}

- (void)initFindString:(NSString*)aString
      forwardDirection:(BOOL)direction
          ignoringCase:(BOOL)ignoreCase
           startingAtX:(int)x
           startingAtY:(int)y
            withOffset:(int)offset
             inContext:(FindContext*)context
{
    // Append the screen contents to the scrollback buffer so they are included in the search.
    int linesPushed;
    linesPushed = [self _appendScreenToScrollback];

    // Get the start position of (x,y)
    int startPos;
    BOOL isOk = [linebuffer convertCoordinatesAtX:x
                                            atY:y
                                      withWidth:WIDTH
                                     toPosition:&startPos
                                         offset:offset * (direction ? 1 : -1)];
    if (!isOk) {
        // NSLog(@"Couldn't convert %d,%d to position", x, y);
        if (direction) {
            startPos = [linebuffer firstPos];
        } else {
            startPos = [linebuffer lastPos] - 1;
        }
    }

    // Set up the options bitmask and call findSubstring.
    int opts = 0;
    if (!direction) {
        opts |= FindOptBackwards;
    }
    if (ignoreCase) {
        opts |= FindOptCaseInsensitive;
    }
    [linebuffer initFind:aString startingAt:startPos options:opts withContext:context];
    context->hasWrapped = NO;
    [self _popScrollbackLines:linesPushed];
}

- (void)cancelFindInContext:(FindContext*)context
{
    [linebuffer releaseFind:context];
}

- (BOOL)continueFindResultAtStartX:(int*)startX
                          atStartY:(int*)startY
                            atEndX:(int*)endX
                            atEndY:(int*)endY
                             found:(BOOL*)found
                         inContext:(FindContext*)context
{
    // Append the screen contents to the scrollback buffer so they are included in the search.
    int linesPushed;
    linesPushed = [self _appendScreenToScrollback];

    // Search one block.
    int stopAt;
    if (context->dir > 0) {
        stopAt = [linebuffer lastPos];
    } else {
        stopAt = [linebuffer firstPos];
    }

    struct timeval begintime;
    gettimeofday(&begintime, NULL);
    BOOL keepSearching = NO;
    int iterations = 0;
    int ms_diff = 0;
    do {
        if (context->status == Searching) {
            // NSLog(@"VT100Screen: Search next block");
            [linebuffer findSubstring:context stopAt:stopAt];
        }

        // Handle the current state
        BOOL isOk;
        switch (context->status) {
            case Matched:
                // NSLog(@"matched");
                // Found a match in the text.
                isOk = [linebuffer convertPosition:context->resultPosition
                                       withWidth:WIDTH
                                             toX:startX
                                             toY:startY];
                NSAssert(isOk, @"Couldn't convert start position");

                isOk = [linebuffer convertPosition:context->resultPosition + context->matchLength - 1
                                       withWidth:WIDTH
                                             toX:endX
                                             toY:endY];
                NSAssert(isOk, @"Couldn't convert end position");
                [linebuffer releaseFind:context];
                keepSearching = NO;
                *found = YES;
                break;

            case Searching:
                // NSLog(@"searching");
                // No result yet but keep looking
                keepSearching = YES;
                *found = NO;
                break;

            case NotFound:
                // NSLog(@"not found");
                // Reached stopAt point with no match.
                if (context->hasWrapped) {
                    [linebuffer releaseFind:context];
                    keepSearching = NO;
                } else {
                    // NSLog(@"...wrapping");
                    // wrap around and resume search.
                    FindContext temp;
                    [linebuffer initFind:findContext.substring
                              startingAt:(findContext.dir > 0 ? [linebuffer firstPos] : [linebuffer lastPos]-1)
                                 options:findContext.options
                             withContext:&temp];
                    [linebuffer releaseFind:&findContext];
                    *context = temp;
                    context->hasWrapped = YES;
                    keepSearching = YES;
                }
                *found = NO;
                break;

            default:
                NSAssert(0, @"Bogus status");
        }

        struct timeval endtime;
        if (keepSearching) {
            gettimeofday(&endtime, NULL);
            ms_diff = (endtime.tv_sec - begintime.tv_sec) * 1000 +
                      (endtime.tv_usec - begintime.tv_usec) / 1000;
        }
        ++iterations;
    } while (keepSearching && ms_diff < 100);
    // NSLog(@"Did %d iterations in %dms. Average time per block was %dms", iterations, ms_diff, ms_diff/iterations);

    [self _popScrollbackLines:linesPushed];
    return keepSearching;
}

- (void)saveToDvr
{
    if (!dvr || ![[PreferencePanel sharedInstance] instantReplay]) {
        return;
    }

    DVRFrameInfo info;
    info.cursorX = cursorX;
    info.cursorY = cursorY;
    info.height = HEIGHT;
    info.width = WIDTH;
    info.topOffset = screen_top - buffer_lines;

    [dvr appendFrame:(char*)buffer_lines
              length:sizeof(screen_char_t) * REAL_WIDTH * HEIGHT
                info:&info];
}

- (void)disableDvr
{
    [dvr release];
    dvr = nil;
}

- (void)setFromFrame:(screen_char_t*)s len:(int)len info:(DVRFrameInfo)info
{
    int yo = 0;
    if (info.width == WIDTH && info.height == HEIGHT) {
        memcpy(buffer_lines, s, len);
        screen_top = buffer_lines + info.topOffset;
        [self setDirty];
    } else {
        yo = info.height - HEIGHT;
        if (yo < 0) {
            // Display is larger than history. Happens if you're in fullscreen.
            yo = 0;
        }
        int widthToCopy = WIDTH;
        if (info.width < WIDTH) {
            // Display is larger than history. Happens if you're in fullscreen.
            widthToCopy = info.width;
        }

        screen_char_t* lineOut;
        screen_char_t* lineIn;

        int truncateHistoryLines = 0;
        if (HEIGHT < info.height) {
            truncateHistoryLines = info.height - HEIGHT;
        }

        screen_top = buffer_lines;
        for (int y = 0; y < HEIGHT && y < info.height; ++y) {
            lineOut = buffer_lines + y * REAL_WIDTH;
            lineIn = s + ((info.topOffset + (truncateHistoryLines + y) * (info.width + 1)) % (len / sizeof(screen_char_t)));
            memcpy(lineOut, lineIn, widthToCopy * sizeof(screen_char_t));
            if (WIDTH > info.width) {
                // Display wider than history
                memset(lineOut + widthToCopy, 0, (WIDTH - widthToCopy) * sizeof(screen_char_t));
                lineOut[WIDTH].code = 0;
                lineOut[WIDTH].complexChar = NO;
            } else {
                // History too wide for screen
                if (lineIn[widthToCopy].code == DWC_RIGHT) {
                    lineOut[widthToCopy - 1].code = 0;
                    lineOut[widthToCopy - 1].complexChar = NO;
                }
                if (lineOut[widthToCopy - 1].code == TAB_FILLER) {
                    lineOut[widthToCopy - 1].code = '\t';
                    lineOut[widthToCopy - 1].complexChar = NO;
                }
            }
        }
        for (int y = info.height; y < HEIGHT; ++y) {
            lineOut = buffer_lines + y * REAL_WIDTH;
            memset(lineOut, 0, REAL_WIDTH * sizeof(screen_char_t));
        }
        [self setDirty];
    }
    cursorX = info.cursorX;
    cursorY = info.cursorY - yo;
    if (cursorX < 0) {
        cursorX = 0;
    }
    if (cursorY < 0) {
        cursorY = 0;
    }
    if (cursorX >= WIDTH) {
        cursorX = WIDTH - 1;
    }
    if (cursorY >= HEIGHT) {
        cursorY = HEIGHT - 1;
    }
}

- (DVR*)dvr
{
    return dvr;
}


@end

@implementation VT100Screen (Private)

// gets line offset by specified index from specified line poiner; accounts for buffer wrap
- (screen_char_t *)_getLineAtIndex:(int)anIndex fromLine:(screen_char_t *)aLine
{
    screen_char_t *the_line = NULL;

    NSParameterAssert(anIndex >= 0);

    // get the line offset from the specified line
    the_line = aLine + anIndex*REAL_WIDTH;

    // check if we have gone beyond our buffer; if so, we need to wrap around to the top of buffer
    if( the_line >= buffer_lines + REAL_WIDTH*HEIGHT)
    {
        the_line -= REAL_WIDTH * HEIGHT;
        NSAssert(the_line >= buffer_lines && the_line < buffer_lines + REAL_WIDTH*HEIGHT, @"out of range.");
    }

    return (the_line);
}

// returns a line set to default character and attributes
// released when session is closed
- (screen_char_t*)_getDefaultLineWithWidth:(int)width
{
    // check if we have to generate a new line
    if (default_line &&
        default_line_width >= width &&
        ForegroundColorsEqual(default_fg_code, [TERMINAL foregroundColorCodeReal]) &&
        BackgroundColorsEqual(default_bg_code, [TERMINAL backgroundColorCodeReal])) {
        return default_line;
    }

    default_fg_code = [TERMINAL foregroundColorCodeReal];
    default_bg_code = [TERMINAL backgroundColorCodeReal];
    default_line_width = width;

    if (default_line) {
        free(default_line);
    }
    default_line = (screen_char_t*)malloc((width+1)*sizeof(screen_char_t));

    for (int i = 0; i < width; i++) {
        default_line[i].code = 0;
        default_line[i].complexChar = NO;
        CopyForegroundColor(&default_line[i], default_fg_code);
        CopyBackgroundColor(&default_line[i], default_bg_code);
    }

    // Not wrapped by default
    default_line[width].code = EOL_HARD;

    return default_line;
}


// adds a line to scrollback area. Returns YES if oldest line is lost, NO otherwise
- (int)_addLineToScrollback
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif

    int len = WIDTH;
    if (screen_top[WIDTH].code == EOL_HARD) {
        // The line is not continued. Figure out its length by finding the last nonnull char.
        while (len > 0 && (screen_top[len - 1].code == 0)) {
            assert(screen_top[len - 1].code != DWC_SKIP); // Impossible to have a dwc skip here.
            --len;
        }
    }
    if (screen_top[WIDTH].code == EOL_DWC && len == WIDTH) {
        --len;
    }
    [linebuffer appendLine:screen_top length:len partial:(screen_top[WIDTH].code != EOL_HARD) width:WIDTH];
    int dropped = [linebuffer dropExcessLinesWithWidth: WIDTH];
    current_scrollback_lines = [linebuffer numLinesWithWidth: WIDTH];

    NSAssert(dropped == 0 || dropped == 1, @"Unexpected number of lines dropped");

    return dropped;
}

- (void)_setInitialTabStops
{
    [self clearTabStop];
    const int kInitialTabWindow = 1000;
    for (int i = 0; i < kInitialTabWindow; i += TABSIZE) {
        [tabStops addObject:[NSNumber numberWithInt:i]];
    }
}

@end

