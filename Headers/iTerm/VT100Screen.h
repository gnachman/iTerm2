// -*- mode:objc -*-
// $Id: VT100Screen.h,v 1.38 2008-09-30 06:21:12 yfabian Exp $
/*
 **  VT100Screen.h
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

#import <Cocoa/Cocoa.h>
#import <iTerm/VT100Terminal.h>
#import <LineBuffer.h>
#import "DVR.h"

@class PTYTask;
@class PTYSession;
@class PTYTextView;
@class iTermGrowlDelegate;

// continueFindAllResults populates an array of search results with these
// objects.
@interface SearchResult : NSObject
{
@public
    int startX, endX;
    long long absStartY, absEndY;
}

@end

// For debugging: log the buffer.
void DumpBuf(screen_char_t* p, int n);

// Convert a string into screen_char_t. This deals with padding out double-
// width characters, joining combining marks, and skipping zero-width spaces.
//
// The buffer size must be at least twice the length of the string (worst case:
//   every character is double-width).
// Pass prototype foreground and background colors in fg and bg.
// *len is filled in with the number of elements of *buf that were set.
// encoding is currently ignored and it's assumed to be UTF-16.
// A good choice for ambiguousIsDoubleWidth is [SESSION doubleWidth].
// If not null, *cursorIndex gives an index into s and is changed into the
//   corresponding index into buf.
void StringToScreenChars(NSString *s,
                         screen_char_t *buf,
                         screen_char_t fg,
                         screen_char_t bg,
                         int *len,
                         NSStringEncoding encoding,
                         BOOL ambiguousIsDoubleWidth,
                         int* cursorIndex);

@interface VT100Screen : NSObject
{
    int WIDTH; // width of screen
    int HEIGHT; // height of screen
    int cursorX;
    int cursorY;
    int SAVE_CURSOR_X;
    int SAVE_CURSOR_Y;
    int ALT_SAVE_CURSOR_X;
    int ALT_SAVE_CURSOR_Y;
    int SCROLL_TOP;
    int SCROLL_BOTTOM;
    NSMutableSet* tabStops;

    VT100Terminal *TERMINAL;
    PTYTask *SHELL;
    PTYSession *SESSION;
    int charset[4], saveCharset[4];
    BOOL blinkShow;
    BOOL PLAYBELL;
    BOOL SHOWBELL;
    BOOL FLASHBELL;
    BOOL GROWL;


    BOOL blinkingCursor;
    PTYTextView *display;

    // A circular buffer exactly (WIDTH+1) * HEIGHT elements in size. This contains
    // only the contents of the screen. The scrollback buffer is stored in linebuffer.
    screen_char_t *buffer_lines;

    // The position in buffer_lines of the first line in the screen. The logical lines
    // wrap around the circular buffer.
    screen_char_t *screen_top;

    // buffer holding flags for each char on whether it needs to be redrawn
    char *dirty;
    // Number of bytes in the dirty array.
    int dirtySize;

    // a single default line
    screen_char_t *default_line;
    screen_char_t *result_line;

    // temporary buffer to store main buffer in SAVE_BUFFER/RESET_BUFFER mode
    screen_char_t *temp_buffer;

    // default line stuff
    screen_char_t default_bg_code;
    screen_char_t default_fg_code;
    int default_line_width;

    // Max size of scrollback buffer
    unsigned int  max_scrollback_lines;
    // This flag overrides max_scrollback_lines:
    BOOL unlimitedScrollback_;

    // how many scrollback lines have been lost due to overflow
    int scrollback_overflow;
    long long cumulative_scrollback_overflow;

    // print to ansi...
    BOOL printToAnsi;        // YES=ON, NO=OFF, default=NO;
    NSMutableString *printToAnsiString;

    // Growl stuff
    iTermGrowlDelegate* gd;

    // Scrollback buffer
    LineBuffer* linebuffer;
    FindContext findContext;

    // Used for recording instant replay.
    DVR* dvr;
}


- (id)init;
- (void)dealloc;

- (NSString *)description;

- (screen_char_t*)initScreenWithWidth:(int)width Height:(int)height;
- (void)resizeWidth:(int)new_width height:(int)height;
- (void)reset;
- (void)setWidth:(int)width height:(int)height;
- (int)width;
- (int)height;
- (void)setScrollback:(unsigned int)lines;
- (void)setUnlimitedScrollback:(BOOL)enable;
- (void)setTerminal:(VT100Terminal *)terminal;
- (VT100Terminal *)terminal;
- (void)setShellTask:(PTYTask *)shell;
- (PTYTask *)shellTask;
- (PTYSession *) session;
- (void)setSession:(PTYSession *)session;

- (PTYTextView *) display;
- (void) setDisplay: (PTYTextView *) aDisplay;

- (BOOL) blinkingCursor;
- (void) setBlinkingCursor: (BOOL) flag;
- (void)showCursor:(BOOL)show;
- (void)setPlayBellFlag:(BOOL)flag;
- (void)setShowBellFlag:(BOOL)flag;
- (void)setFlashBellFlag:(BOOL)flag;
- (void)setGrowlFlag:(BOOL)flag;
- (BOOL)growl;

// line access
// This function is dangerous! It writes to an internal buffer and returns a
// pointer to it. Better to use getLineAtIndex:withBuffer:.
- (screen_char_t *) getLineAtIndex: (int) theIndex;

// Provide a buffer as large as sizeof(screen_char_t*) * ([SCREEN width] + 1)
- (screen_char_t *)getLineAtIndex:(int)theIndex withBuffer:(screen_char_t*)buffer;
- (screen_char_t *)getLineAtScreenIndex:(int)theIndex;
- (NSString *)getLineString:(screen_char_t *)theLine;

// edit screen buffer
- (void)putToken:(VT100TCC)token;
- (void)clearBuffer;
- (long long)absoluteLineNumberOfCursor;
- (void)clearScrollbackBuffer;
- (void)saveBuffer;
- (void)restoreBuffer;

// internal
- (void)setString:(NSString *)s ascii:(BOOL)ascii;
- (void)setStringToX:(int)x
                   Y:(int)y
              string:(NSString *)string
               ascii:(BOOL)ascii;
- (void)addLineToScrollback;
- (void)setNewLine;
- (void)deleteCharacters:(int)n;
- (void)backSpace;
- (void)backTab;
- (void)setTab;
- (void)clearTabStop;
- (BOOL)haveTabStopAt:(int)x;
- (void)setTabStopAt:(int)x;
- (void)removeTabStopAt:(int)x;
- (void)clearScreen;
- (void)eraseInDisplay:(VT100TCC)token;
- (void)eraseInLine:(VT100TCC)token;
- (void)selectGraphicRendition:(VT100TCC)token;
- (void)cursorLeft:(int)n;
- (void)cursorRight:(int)n;
- (void)cursorUp:(int)n;
- (void)cursorDown:(int)n;
- (void)cursorToX: (int) x;
- (void)cursorToX:(int)x Y:(int)y;
- (void)saveCursorPosition;
- (void)restoreCursorPosition;
- (void)setTopBottom:(VT100TCC)token;
- (void)scrollUp;
- (void)scrollDown;
- (void)activateBell;
- (void)deviceReport:(VT100TCC)token;
- (void)deviceAttribute:(VT100TCC)token;
- (void)insertBlank: (int)n;
- (void)insertLines: (int)n;
- (void)deleteLines: (int)n;
- (void)blink;
- (int)cursorX;
- (int)cursorY;

- (int)numberOfLines;
- (int)numberOfScrollbackLines;

- (int)scrollbackOverflow;
- (long long)totalScrollbackOverflow;
- (void)resetScrollbackOverflow;
- (void)scrollScreenIntoScrollbackBuffer:(int)leaving;

// Set a range of bytes to dirty=1
- (void)setRangeDirty:(NSRange)range;

// OR in a value into the dirty array at an x,y coordinate
- (void)setCharDirtyAtX:(int)x Y:(int)y value:(int)v;

// Retrieve the dirty flags at an x,y coordinate
- (int)dirtyAtX:(int)x Y:(int)y;

// Check if any flag is set at an x,y coordinate in the dirty array
- (BOOL)isDirtyAtX:(int)x Y:(int)y;

- (void)resetDirty;
- (void)setDirty;

// print to ansi...
- (BOOL) printToAnsi;
- (void) setPrintToAnsi: (BOOL) aFlag;
- (void) printStringToAnsi: (NSString *) aString;

// UI stuff
- (void) doPrint;

// Is this character double width on this screen?
- (BOOL)isDoubleWidthCharacter:(unichar)c;

// Initialize the find context.
- (FindContext*)findContext;
- (void)initFindString:(NSString*)aString
      forwardDirection:(BOOL)direction
          ignoringCase:(BOOL)ignoreCase
                 regex:(BOOL)regex
           startingAtX:(int)x
           startingAtY:(int)y
            withOffset:(int)offsetof
             inContext:(FindContext*)context
       multipleResults:(BOOL)multipleResults;

- (BOOL)continueFindResultAtStartX:(int*)startX
                          atStartY:(int*)startY
                            atEndX:(int*)endX
                            atEndY:(int*)endY
                             found:(BOOL*)found
                         inContext:(FindContext*)context;

// Find all matches to to the search in the provided context. Returns YES if it
// should be called again.
- (BOOL)continueFindAllResults:(NSMutableArray*)results
                     inContext:(FindContext*)context;
- (void)cancelFindInContext:(FindContext*)context;

- (void) dumpDebugLog;

// Return a human-readable dump of the screen contents.
- (NSString*)debugString;

// Save the current state to a new frame in the dvr.
- (void)saveToDvr;

// Turn off DVR for this screen.
- (void)disableDvr;

// Accessor.
- (DVR*)dvr;

// Load a frame from a dvr decoder.
- (void)setFromFrame:(screen_char_t*)s len:(int)len info:(DVRFrameInfo)info;

@end

