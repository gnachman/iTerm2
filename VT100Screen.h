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
#import "VT100Terminal.h"
#import "LineBuffer.h"
#import "DVR.h"
#import "PTYTextView.h"

extern NSString * const kHighlightForegroundColor;
extern NSString * const kHighlightBackgroundColor;

@class iTermGrowlDelegate;
@class PTYSession;
@class PTYTask;
@class VT100Grid;

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
                         BOOL ambiguousIsDoubleWidth,
                         int* cursorIndex);
void TranslateCharacterSet(screen_char_t *s, int len);

@interface VT100Screen : NSObject <PTYTextViewDataSource>
{
    NSMutableSet* tabStops;

    VT100Terminal *TERMINAL;
    PTYTask *SHELL;
    PTYSession *SESSION;
    int charset[4];
    int saveCharset[4];
    BOOL blinkShow;
    BOOL PLAYBELL;
    BOOL SHOWBELL;
    BOOL FLASHBELL;
    BOOL GROWL;
    BOOL blinkingCursor;
    PTYTextView *display;
    VT100Grid *primaryGrid_;
    VT100Grid *altGrid_;  // may be nil
    VT100Grid *currentGrid_;  // Weak reference. Points to either primaryGrid or altGrid.
    
    // Max size of scrollback buffer
    unsigned int max_scrollback_lines;
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
    long long savedFindContextAbsPos_;

    // Used for recording instant replay.
    DVR* dvr;
    BOOL saveToScrollbackInAlternateScreen_;

    BOOL allowTitleReporting_;
	BOOL allDirty_;  // When true, all cells are dirty. Faster than a big memset.
}


- (id)initWithTerminal:(VT100Terminal *)terminal;
- (void)dealloc;

- (NSString *)description;

- (void)setUpScreenWithWidth:(int)width height:(int)height;
- (void)resizeWidth:(int)new_width height:(int)height;
- (void)reset;
- (void)resetPreservingPrompt:(BOOL)preservePrompt;
- (void)resetCharset;
- (BOOL)usingDefaultCharset;
- (void)setScrollback:(unsigned int)lines;
- (void)setUnlimitedScrollback:(BOOL)enable;
- (void)setTerminal:(VT100Terminal *)terminal;
- (void)setShellTask:(PTYTask *)shell;
- (void)setSession:(PTYSession *)session;
- (BOOL)vsplitMode;
- (void)setVsplitMode:(BOOL)mode;

- (PTYTextView *)display;
- (void)setDisplay:(PTYTextView *)aDisplay;

- (BOOL)blinkingCursor;
- (void)setBlinkingCursor:(BOOL)flag;
- (void)processXtermPaste64:(NSString*)commandString;
- (void)showCursor:(BOOL)show;
- (void)setPlayBellFlag:(BOOL)flag;
- (void)setShowBellFlag:(BOOL)flag;
- (void)setFlashBellFlag:(BOOL)flag;
- (void)setGrowlFlag:(BOOL)flag;
- (void)setSaveToScrollbackInAlternateScreen:(BOOL)flag;
- (BOOL)growl;

// edit screen buffer
- (void)putToken:(VT100TCC)token;
- (void)clearBuffer;
- (void)clearScrollbackBuffer;
- (void)showPrimaryBuffer;
- (void)showAltBuffer;

- (void)setSendModifiers:(int *)modifiers
               numValues:(int)numValues;

- (void)mouseModeDidChange:(MouseMode)mouseMode;

// internal
- (void)setString:(NSString *)s ascii:(BOOL)ascii;
- (void)crlf; // -crlf is called only by tmux integration, so it ignores vsplit mode.
- (void)linefeed;
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
- (void)cursorToX:(int)x;
- (void)cursorToY:(int)y;
- (void)cursorToX:(int)x Y:(int)y;
- (void)carriageReturn;
- (void)saveCursorPosition;
- (void)restoreCursorPosition;
- (void)setTopBottom:(VT100TCC)token;
- (void)activateBell;
- (void)deviceReport:(VT100TCC)token withQuestion:(BOOL)question;
- (void)deviceAttribute:(VT100TCC)token;
- (void)secondaryDeviceAttribute:(VT100TCC)token;
- (void)deleteLines:(int)n;
- (void)blink;

- (void)setHistory:(NSArray *)history;
- (void)setAltScreen:(NSArray *)lines;
- (void)setTmuxState:(NSDictionary *)state;

// Set the char at x,y dirty.
- (void)setCharDirtyAtX:(int)x Y:(int)y;

// Check if any flag is set at an x,y coordinate in the dirty array
- (BOOL)isDirtyAtX:(int)x Y:(int)y;

- (void)resetDirty;
- (void)markAsNeedingCompleteRedraw;

// print to ansi...
- (BOOL)printToAnsi;
- (void)setPrintToAnsi:(BOOL)aFlag;
- (void)printStringToAnsi:(NSString *)aString;

// UI stuff
- (void)doPrint;

// Is this character double width on this screen?
- (BOOL)isDoubleWidthCharacter:(unichar)c;

// Set the colors in the prototype char to all text on screen that matches the regex.
// See kHighlightXxxColor constants at the top of this file for dict keys, values are NSColor*s.
- (void)highlightTextMatchingRegex:(NSString *)regex
                            colors:(NSDictionary *)colors;

// Turn off DVR for this screen.
- (void)disableDvr;

// Accessor.
- (DVR*)dvr;

// Load a frame from a dvr decoder.
- (void)setFromFrame:(screen_char_t*)s len:(int)len info:(DVRFrameInfo)info;

// Save the position of the end of the scrollback buffer without the screen appeneded.
- (void)saveTerminalAbsPos;

// Restore the saved position into a passed-in find context (see saveFindContextAbsPos and saveTerminalAbsPos).
- (void)restoreSavedPositionToFindContext:(FindContext *)context;

// Set whether title reporting is allowed. Defaults to no.
- (void)setAllowTitleReporting:(BOOL)allow;

@end

