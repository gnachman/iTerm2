/*
 **  PTYSession.h
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: Implements the model class for a terminal session.
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

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <iTerm/BookmarkModel.h>
#import "DVR.h"
#import "WindowControllerInterface.h"
#import "TextViewWrapper.h"

#include <sys/time.h>

#define NSLeftAlternateKeyMask  (0x000020 | NSAlternateKeyMask)
#define NSRightAlternateKeyMask (0x000040 | NSAlternateKeyMask)

@class PTYTask;
@class PTYTextView;
@class PTYScrollView;
@class VT100Screen;
@class VT100Terminal;
@class PreferencePanel;
@class iTermController;
@class iTermGrowlDelegate;
@class FakeWindow;
@class PseudoTerminal;

// Timer period when all we have to do is update blinking text/cursor.
static const float kBlinkTimerIntervalSec = 1.0 / 2.0;
// Timer period when receiving lots of data.
static const float kSlowTimerIntervalSec = 1.0 / 10.0;
// Timer period for interactive use.
static const float kFastTimerIntervalSec = 1.0 / 30.0;
// Timer period for background sessions. This changes the tab item's color
// so it must run often enough for that to be useful.
// TODO(georgen): There's room for improvement here.
static const float kBackgroundSessionIntervalSec = 1;

@class PTYTab;
@class SessionView;
@interface PTYSession : NSResponder
{
    // Owning tab.
    PTYTab* tab_;

    // tty device
    NSString* tty;

    // name can be changed by the host.
    NSString* name;

    // defaultName cannot be changed by the host.
    NSString* defaultName;

    // The window title that should be used when this session is current. Otherwise defaultName
    // should be used.
    NSString* windowTitle;

    // Shell wraps the underlying file descriptor pair.
    PTYTask* SHELL;

    // Terminal processes vt100 codes.
    VT100Terminal* TERMINAL;

    // The value of the $TERM environment var.
    NSString* TERM_VALUE;

    // The value of the $COLORFGBG environment var.
    NSString* COLORFGBG_VALUE;

    // The current screen contents.
    VT100Screen* SCREEN;

    // Has the underlying connection been closed?
    BOOL EXIT;

    // The view in which this session's objects live.
    SessionView* view;

    // The scrollview in which this session's contents are displayed.
    PTYScrollView* SCROLLVIEW;

    // A view that wraps the textview. It is the scrollview's document. This exists to provide a
    // top margin above the textview.
    TextViewWrapper* WRAPPER;

    // The view that contains all the visible text in this session.
    PTYTextView* TEXTVIEW;

    // This timer fires periodically to redraw TEXTVIEW, update the scroll position, tab appearance,
    // etc.
    NSTimer *updateTimer;

    // Anti-idle timer that sends a character every so often to the host.
    NSTimer* antiIdleTimer;

    // The code to send in the anti idle timer.
    char ai_code;

    // If true, close the tab when the session ends.
    BOOL autoClose;

    // True if ambiguous-width characters are double-width.
    BOOL doubleWidth;

    // True if mouse movements are sent to the host.
    BOOL xtermMouseReporting;

    // This is not used as far as I can tell.
    int bell;

    // Filename of background image.
    NSString* backgroundImagePath;

    // Bookmark currently in use.
    NSDictionary* addressBookEntry;

    // The bookmark the session was originally created with so those settings can be restored if
    // needed.
    Bookmark* originalAddressBookEntry;

    // Growl stuff
    iTermGrowlDelegate* gd;

    // Status reporting
    struct timeval lastInput, lastOutput;

    // Time that the tab label was last updated.
    struct timeval lastUpdate;

    // Does the session have new output? Used by -[PTYTab setLabelAttributes] to color the tab's title
    // appropriately.
    BOOL newOutput;

    // Is the session idle? Used by setLableAttribute to send a growl message when processing ends.
    BOOL growlIdle;

    // Is there new output for the purposes of growl notifications? They run on a different schedule
    // than tab colors.
    BOOL growlNewOutput;

    // Has this session's bookmark been divorced from the bookmark in the BookmarkModel? Changes
    // in this bookmark may happen indepentendly of the persistent bookmark.
    bool isDivorced;

    // A digital video recorder for this session that implements the instant replay feature. These
    // are non-null while showing instant replay.
    DVR* dvr_;
    DVRDecoder* dvrDecoder_;

    // Set only if this is not a live session (we are showing instant replay). Is a pointer to the
    // hidden live session while looking at the past.
    PTYSession* liveSession_;

    // Is the update timer's callback currently running?
    BOOL timerRunning_;

    // Paste from the head of this string from a timer until it's empty.
    NSMutableString* slowPasteBuffer;
    NSTimer* slowPasteTimer;

    // The name of the foreground job at the moment as best we can tell.
    NSString* jobName_;
}

// init/dealloc
- (id)init;
- (void)dealloc;

// accessor
- (DVR*)dvr;

// accessor
- (DVRDecoder*)dvrDecoder;

// Jump to a particular point in time.
- (long long)irSeekToAtLeast:(long long)timestamp;

// accessor. nil if this session is live.
- (PTYSession*)liveSession;

// test if we're at the beginning/end of time.
- (BOOL)canInstantReplayPrev;
- (BOOL)canInstantReplayNext;

// Disable all timers.
- (void)cancelTimers;

// Begin showing DVR frames from some live session.
- (void)setDvr:(DVR*)dvr liveSession:(PTYSession*)liveSession;

// Go forward/back in time. Must call setDvr:liveSession: first.
- (void)irAdvance:(int)dir;

// Session specific methods
- (BOOL)setScreenSize:(NSRect)aRect parent:(id<WindowControllerInterface>)parent;

- (void)startProgram:(NSString *)program
           arguments:(NSArray *)prog_argv
         environment:(NSDictionary *)prog_env
              isUTF8:(BOOL)isUTF8;
- (void)terminate;

- (void)setNewOutput:(BOOL)value;
- (BOOL)newOutput;

// Preferences
- (void)setPreferencesFromAddressBookEntry: (NSDictionary *)aePrefs;

// PTYTask
- (void)writeTask:(NSData*)data;
- (void)readTask:(NSData*)data;
- (void)brokenPipe;

// PTYTextView
- (BOOL)hasKeyMappingForEvent: (NSEvent *)event highPriority: (BOOL)priority;
- (void)keyDown:(NSEvent *)event;
- (BOOL)willHandleEvent: (NSEvent *)theEvent;
- (void)handleEvent: (NSEvent *)theEvent;
- (void)insertText:(NSString *)string;
- (void)insertNewline:(id)sender;
- (void)insertTab:(id)sender;
- (void)moveUp:(id)sender;
- (void)moveDown:(id)sender;
- (void)moveLeft:(id)sender;
- (void)moveRight:(id)sender;
- (void)pageUp:(id)sender;
- (void)pageDown:(id)sender;
- (void)paste:(id)sender;
- (void)pasteString: (NSString *)aString;
- (void)pasteSlowly:(id)sender;
- (void)deleteBackward:(id)sender;
- (void)deleteForward:(id)sender;
- (void)textViewDidChangeSelection: (NSNotification *)aNotification;
- (void)textViewResized: (NSNotification *)aNotification;
- (void)tabViewWillRedraw: (NSNotification *)aNotification;


// misc
- (void)setWidth:(int)width height:(int)height;


// Contextual menu
- (void)menuForEvent:(NSEvent *)theEvent menu: (NSMenu *)theMenu;


// get/set methods
- (PTYTab*)tab;
- (void)setTab:(PTYTab*)tab;
- (struct timeval)lastOutput;
- (void)setGrowlIdle:(BOOL)value;
- (BOOL)growlIdle;
- (void)setGrowlNewOutput:(BOOL)value;
- (BOOL)growlNewOutput;

- (NSString *)name;
- (void)setName: (NSString *)theName;
- (NSString *)defaultName;
- (NSString*)joblessDefaultName;
- (void)setDefaultName: (NSString *)theName;
- (NSString *)uniqueID;
- (void)setUniqueID: (NSString *)uniqueID;
- (NSString *)windowTitle;
- (void)setWindowTitle: (NSString *)theTitle;
- (PTYTask *)SHELL;
- (void)setSHELL: (PTYTask *)theSHELL;
- (VT100Terminal *)TERMINAL;
- (void)setTERMINAL: (VT100Terminal *)theTERMINAL;
- (NSString *)TERM_VALUE;
- (void)setTERM_VALUE: (NSString *)theTERM_VALUE;
- (NSString *)COLORFGBG_VALUE;
- (void)setCOLORFGBG_VALUE: (NSString *)theCOLORFGBG_VALUE;
- (VT100Screen *)SCREEN;
- (void)setSCREEN: (VT100Screen *)theSCREEN;
- (NSImage *)image;
- (SessionView *)view;
- (void)setView:(SessionView*)newView;
- (PTYTextView *)TEXTVIEW;
- (void)setTEXTVIEW: (PTYTextView *)theTEXTVIEW;
- (PTYScrollView *)SCROLLVIEW;
- (void)setSCROLLVIEW: (PTYScrollView *)theSCROLLVIEW;
- (NSStringEncoding)encoding;
- (void)setEncoding:(NSStringEncoding)encoding;
- (BOOL)antiIdle;
- (int)antiCode;
- (void)setAntiIdle:(BOOL)set;
- (void)setAntiCode:(int)code;
- (BOOL)autoClose;
- (void)setAutoClose:(BOOL)set;
- (BOOL)doubleWidth;
- (void)setDoubleWidth:(BOOL)set;
- (BOOL)xtermMouseReporting;
- (void)setXtermMouseReporting:(BOOL)set;
- (NSDictionary *)addressBookEntry;

// Return the address book that the session was originally created with.
- (Bookmark *)originalAddressBookEntry;
- (void)setAddressBookEntry:(NSDictionary*)entry;
- (NSString *)tty;
- (NSString *)contents;
- (iTermGrowlDelegate*)growlDelegate;


- (void)clearBuffer;
- (void)clearScrollbackBuffer;
- (BOOL)logging;
- (void)logStart;
- (void)logStop;
- (NSString *)backgroundImagePath;
- (void)setBackgroundImagePath: (NSString *)imageFilePath;
- (NSColor *)foregroundColor;
- (void)setForegroundColor:(NSColor*)color;
- (NSColor *)backgroundColor;
- (void)setBackgroundColor:(NSColor*)color;
- (NSColor *)selectionColor;
- (void)setSelectionColor: (NSColor *)color;
- (NSColor *)boldColor;
- (void)setBoldColor:(NSColor*)color;
- (NSColor *)cursorColor;
- (void)setCursorColor:(NSColor*)color;
- (NSColor *)selectedTextColor;
- (void)setSelectedTextColor: (NSColor *)aColor;
- (NSColor *)cursorTextColor;
- (void)setCursorTextColor: (NSColor *)aColor;
- (float)transparency;
- (void)setTransparency:(float)transparency;
- (BOOL)useBoldFont;
- (void)setUseBoldFont:(BOOL)boldFlag;
- (void)setColorTable:(int)index color:(NSColor *)c;
- (int)optionKey;
- (int)rightOptionKey;

// Session status

- (BOOL)exited;
- (BOOL)bell;
- (void)setBell: (BOOL)flag;

- (void)sendCommand: (NSString *)command;

// Display timer stuff
- (void)updateDisplay;
- (void)doAntiIdle;
- (NSString*)ansiColorsMatchingForeground:(NSDictionary*)fg andBackground:(NSDictionary*)bg inBookmark:(Bookmark*)aDict;
- (void)updateScroll;

- (int)columns;
- (int)rows;
- (void)changeFontSizeDirection:(int)dir;
- (void)setFont:(NSFont*)font nafont:(NSFont*)nafont horizontalSpacing:(float)horizontalSpacing verticalSpacing:(float)verticalSpacing;

// Assigns a new GUID to the session so that changes to the bookmark will not
// affect it. Returns the GUID of a divorced bookmark. Does nothing if already
// divorced, but still returns the divorced GUID.
- (NSString*)divorceAddressBookEntryFromPreferences;

// Schedule the screen update timer to run in a specified number of seconds.
- (void)scheduleUpdateIn:(NSTimeInterval)timeout;

- (NSString*)jobName;

@end

@interface PTYSession (ScriptingSupport)

// Object specifier
- (NSScriptObjectSpecifier *)objectSpecifier;
-(void)handleExecScriptCommand: (NSScriptCommand *)aCommand;
-(void)handleTerminateScriptCommand: (NSScriptCommand *)command;
-(void)handleSelectScriptCommand: (NSScriptCommand *)command;
-(void)handleWriteScriptCommand: (NSScriptCommand *)command;

@end

@interface PTYSession (Private)

- (NSString*)_getLocale;
- (void)setDvrFrame;

@end
