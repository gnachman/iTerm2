/*
 **  PTYSession.m
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

#import <iTerm/iTerm.h>
#import <iTerm/PTYSession.h>
#import <iTerm/PTYTask.h>
#import <iTerm/PTYTextView.h>
#import <iTerm/PTYScrollView.h>;
#import <iTerm/VT100Screen.h>
#import <iTerm/VT100Terminal.h>
#import <iTerm/PreferencePanel.h>
#import <WindowControllerInterface.h>
#import <iTerm/iTermController.h>
#import <iTerm/PseudoTerminal.h>
#import <FakeWindow.h>
#import <iTerm/NSStringITerm.h>
#import <iTerm/iTermKeyBindingMgr.h>
#import <iTerm/ITAddressBookMgr.h>
#import <iTerm/iTermGrowlDelegate.h>
#import "iTermApplicationDelegate.h"
#import "SessionView.h"
#import "PTYTab.h"

#include <unistd.h>
#include <sys/wait.h>
#include <sys/time.h>

#define DEBUG_ALLOC           0
#define DEBUG_METHOD_TRACE    0
#define DEBUG_KEYDOWNDUMP     0

@implementation PTYSession

static NSString *TERM_ENVNAME = @"TERM";
static NSString *COLORFGBG_ENVNAME = @"COLORFGBG";
static NSString *PWD_ENVNAME = @"PWD";
static NSString *PWD_ENVVALUE = @"~";

// Constants for saved window arrangement keys.
static NSString* SESSION_ARRANGEMENT_COLUMNS = @"Columns";
static NSString* SESSION_ARRANGEMENT_ROWS = @"Rows";
static NSString* SESSION_ARRANGEMENT_BOOKMARK = @"Bookmark";
static NSString* SESSION_ARRANGEMENT_WORKING_DIRECTORY = @"Working Directory";

// init/dealloc
- (id)init
{
    if ((self = [super init]) == nil) {
        return (nil);
    }

    isDivorced = NO;
    gettimeofday(&lastInput, NULL);
    lastOutput = lastInput;
    lastUpdate = lastInput;
    EXIT=NO;
    savedScrollPosition_ = -1;
    updateTimer = nil;
    antiIdleTimer = nil;
    addressBookEntry=nil;

#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif

    // Allocate screen, shell, and terminal objects
    SHELL = [[PTYTask alloc] init];
    TERMINAL = [[VT100Terminal alloc] init];
    SCREEN = [[VT100Screen alloc] init];
    NSParameterAssert(SHELL != nil && TERMINAL != nil && SCREEN != nil);

    // Need Growl plist stuff
    gd = [iTermGrowlDelegate sharedInstance];
    growlIdle = growlNewOutput = NO;

    slowPasteBuffer = [[NSMutableString alloc] init];

    return self;
}

- (void)dealloc
{
    [slowPasteBuffer release];
    if (slowPasteTimer) {
        [slowPasteTimer invalidate];
    }
    [lastActiveAt_ release];
    [bookmarkName release];
    [TERM_VALUE release];
    [COLORFGBG_VALUE release];
    [name release];
    [windowTitle release];
    [addressBookEntry release];
    [backgroundImagePath release];
    [antiIdleTimer invalidate];
    [antiIdleTimer release];
    [updateTimer invalidate];
    [updateTimer release];
    [originalAddressBookEntry release];
    [liveSession_ release];

    [SHELL release];
    SHELL = nil;
    [SCREEN release];
    SCREEN = nil;
    [TERMINAL release];
    TERMINAL = nil;

    [[NSNotificationCenter defaultCenter] removeObserver: self];

    if (dvrDecoder_) {
        [dvr_ releaseDecoder:dvrDecoder_];
        [dvr_ release];
    }

    [super dealloc];
#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x, done", __PRETTY_FUNCTION__, self);
#endif
}

- (void)cancelTimers
{
    [view cancelTimers];
    [updateTimer invalidate];
    [antiIdleTimer invalidate];
}

- (void)setDvr:(DVR*)dvr liveSession:(PTYSession*)liveSession
{
    assert(liveSession != self);

    liveSession_ = liveSession;
    [liveSession_ retain];
    [SCREEN disableDvr];
    dvr_ = dvr;
    [dvr_ retain];
    dvrDecoder_ = [dvr getDecoder];
    long long t = [dvr_ lastTimeStamp];
    if (t) {
        [dvrDecoder_ seek:t];
        [self setDvrFrame];
    }
}

- (void)irAdvance:(int)dir
{
    if (!dvr_) {
        if (dir < 0) {
            [[[self tab] realParentWindow] replaySession:self];
            PTYSession* irSession = [[[self tab] realParentWindow] currentSession];
             if (irSession != self) {
                 // Failed to enter replay mode (perhaps nothing to replay?)
                [irSession irAdvance:dir];
             }
            return;
        } else {
            NSBeep();
            return;
        }

    }
    if (dir > 0) {
        if (![dvrDecoder_ next] || [dvrDecoder_ timestamp] == [dvr_ lastTimeStamp]) {
            // Switch to the live view
            [[[self tab] realParentWindow] showLiveSession:liveSession_ inPlaceOf:self];
            return;
        }
    } else {
        if (![dvrDecoder_ prev]) {
            NSBeep();
        }
    }
    [self setDvrFrame];
}

- (long long)irSeekToAtLeast:(long long)timestamp
{
    assert(dvr_);
    if (![dvrDecoder_ seek:timestamp]) {
        [dvrDecoder_ seek:[dvr_ firstTimeStamp]];
    }
    [self setDvrFrame];
    return [dvrDecoder_ timestamp];
}

- (DVR*)dvr
{
    return dvr_;
}

- (DVRDecoder*)dvrDecoder
{
    return dvrDecoder_;
}

- (PTYSession*)liveSession
{
    return liveSession_;
}

+ (PTYSession*)sessionFromArrangement:(NSDictionary*)arrangement inView:(SessionView*)sessionView inTab:(PTYTab*)theTab
{
    PTYSession* aSession = [[[PTYSession alloc] init] autorelease];
    aSession->view = sessionView;
    [[sessionView findViewController] setDelegate:aSession];
    Bookmark* theBookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:[[arrangement objectForKey:SESSION_ARRANGEMENT_BOOKMARK] objectForKey:KEY_GUID]];
    BOOL needDivorce = NO;
    if (!theBookmark) {
        theBookmark = [arrangement objectForKey:SESSION_ARRANGEMENT_BOOKMARK];
        needDivorce = YES;
    }
    [[aSession SCREEN] setUnlimitedScrollback:[[theBookmark objectForKey:KEY_UNLIMITED_SCROLLBACK] boolValue]];
    [[aSession SCREEN] setScrollback:[[theBookmark objectForKey:KEY_SCROLLBACK_LINES] intValue]];

     // set our preferences
    [aSession setAddressBookEntry:theBookmark];

    [aSession setScreenSize:[sessionView frame] parent:[theTab realParentWindow]];

    [aSession setPreferencesFromAddressBookEntry:theBookmark];
    [[aSession SCREEN] setDisplay:[aSession TEXTVIEW]];
    [aSession runCommandWithOldCwd:[arrangement objectForKey:SESSION_ARRANGEMENT_WORKING_DIRECTORY]];
    [aSession setName:[theBookmark objectForKey:KEY_NAME]];
    if ([[[[theTab realParentWindow] window] title] compare:@"Window"] == NSOrderedSame) {
        [[theTab realParentWindow] setWindowTitle];
    }
    [aSession setTab:theTab];

    if (needDivorce) {
        [aSession divorceAddressBookEntryFromPreferences];
    }

    return aSession;
}

// Session specific methods
- (BOOL)setScreenSize:(NSRect)aRect parent:(id<WindowControllerInterface>)parent
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession setScreenSize:parent:]", __FILE__, __LINE__);
#endif

    [SCREEN setSession:self];

    // Allocate a container to hold the scrollview
    if (!view) {
        view = [[[SessionView alloc] initWithFrame:NSMakeRect(0, 0, aRect.size.width, aRect.size.height)
                                          session:self] autorelease];
        [[view findViewController] setDelegate:self];
    }

    // Allocate a scrollview
    SCROLLVIEW = [[PTYScrollView alloc] initWithFrame: NSMakeRect(0, 0, aRect.size.width, aRect.size.height)];
    [SCROLLVIEW setHasVerticalScroller:(![parent fullScreen] &&
                                        ![[PreferencePanel sharedInstance] hideScrollbar])];
    NSParameterAssert(SCROLLVIEW != nil);
    [SCROLLVIEW setAutoresizingMask: NSViewWidthSizable|NSViewHeightSizable];

    // assign the main view
    [view addSubview:SCROLLVIEW];
    [view setAutoresizesSubviews:YES];
    // TODO(georgen): I disabled setCopiesOnScroll because there is a vertical margin in the PTYTextView and
    // we would not want that copied. This is obviously bad for performance when scrolling, but it's unclear
    // whether the difference will ever be noticable. I believe it could be worked around (painfully) by
    // subclassing NSClipView and overriding viewBoundsChanged: and viewFrameChanged: so that it coipes on
    // scroll but it doesn't include the vertical marigns when doing so.
    // The vertical margins are indespensable because different PTYTextViews may use different fonts/font
    // sizes, but the window size does not change as you move from tab to tab. If the margin is outside the
    // NSScrollView's contentView it looks funny.
    [[SCROLLVIEW contentView] setCopiesOnScroll:NO];

    // Allocate a text view
    NSSize aSize = [SCROLLVIEW contentSize];
    WRAPPER = [[TextViewWrapper alloc] initWithFrame:NSMakeRect(0, 0, aSize.width, aSize.height)];
    [WRAPPER setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    TEXTVIEW = [[PTYTextView alloc] initWithFrame: NSMakeRect(0, VMARGIN, aSize.width, aSize.height)];
    [TEXTVIEW setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [TEXTVIEW setFont:[ITAddressBookMgr fontWithDesc:[addressBookEntry objectForKey:KEY_NORMAL_FONT]]
               nafont:[ITAddressBookMgr fontWithDesc:[addressBookEntry objectForKey:KEY_NON_ASCII_FONT]]
    horizontalSpacing:[[addressBookEntry objectForKey:KEY_HORIZONTAL_SPACING] floatValue]
      verticalSpacing:[[addressBookEntry objectForKey:KEY_VERTICAL_SPACING] floatValue]];
    [self setTransparency:[[addressBookEntry objectForKey:KEY_TRANSPARENCY] floatValue]];

    [WRAPPER addSubview:TEXTVIEW];
    [TEXTVIEW setFrame:NSMakeRect(0, VMARGIN, aSize.width, aSize.height - VMARGIN)];
    [TEXTVIEW release];

    // assign terminal and task objects
    [SCREEN setShellTask:SHELL];
    [SCREEN setTerminal:TERMINAL];
    [TERMINAL setScreen: SCREEN];
    [SHELL setDelegate:self];

    // initialize the screen
    int width = (aSize.width - MARGIN*2) / [TEXTVIEW charWidth];
    int height = (aSize.height - VMARGIN*2) / [TEXTVIEW lineHeight];
    if ([SCREEN initScreenWithWidth:width Height:height]) {
        [self setName:@"Shell"];
        [self setDefaultName:@"Shell"];

        [TEXTVIEW setDataSource: SCREEN];
        [TEXTVIEW setDelegate: self];
        [SCROLLVIEW setDocumentView:WRAPPER];
        [WRAPPER release];
        [SCROLLVIEW setDocumentCursor: [PTYTextView textViewCursor]];
        [SCROLLVIEW setLineScroll:[TEXTVIEW lineHeight]];
        [SCROLLVIEW setPageScroll:2*[TEXTVIEW lineHeight]];
        [SCROLLVIEW setHasVerticalScroller:(![parent fullScreen] &&
                                            ![[PreferencePanel sharedInstance] hideScrollbar])];

        ai_code=0;
        [antiIdleTimer release];
        antiIdleTimer = nil;
        newOutput = NO;

        return YES;
    } else {
        [SCREEN release];
        SCREEN = nil;
        [TEXTVIEW release];
        NSRunCriticalAlertPanel(NSLocalizedStringFromTableInBundle(@"Out of memory",@"iTerm", [NSBundle bundleForClass: [self class]], @"Error"),
                         NSLocalizedStringFromTableInBundle(@"New sesssion cannot be created. Try smaller buffer sizes.",@"iTerm", [NSBundle bundleForClass: [self class]], @"Error"),
                         NSLocalizedStringFromTableInBundle(@"OK",@"iTerm", [NSBundle bundleForClass: [self class]], @"OK"),
                         nil, nil);

        return NO;
    }
}

- (void)runCommandWithOldCwd:(NSString*)oldCWD
{
    NSMutableString *cmd;
    NSArray *arg;
    NSString *pwd;
    BOOL isUTF8;

    // Grab the addressbook command
    Bookmark* addressbookEntry = [self addressBookEntry];
    BOOL loginSession;
    cmd = [[[NSMutableString alloc] initWithString:[ITAddressBookMgr bookmarkCommand:addressbookEntry isLoginSession:&loginSession]] autorelease];
    NSMutableString* theName = [[[NSMutableString alloc] initWithString:[addressbookEntry objectForKey:KEY_NAME]] autorelease];
    // Get session parameters
    [[[self tab] realParentWindow] getSessionParameters:cmd withName:theName];

    [PseudoTerminal breakDown:cmd cmdPath:&cmd cmdArgs:&arg];

    pwd = [ITAddressBookMgr bookmarkWorkingDirectory:addressbookEntry];
    if ([pwd length] == 0) {
        if (oldCWD) {
            pwd = oldCWD;
        } else {
            pwd = NSHomeDirectory();
        }
    }
    NSDictionary *env = [NSDictionary dictionaryWithObject: pwd forKey:@"PWD"];
    isUTF8 = ([[addressbookEntry objectForKey:KEY_CHARACTER_ENCODING] unsignedIntValue] == NSUTF8StringEncoding);

    [[[self tab] realParentWindow] setName:theName forSession:self];

    // Start the command
    [self startProgram:cmd arguments:arg environment:env isUTF8:isUTF8 asLoginSession:loginSession];
}

- (void)setWidth:(int)width height:(int)height
{
    [SCREEN resizeWidth:width height:height];
    [SHELL setWidth:width height:height];
    [TEXTVIEW clearHighlights];
}

- (void)setNewOutput:(BOOL)value
{
    newOutput = value;
}

- (BOOL)newOutput
{
    return newOutput;
}

- (void)startProgram:(NSString *)program
           arguments:(NSArray *)prog_argv
         environment:(NSDictionary *)prog_env
              isUTF8:(BOOL)isUTF8
      asLoginSession:(BOOL)asLoginSession
{
    NSString *path = program;
    NSMutableArray *argv = [NSMutableArray arrayWithArray:prog_argv];
    NSMutableDictionary *env = [NSMutableDictionary dictionaryWithDictionary:prog_env];


#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession startProgram:%@ arguments:%@ environment:%@]",
          __FILE__, __LINE__, program, prog_argv, prog_env );
#endif
    if ([env objectForKey:TERM_ENVNAME] == nil)
        [env setObject:TERM_VALUE forKey:TERM_ENVNAME];

    if ([env objectForKey:COLORFGBG_ENVNAME] == nil && COLORFGBG_VALUE != nil)
        [env setObject:COLORFGBG_VALUE forKey:COLORFGBG_ENVNAME];

    NSString* lang = [self _lang];
    if (lang) {
        [env setObject:lang forKey:@"LANG"];
    } else {
        [env setObject:[self encodingName] forKey:@"LC_CTYPE"];
    }

    if ([env objectForKey:PWD_ENVNAME] == nil)
        [env setObject:[PWD_ENVVALUE stringByExpandingTildeInPath] forKey:PWD_ENVNAME];

    [SHELL launchWithPath:path
                arguments:argv
              environment:env
                    width:[SCREEN width]
                   height:[SCREEN height]
                   isUTF8:isUTF8
           asLoginSession:asLoginSession];

}


- (void)terminate
{
    // deregister from the notification center
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    if (liveSession_) {
        [liveSession_ terminate];
    }

    EXIT = YES;
    [SHELL stop];

    // final update of display
    [self updateDisplay];

    [TEXTVIEW setDataSource: nil];
    [TEXTVIEW setDelegate: nil];
    [TEXTVIEW removeFromSuperview];
    TEXTVIEW = nil;

    [SHELL setDelegate:nil];
    [SCREEN setShellTask:nil];
    [SCREEN setSession:nil];
    [SCREEN setTerminal:nil];
    [TERMINAL setScreen:nil];

    [updateTimer invalidate];
    [updateTimer release];
    updateTimer = nil;

    if (slowPasteTimer) {
        [slowPasteTimer invalidate];
        slowPasteTimer = nil;
    }

    [tab_ removeSession:self];
    tab_ = nil;
}

- (void)writeTask:(NSData*)data
{
    // check if we want to send this input to all the sessions
    id<WindowControllerInterface> parent = [[self tab] parentWindow];
    if ([parent sendInputToAllSessions] == NO) {
        if (!EXIT) {
            [self setBell:NO];
            PTYScroller* ptys = (PTYScroller*)[SCROLLVIEW verticalScroller];
            [SHELL writeTask:data];
            [ptys setUserScroll:NO];
        }
    } else {
        // send to all sessions
        [parent sendInputToAllSessions:data];
    }
}

- (void)readTask:(NSData*)data
{
    if ([data length] == 0 || EXIT) {
        return;
    }
    if (gDebugLogging) {
      const char* bytes = [data bytes];
      int length = [data length];
      DebugLog([NSString stringWithFormat:@"readTask called with %d bytes. The last byte is %d", (int)length, (int)bytes[length-1]]);
    }

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession readTask:%@]", __FILE__, __LINE__,
        [[NSString alloc] initWithBytes:[data bytes] length:[data length] encoding:nil]);
#endif

    [TERMINAL putStreamData:data];

    VT100TCC token;

    // while loop to process all the tokens we can get
    while (!EXIT &&
           TERMINAL &&
           ((token = [TERMINAL getNextToken]),
            token.type != VT100_WAIT &&
            token.type != VT100CC_NULL)) {
        // process token
        if (token.type != VT100_SKIP) {
            if (token.type == VT100_NOTSUPPORT) {
                //NSLog(@"%s(%d):not support token", __FILE__ , __LINE__);
            } else {
                [SCREEN putToken:token];
            }
        }
    } // end token processing loop

    gettimeofday(&lastOutput, NULL);
    newOutput = YES;

    // Make sure the screen gets redrawn soonish
    if ([[[self tab] parentWindow] currentTab] == [self tab]) {
        if ([data length] < 1024) {
            [self scheduleUpdateIn:kFastTimerIntervalSec];
        } else {
            [self scheduleUpdateIn:kSlowTimerIntervalSec];
        }
    } else {
        [self scheduleUpdateIn:kBackgroundSessionIntervalSec];
    }
}

- (void)brokenPipe
{
    if ([SCREEN growl]) {
        [gd growlNotify:NSLocalizedStringFromTableInBundle(@"Broken Pipe",
                                                           @"iTerm",
                                                           [NSBundle bundleForClass:[self class]],
                                                           @"Growl Alerts")
            withDescription:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Session %@ #%d just terminated.",
                                                                                          @"iTerm",
                                                                                          [NSBundle bundleForClass:[self class]],
                                                                                          @"Growl Alerts"),
                             [self name],
                             [[self tab] realObjectCount]]
            andNotification:@"Broken Pipes"];
    }

    EXIT = YES;
    [[self tab] setLabelAttributes];

    if ([self autoClose]) {
        [[self tab] closeSession:self];
    } else {
        [self updateDisplay];
    }
}

- (BOOL)hasActionableKeyMappingForEvent:(NSEvent *)event
{
    unsigned int modflag;
    NSString *unmodkeystr;
    unichar unmodunicode;
    int keyBindingAction;
    NSString *keyBindingText;

    modflag = [event modifierFlags];
    unmodkeystr = [event charactersIgnoringModifiers];
    unmodunicode = [unmodkeystr length]>0?[unmodkeystr characterAtIndex:0]:0;

    /*
    unsigned short keycode = [event keyCode];
    NSString *keystr = [event characters];
    unichar unicode = [keystr length] > 0 ? [keystr characterAtIndex:0] : 0;
    NSLog(@"event:%@ (%x+%x)[%@][%@]:%x(%c) <%d>", event,modflag,keycode,keystr,unmodkeystr,unicode,unicode,(modflag & NSNumericPadKeyMask));
    */

    // Check if we have a custom key mapping for this event

    keyBindingAction = [iTermKeyBindingMgr actionForKeyCode:unmodunicode
                                                  modifiers:modflag
                                                       text:&keyBindingText
                                                keyMappings:[[self addressBookEntry] objectForKey: KEY_KEYBOARD_MAP]];


    return (keyBindingAction >= 0) && (keyBindingAction != KEY_ACTION_DO_NOT_REMAP_MODIFIERS) && (keyBindingAction != KEY_ACTION_REMAP_LOCALLY);
}

+ (void)reloadAllBookmarks
{
    int n = [[iTermController sharedInstance] numberOfTerminals];
    for (int i = 0; i < n; ++i) {
        PseudoTerminal* pty = [[iTermController sharedInstance] terminalAtIndex:i];
        [pty reloadBookmarks];
    }
}

- (BOOL)_askAboutOutdatedKeyMappings
{
    NSNumber* n = [addressBookEntry objectForKey:KEY_ASK_ABOUT_OUTDATED_KEYMAPS];
    return n ? [n boolValue] : YES;
}

- (void)_removeOutdatedKeyMapping
{
    NSMutableDictionary* temp = [NSMutableDictionary dictionaryWithDictionary:addressBookEntry];
    [iTermKeyBindingMgr removeMappingWithCode:NSLeftArrowFunctionKey
                                    modifiers:NSCommandKeyMask | NSAlternateKeyMask | NSNumericPadKeyMask
                                   inBookmark:temp];
    [iTermKeyBindingMgr removeMappingWithCode:NSRightArrowFunctionKey
                                    modifiers:NSCommandKeyMask | NSAlternateKeyMask | NSNumericPadKeyMask
                                   inBookmark:temp];

    BookmarkModel* model;
    if (isDivorced) {
        model = [BookmarkModel sessionsInstance];
    } else {
        model = [BookmarkModel sharedInstance];
    }
    [model setBookmark:temp withGuid:[temp objectForKey:KEY_GUID]];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermKeyBindingsChanged"
                                                        object:nil
                                                      userInfo:nil];
    [PTYSession reloadAllBookmarks];
}

- (void)_setKeepOutdatedKeyMapping
{
    BookmarkModel* model;
    if (isDivorced) {
        model = [BookmarkModel sessionsInstance];
    } else {
        model = [BookmarkModel sharedInstance];
    }
    [model setObject:[NSNumber numberWithBool:NO]
                                       forKey:KEY_ASK_ABOUT_OUTDATED_KEYMAPS
                                   inBookmark:addressBookEntry];
    [PTYSession reloadAllBookmarks];
}

+ (BOOL)_recursiveSelectMenuItem:(NSString*)theName inMenu:(NSMenu*)menu
{
    for (NSMenuItem* item in [menu itemArray]) {
        if (![item isEnabled] || [item isHidden] || [item isAlternate]) {
            continue;
        }
        if ([item hasSubmenu]) {
            if ([PTYSession _recursiveSelectMenuItem:theName inMenu:[item submenu]]) {
                return YES;
            }
        } else if ([theName isEqualToString:[item title]]) {
            [NSApp sendAction:[item action]
                           to:[item target]
                         from:nil];
            return YES;
        }
    }
    return NO;
}

+ (BOOL)handleShortcutWithoutTerminal:(NSEvent*)event
{
    unsigned int modflag;
    NSString *unmodkeystr;
    unichar unmodunicode;
    int keyBindingAction;
    NSString *keyBindingText;

    modflag = [event modifierFlags];
    unmodkeystr = [event charactersIgnoringModifiers];
    unmodunicode = [unmodkeystr length]>0?[unmodkeystr characterAtIndex:0]:0;

    // Check if we have a custom key mapping for this event
    keyBindingAction = [iTermKeyBindingMgr actionForKeyCode:unmodunicode
                                                  modifiers:modflag
                                                       text:&keyBindingText
                                                keyMappings:[iTermKeyBindingMgr globalKeyMap]];


    if (keyBindingAction == KEY_ACTION_SELECT_MENU_ITEM) {
        [PTYSession selectMenuItem:keyBindingText];
        return YES;
    } else {
        return NO;
    }
}


+ (void)selectMenuItem:(NSString*)theName
{
    if (![self _recursiveSelectMenuItem:theName inMenu:[NSApp mainMenu]]) {
        NSBeep();
    }
}

// Handle bookmark- and global-scope keybindings. If there is no keybinding then
// pass the keystroke as input.
- (void)keyDown:(NSEvent *)event
{
    unsigned char *send_str = NULL;
    unsigned char *dataPtr = NULL;
    int dataLength = 0;
    size_t send_strlen = 0;
    int send_pchr = -1;
    int keyBindingAction;
    NSString *keyBindingText;

    unsigned int modflag;
    NSString *keystr;
    NSString *unmodkeystr;
    unichar unicode, unmodunicode;

#if DEBUG_METHOD_TRACE || DEBUG_KEYDOWNDUMP
    NSLog(@"%s(%d):-[PTYSession keyDown:%@]",
          __FILE__, __LINE__, event);
#endif

    modflag = [event modifierFlags];
    keystr  = [event characters];
    unmodkeystr = [event charactersIgnoringModifiers];
    if ([unmodkeystr length] == 0) {
        return;
    }
    unicode = [keystr length] > 0 ? [keystr characterAtIndex:0] : 0;
    unmodunicode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;

    gettimeofday(&lastInput, NULL);

    if ([[[self tab] realParentWindow] inInstantReplay]) {
        // Special key handling in IR mode, and keys never get sent to the live
        // session, even though it might be displayed.
        if (unicode == 27) {
            // Escape exits IR
            [[[self tab] realParentWindow] closeInstantReplay:self];
            return;
        } else if (unmodunicode == NSLeftArrowFunctionKey) {
            // Left arrow moves to prev frame
            [[[self tab] realParentWindow] irPrev:self];
        } else if (unmodunicode == NSRightArrowFunctionKey) {
            // Right arrow moves to next frame
            [[[self tab] realParentWindow] irNext:self];
        } else {
            NSBeep();
        }
        return;
    }

    /*
    unsigned short keycode = [event keyCode];
    NSLog(@"event:%@ (%x+%x)[%@][%@]:%x(%c) <%d>", event,modflag,keycode,keystr,unmodkeystr,unicode,unicode,(modflag & NSNumericPadKeyMask));
    */

    // Check if we have a custom key mapping for this event
    keyBindingAction = [iTermKeyBindingMgr actionForKeyCode:unmodunicode
                                                  modifiers:modflag
                                                       text:&keyBindingText
                                                keyMappings:[[self addressBookEntry] objectForKey:KEY_KEYBOARD_MAP]];

    if (keyBindingAction >= 0) {
        // A special action was bound to this key combination.
        NSString *aString;

        if (keyBindingAction == KEY_ACTION_NEXT_SESSION ||
            keyBindingAction == KEY_ACTION_PREVIOUS_SESSION) {
            // Warn users about outdated default key bindings.
            int tempMods = modflag & (NSAlternateKeyMask | NSControlKeyMask | NSShiftKeyMask | NSCommandKeyMask);
            int tempKeyCode = unmodunicode;
            if (tempMods == (NSCommandKeyMask | NSAlternateKeyMask) &&
                (tempKeyCode == 0xf702 || tempKeyCode == 0xf703) &&
                [[[self tab] sessions] count] > 1) {
                if ([self _askAboutOutdatedKeyMappings]) {
                    int result = NSRunAlertPanel(@"Outdated Key Mapping Found",
                                                 @"It looks like you're trying to switch split panes but you have a key mapping from an old iTerm installation for ⌘⌥← or ⌘⌥→ that switches tabs instead. What would you like to do?",
                                                 @"Remove it",
                                                 @"Remind me later",
                                                 @"Keep it");
                    switch (result) {
                        case NSAlertDefaultReturn:
                            // Remove it
                            [self _removeOutdatedKeyMapping];
                            return;
                            break;
                        case NSAlertAlternateReturn:
                            // Remind me later
                            break;
                        case NSAlertOtherReturn:
                            // Keep it
                            [self _setKeepOutdatedKeyMapping];
                            break;
                        default:
                            break;
                    }
                }
            }
        }

        switch (keyBindingAction) {
            case KEY_ACTION_NEXT_SESSION:
                [[[self tab] parentWindow] nextTab:nil];
                break;
            case KEY_ACTION_NEXT_WINDOW:
                [[iTermController sharedInstance] nextTerminal:nil];
                break;
            case KEY_ACTION_PREVIOUS_SESSION:
                [[[self tab] parentWindow] previousTab:nil];
                break;
            case KEY_ACTION_PREVIOUS_WINDOW:
                [[iTermController sharedInstance] previousTerminal:nil];
                break;
            case KEY_ACTION_SCROLL_END:
                [TEXTVIEW scrollEnd];
                [(PTYScrollView *)[TEXTVIEW enclosingScrollView] detectUserScroll];
                break;
            case KEY_ACTION_SCROLL_HOME:
                [TEXTVIEW scrollHome];
                [(PTYScrollView *)[TEXTVIEW enclosingScrollView] detectUserScroll];
                break;
            case KEY_ACTION_SCROLL_LINE_DOWN:
                [TEXTVIEW scrollLineDown:self];
                [(PTYScrollView *)[TEXTVIEW enclosingScrollView] detectUserScroll];
                break;
            case KEY_ACTION_SCROLL_LINE_UP:
                [TEXTVIEW scrollLineUp:self];
                [(PTYScrollView *)[TEXTVIEW enclosingScrollView] detectUserScroll];
                break;
            case KEY_ACTION_SCROLL_PAGE_DOWN:
                [TEXTVIEW scrollPageDown:self];
                [(PTYScrollView *)[TEXTVIEW enclosingScrollView] detectUserScroll];
                break;
            case KEY_ACTION_SCROLL_PAGE_UP:
                [TEXTVIEW scrollPageUp:self];
                [(PTYScrollView *)[TEXTVIEW enclosingScrollView] detectUserScroll];
                break;
            case KEY_ACTION_ESCAPE_SEQUENCE:
                if (EXIT) {
                    return;
                }
                if ([keyBindingText length] > 0) {
                    aString = [NSString stringWithFormat:@"\e%@", keyBindingText];
                    [self writeTask:[aString dataUsingEncoding:NSUTF8StringEncoding]];
                }
                break;
            case KEY_ACTION_HEX_CODE:
                if (EXIT) {
                    return;
                }
                if ([keyBindingText length]) {
                    NSArray* components = [keyBindingText componentsSeparatedByString:@" "];
                    for (NSString* part in components) {
                        const char* utf8 = [part UTF8String];
                        char* endPtr;
                        unsigned char c = strtol(utf8, &endPtr, 16);
                        if (endPtr != utf8) {
                            [self writeTask:[NSData dataWithBytes:&c length:sizeof(c)]];
                        }
                    }
                }
                break;
            case KEY_ACTION_TEXT:
                if (EXIT) {
                    return;
                }
                if([keyBindingText length] > 0) {
                    NSMutableString *bindingText = [NSMutableString stringWithString:keyBindingText];
                    [bindingText replaceOccurrencesOfString:@"\\n" withString:@"\n" options:NSLiteralSearch range:NSMakeRange(0,[bindingText length])];
                    [bindingText replaceOccurrencesOfString:@"\\e" withString:@"\e" options:NSLiteralSearch range:NSMakeRange(0,[bindingText length])];
                    [bindingText replaceOccurrencesOfString:@"\\a" withString:@"\a" options:NSLiteralSearch range:NSMakeRange(0,[bindingText length])];
                    [bindingText replaceOccurrencesOfString:@"\\t" withString:@"\t" options:NSLiteralSearch range:NSMakeRange(0,[bindingText length])];
                    [self writeTask:[bindingText dataUsingEncoding:NSUTF8StringEncoding]];
                }
                break;
            case KEY_ACTION_SELECT_MENU_ITEM:
                [PTYSession selectMenuItem:keyBindingText];
                break;

            case KEY_ACTION_SEND_C_H_BACKSPACE:
                if (EXIT) {
                    return;
                }
                [self writeTask:[@"\010" dataUsingEncoding:NSUTF8StringEncoding]];
                break;
            case KEY_ACTION_SEND_C_QM_BACKSPACE:
                if (EXIT) {
                    return;
                }
                [self writeTask:[@"\177" dataUsingEncoding:NSUTF8StringEncoding]]; // decimal 127
                break;
            case KEY_ACTION_IGNORE:
                break;
            case KEY_ACTION_IR_FORWARD:
                [[iTermController sharedInstance] irAdvance:1];
                break;
            case KEY_ACTION_IR_BACKWARD:
                [[iTermController sharedInstance] irAdvance:-1];
                break;
            case KEY_ACTION_SELECT_PANE_LEFT:
                [[[iTermController sharedInstance] currentTerminal] selectPaneLeft:nil];
                break;
            case KEY_ACTION_SELECT_PANE_RIGHT:
                [[[iTermController sharedInstance] currentTerminal] selectPaneRight:nil];
                break;
            case KEY_ACTION_SELECT_PANE_ABOVE:
                [[[iTermController sharedInstance] currentTerminal] selectPaneUp:nil];
                break;
            case KEY_ACTION_SELECT_PANE_BELOW:
                [[[iTermController sharedInstance] currentTerminal] selectPaneDown:nil];
                break;
            case KEY_ACTION_DO_NOT_REMAP_MODIFIERS:
            case KEY_ACTION_REMAP_LOCALLY:
                break;
            case KEY_ACTION_TOGGLE_FULLSCREEN:
                [[[iTermController sharedInstance] currentTerminal] toggleFullScreen:nil];
                break;
            case KEY_ACTION_NEW_WINDOW_WITH_PROFILE:
                [[[self tab] realParentWindow] newWindowWithBookmarkGuid:keyBindingText];
                break;
            case KEY_ACTION_NEW_TAB_WITH_PROFILE:
                [[[self tab] realParentWindow] newTabWithBookmarkGuid:keyBindingText];
                break;
            case KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE:
                [[[self tab] realParentWindow] splitVertically:NO withBookmarkGuid:keyBindingText];
                break;
            case KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE:
                [[[self tab] realParentWindow] splitVertically:YES withBookmarkGuid:keyBindingText];
                break;
            default:
                NSLog(@"Unknown key action %d", keyBindingAction);
                break;
        }
    } else {
        if (EXIT) {
            return;
        }
        // No special binding for this key combination.
        if (modflag & NSFunctionKeyMask) {
            // Handle all "special" keys (arrows, etc.)
            NSData *data = nil;

            // Set the alternate key mask iff an esc-generating modifier is
            // pressed.
            unsigned int hackedModflag = modflag & (~NSAlternateKeyMask);
            if ([self shouldSendEscPrefixForModifier:modflag]) {
                hackedModflag |= NSAlternateKeyMask;
            }

            switch (unicode) {
                case NSUpArrowFunctionKey:
                    data = [TERMINAL keyArrowUp:hackedModflag];
                    break;
                case NSDownArrowFunctionKey:
                    data = [TERMINAL keyArrowDown:hackedModflag];
                    break;
                case NSLeftArrowFunctionKey:
                    data = [TERMINAL keyArrowLeft:hackedModflag];
                    break;
                case NSRightArrowFunctionKey:
                    data = [TERMINAL keyArrowRight:hackedModflag];
                    break;
                case NSInsertFunctionKey:
                    data = [TERMINAL keyInsert];
                    break;
                case NSDeleteFunctionKey:
                    // This is forward delete, not backspace.
                    data = [TERMINAL keyDelete];
                    break;
                case NSHomeFunctionKey:
                    data = [TERMINAL keyHome:hackedModflag];
                    break;
                case NSEndFunctionKey:
                    data = [TERMINAL keyEnd:hackedModflag];
                    break;
                case NSPageUpFunctionKey:
                    data = [TERMINAL keyPageUp:hackedModflag];
                    break;
                case NSPageDownFunctionKey:
                    data = [TERMINAL keyPageDown:hackedModflag];
                    break;
                case NSClearLineFunctionKey:
                    data = [@"\e" dataUsingEncoding:NSUTF8StringEncoding];
                    break;
            }

            if (NSF1FunctionKey <= unicode && unicode <= NSF35FunctionKey) {
                data = [TERMINAL keyFunction:unicode - NSF1FunctionKey + 1];
            }

            if (data != nil) {
                send_str = (unsigned char *)[data bytes];
                send_strlen = [data length];
            } else if (keystr != nil) {
                NSData *keydat = ((modflag & NSControlKeyMask) && unicode > 0) ?
                    [keystr dataUsingEncoding:NSUTF8StringEncoding] :
                    [unmodkeystr dataUsingEncoding:NSUTF8StringEncoding];
                send_str = (unsigned char *)[keydat bytes];
                send_strlen = [keydat length];
            }
        } else if (((modflag & NSLeftAlternateKeyMask) == NSLeftAlternateKeyMask &&
                    ([self optionKey] != OPT_NORMAL)) ||
                   ((modflag & NSRightAlternateKeyMask) == NSRightAlternateKeyMask &&
                    ([self rightOptionKey] != OPT_NORMAL))) {
            // A key was pressed while holding down option and the option key
            // is not behaving normally. Apply the modified behavior.
            int mode;  // The modified behavior based on which modifier is pressed.
            if ((modflag & NSLeftAlternateKeyMask) == NSLeftAlternateKeyMask) {
                mode = [self optionKey];
            } else {
                mode = [self rightOptionKey];
            }

            NSData *keydat = ((modflag & NSControlKeyMask) && unicode > 0)?
                [keystr dataUsingEncoding:NSUTF8StringEncoding]:
                [unmodkeystr dataUsingEncoding:NSUTF8StringEncoding];
            if (keydat != nil) {
                send_str = (unsigned char *)[keydat bytes];
                send_strlen = [keydat length];
            }
            if (mode == OPT_ESC) {
                send_pchr = '\e';
            } else if (mode == OPT_META && send_str != NULL) {
                int i;
                for (i = 0; i < send_strlen; ++i) {
                    send_str[i] |= 0x80;
                }
            }
        } else {
            // Regular path for inserting a character from a keypress.
            int max = [keystr length];
            NSData *data=nil;

            if (max != 1||[keystr characterAtIndex:0] > 0x7f) {
                data = [keystr dataUsingEncoding:[TERMINAL encoding]];
            } else {
                data = [keystr dataUsingEncoding:NSUTF8StringEncoding];
            }

            // Enter key is on numeric keypad, but not marked as such
            if (unicode == NSEnterCharacter && unmodunicode == NSEnterCharacter) {
                modflag |= NSNumericPadKeyMask;
                keystr = @"\015";  // Enter key -> 0x0d
            }
            // Check if we are in keypad mode
            if (modflag & NSNumericPadKeyMask) {
                data = [TERMINAL keypadData:unicode keystr:keystr];
            }

            int indMask = modflag & NSDeviceIndependentModifierFlagsMask;
            if ((indMask & NSCommandKeyMask) &&   // pressing cmd
                ([keystr isEqualToString:@"0"] ||  // pressed 0 key
                 ([keystr intValue] > 0 && [keystr intValue] <= 9))) {   // or any other digit key
                // Do not send anything for cmd+number because the user probably
                // fat-fingered switching of tabs/windows.
                data = nil;
            }
            if (data != nil) {
                send_str = (unsigned char *)[data bytes];
                send_strlen = [data length];
                DebugLog([NSString stringWithFormat:@"modflag = 0x%x; send_strlen = %d; send_str[0] = '%c (0x%x)'",
                          modflag, send_strlen, send_str[0]]);
            }

            if ((modflag & NSControlKeyMask) &&
                send_strlen == 1 &&
                send_str[0] == '|') {
                // Control-| is sent as Control-backslash
                send_str = (unsigned char*)"\034";
                send_strlen = 1;
            } else if ((modflag & NSControlKeyMask) &&
                       (modflag & NSShiftKeyMask) &&
                       send_strlen == 1 &&
                       send_str[0] == '/') {
                // Control-shift-/ is sent as Control-?
                send_str = (unsigned char*)"\177";
                send_strlen = 1;
            } else if ((modflag & NSControlKeyMask) &&
                       send_strlen == 1 &&
                       send_str[0] == '/') {
                // Control-/ is sent as Control-/, but needs some help to do so.
                send_str = (unsigned char*)"\037"; // control-/
                send_strlen = 1;
            } else if ((modflag & NSShiftKeyMask) &&
                       send_strlen == 1 &&
                       send_str[0] == '\031') {
                // Shift-tab is sent as Esc-[Z (or "backtab")
                send_str = (unsigned char*)"\033[Z";
                send_strlen = 3;
            }

        }

        if (EXIT == NO) {
            if (send_pchr >= 0) {
                // Send a prefix character (e.g., esc).
                char c = send_pchr;
                dataPtr = (unsigned char*)&c;
                dataLength = 1;
                [self writeTask:[NSData dataWithBytes:dataPtr length:dataLength]];
            }

            if (send_str != NULL) {
                dataPtr = send_str;
                dataLength = send_strlen;
                [self writeTask:[NSData dataWithBytes:dataPtr length:dataLength]];
            }
        }
    }
}

- (BOOL)willHandleEvent:(NSEvent *) theEvent
{
    return NO;
}

- (void)handleEvent:(NSEvent *) theEvent
{
}

- (void)insertText:(NSString *)string
{
    NSData *data;
    NSMutableString *mstring;
    int i;
    int max;

    if (EXIT) {
        return;
    }

    //    NSLog(@"insertText:%@",string);
    mstring = [NSMutableString stringWithString:string];
    max = [string length];
    for (i = 0; i < max; i++) {
        // From http://lists.apple.com/archives/cocoa-dev/2001/Jul/msg00114.html
        // in MacJapanese, the backslash char (ASCII 0xdC) is mapped to Unicode 0xA5.
        // The following line gives you NSString containing an Unicode character Yen sign (0xA5) in Japanese localization.
        // string = [NSString stringWithCString:"\"];
        // TODO: Check the locale before doing this.
        if ([mstring characterAtIndex:i] == 0xa5) {
            [mstring replaceCharactersInRange:NSMakeRange(i, 1) withString:@"\\"];
        }
    }

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession insertText:%@]",
          __FILE__, __LINE__, mstring);
#endif

    data = [mstring dataUsingEncoding:[TERMINAL encoding]
                 allowLossyConversion:YES];

    if (data != nil) {
        [self writeTask:data];
    }
}

- (void)insertNewline:(id)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession insertNewline:%@]",
          __FILE__, __LINE__, sender);
#endif
    [self insertText:@"\n"];
}

- (void)insertTab:(id)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession insertTab:%@]",
          __FILE__, __LINE__, sender);
#endif
    [self insertText:@"\t"];
}

- (void)moveUp:(id)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession moveUp:%@]",
          __FILE__, __LINE__, sender);
#endif
    [self writeTask:[TERMINAL keyArrowUp:0]];
}

- (void)moveDown:(id)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession moveDown:%@]",
          __FILE__, __LINE__, sender);
#endif
    [self writeTask:[TERMINAL keyArrowDown:0]];
}

- (void)moveLeft:(id)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession moveLeft:%@]",
          __FILE__, __LINE__, sender);
#endif
    [self writeTask:[TERMINAL keyArrowLeft:0]];
}

- (void)moveRight:(id)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession moveRight:%@]",
          __FILE__, __LINE__, sender);
#endif
    [self writeTask:[TERMINAL keyArrowRight:0]];
}

- (void)pageUp:(id)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession pageUp:%@]",
          __FILE__, __LINE__, sender);
#endif
    [self writeTask:[TERMINAL keyPageUp:0]];
}

- (void)pageDown:(id)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession pageDown:%@]",
          __FILE__, __LINE__, sender);
#endif
    [self writeTask:[TERMINAL keyPageDown:0]];
}

+ (NSString*)pasteboardString
{
    NSPasteboard *board;

    board = [NSPasteboard generalPasteboard];
    assert(board != nil);

    NSArray *supportedTypes = [NSArray arrayWithObjects:NSFilenamesPboardType, NSStringPboardType, nil];
    NSString *bestType = [board availableTypeFromArray:supportedTypes];

    NSString* info = nil;
    if ([bestType isEqualToString:NSFilenamesPboardType]) {
        NSArray *filenames = [board propertyListForType:NSFilenamesPboardType];
        if ([filenames count] > 0) {
            info = [filenames componentsJoinedByString:@"\n"];
            if ([info length] == 0) {
                info = nil;
            }
        }
    } else {
        info = [board stringForType:NSStringPboardType];
    }
    return info;
}

- (void)paste:(id)sender
{
    NSString* pbStr = [PTYSession pasteboardString];
    if (pbStr) {
        NSMutableString *str;
        str = [[[NSMutableString alloc] initWithString:pbStr] autorelease];
        if ([sender tag] & 1) {
            // paste with escape;
            [str replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:NSLiteralSearch range:NSMakeRange(0, [str length])];
            [str replaceOccurrencesOfString:@"'" withString:@"\\'" options:NSLiteralSearch range:NSMakeRange(0, [str length])];
            [str replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:NSLiteralSearch range:NSMakeRange(0, [str length])];
            [str replaceOccurrencesOfString:@" " withString:@"\\ " options:NSLiteralSearch range:NSMakeRange(0, [str length])];
        }
        if ([sender tag] & 2) {
            [slowPasteBuffer setString:str];
            [self pasteSlowly:nil];
        } else {
            [self pasteString:str];
        }
    }
}

// Outputs 16 bytes every 125ms so that clients that don't buffer input can handle pasting large buffers.
// Override the constnats by setting defaults SlowPasteBytesPerCall and SlowPasteDelayBetweenCalls
- (void)pasteSlowly:(id)sender
{
    NSRange range;
    range.location = 0;
    NSNumber* pref = [[NSUserDefaults standardUserDefaults] valueForKey:@"SlowPasteBytesPerCall"];
    NSNumber* delay = [[NSUserDefaults standardUserDefaults] valueForKey:@"SlowPasteDelayBetweenCalls"];
    const int kBatchSize = pref ? [pref intValue] : 16;
    if ([slowPasteBuffer length] > kBatchSize) {
        range.length = kBatchSize;
    } else {
        range.length = [slowPasteBuffer length];
    }
    [self pasteString:[slowPasteBuffer substringWithRange:range]];
    [slowPasteBuffer deleteCharactersInRange:range];
    if ([slowPasteBuffer length] > 0) {
        slowPasteTimer = [NSTimer scheduledTimerWithTimeInterval:delay ? [delay floatValue] : 0.125
                                                          target:self
                                                        selector:@selector(pasteSlowly:)
                                                        userInfo:nil
                                                         repeats:NO];
    } else {
        slowPasteTimer = nil;
    }
}

- (void)pasteString:(NSString *)aString
{

    if ([aString length] > 0) {
        NSString *tempString = [aString stringReplaceSubstringFrom:@"\r\n" to:@"\r"];
        [self writeTask:[[tempString stringReplaceSubstringFrom:@"\n" to:@"\r"] dataUsingEncoding:[TERMINAL encoding]
                                                                             allowLossyConversion:YES]];
    } else {
        NSBeep();
    }

}

- (void)deleteBackward:(id)sender
{
    unsigned char p = 0x08; // Ctrl+H

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession deleteBackward:%@]",
          __FILE__, __LINE__, sender);
#endif

    [self writeTask:[NSData dataWithBytes:&p length:1]];
}

- (void)deleteForward:(id)sender
{
    unsigned char p = 0x7F; // DEL

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession deleteForward:%@]",
          __FILE__, __LINE__, sender);
#endif
    [self writeTask:[NSData dataWithBytes:&p length:1]];
}

- (void) textViewDidChangeSelection: (NSNotification *) aNotification
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession textViewDidChangeSelection]",
          __FILE__, __LINE__);
#endif

    if ([[PreferencePanel sharedInstance] copySelection]) {
        [TEXTVIEW copy: self];
    }
}

- (void) textViewResized: (NSNotification *) aNotification;
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s: textView = 0x%x", __PRETTY_FUNCTION__, TEXTVIEW);
#endif
    int w;
    int h;

    w = (int)(([[SCROLLVIEW contentView] frame].size.width - MARGIN * 2) / [TEXTVIEW charWidth]);
    h = (int)(([[SCROLLVIEW contentView] frame].size.height) / [TEXTVIEW lineHeight]);
    //NSLog(@"%s: w = %d; h = %d; old w = %d; old h = %d", __PRETTY_FUNCTION__, w, h, [SCREEN width], [SCREEN height]);

    [self setWidth:w height:h];
}

- (BOOL) bell
{
    return bell;
}

- (void)setBell:(BOOL)flag
{
    if (flag != bell) {
        bell = flag;
        [[self tab] setBell:flag];
        if (bell) {
            if ([TEXTVIEW keyIsARepeat] == NO &&
                ![[TEXTVIEW window] isKeyWindow] &&
                [SCREEN growl]) {
                [gd growlNotify:NSLocalizedStringFromTableInBundle(@"Bell",
                                                                   @"iTerm",
                                                                   [NSBundle bundleForClass:[self class]],
                                                                   @"Growl Alerts")
                withDescription:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Session %@ #%d just rang a bell!",
                                                                                              @"iTerm",
                                                                                              [NSBundle bundleForClass:[self class]],
                                                                                              @"Growl Alerts"),
                                 [self name],
                                 [[self tab] realObjectCount]]
                andNotification:@"Bells"];
            }
        }
    }
}

- (NSString*)ansiColorsMatchingForeground:(NSDictionary*)fg andBackground:(NSDictionary*)bg inBookmark:(Bookmark*)aDict
{
    NSColor *fgColor;
    NSColor *bgColor;
    fgColor = [ITAddressBookMgr decodeColor:fg];
    bgColor = [ITAddressBookMgr decodeColor:bg];

    int bgNum = -1;
    int fgNum = -1;
    for(int i = 0; i < 16; ++i) {
        NSString* key = [NSString stringWithFormat:KEYTEMPLATE_ANSI_X_COLOR, i];
        if ([fgColor isEqual: [ITAddressBookMgr decodeColor:[aDict objectForKey:key]]]) {
            fgNum = i;
        }
        if ([bgColor isEqual: [ITAddressBookMgr decodeColor:[aDict objectForKey:key]]]) {
            bgNum = i;
        }
    }

    if (bgNum < 0 || fgNum < 0) {
        return nil;
    }

    return ([[NSString alloc] initWithFormat:@"%d;%d", fgNum, bgNum]);
}

- (void)setPreferencesFromAddressBookEntry:(NSDictionary *) aePrefs
{
    NSColor *colorTable[2][8];
    int i;
    NSDictionary *aDict;

    aDict = aePrefs;
    if (aDict == nil) {
        aDict = [[BookmarkModel sharedInstance] defaultBookmark];
    }
    if (aDict == nil) {
        return;
    }

    [self setForegroundColor:[ITAddressBookMgr decodeColor:[aDict objectForKey:KEY_FOREGROUND_COLOR]]];
    [self setBackgroundColor:[ITAddressBookMgr decodeColor:[aDict objectForKey:KEY_BACKGROUND_COLOR]]];
    [self setSelectionColor:[ITAddressBookMgr decodeColor:[aDict objectForKey:KEY_SELECTION_COLOR]]];
    [self setSelectedTextColor:[ITAddressBookMgr decodeColor:[aDict objectForKey:KEY_SELECTED_TEXT_COLOR]]];
    [self setBoldColor:[ITAddressBookMgr decodeColor:[aDict objectForKey:KEY_BOLD_COLOR]]];
    [self setCursorColor:[ITAddressBookMgr decodeColor:[aDict objectForKey:KEY_CURSOR_COLOR]]];
    [self setCursorTextColor:[ITAddressBookMgr decodeColor:[aDict objectForKey:KEY_CURSOR_TEXT_COLOR]]];
    BOOL scc;
    if ([aDict objectForKey:KEY_SMART_CURSOR_COLOR]) {
        scc = [[aDict objectForKey:KEY_SMART_CURSOR_COLOR] boolValue];
    } else {
        scc = [[PreferencePanel sharedInstance] legacySmartCursorColor];
    }
    [self setSmartCursorColor:scc];

    float mc;
    if ([aDict objectForKey:KEY_MINIMUM_CONTRAST]) {
        mc = [[aDict objectForKey:KEY_MINIMUM_CONTRAST] floatValue];
    } else {
        mc = [[PreferencePanel sharedInstance] legacyMinimumContrast];
    }
    [self setMinimumContrast:mc];

    for (i = 0; i < 8; i++) {
        colorTable[0][i] = [ITAddressBookMgr decodeColor:[aDict objectForKey:[NSString stringWithFormat:KEYTEMPLATE_ANSI_X_COLOR, i]]];
        colorTable[1][i] = [ITAddressBookMgr decodeColor:[aDict objectForKey:[NSString stringWithFormat:KEYTEMPLATE_ANSI_X_COLOR, i + 8]]];
    }
    for(i = 0; i < 8; i++) {
        [self setColorTable:i color:colorTable[0][i]];
        [self setColorTable:i+8 color:colorTable[1][i]];
    }
    for (i = 0; i < 216; i++) {
        [self setColorTable:i+16
                      color:[NSColor colorWithCalibratedRed:(i/36) ? ((i/36)*40+55)/256.0 : 0
                                                      green:(i%36)/6 ? (((i%36)/6)*40+55)/256.0:0
                                                       blue:(i%6) ?((i%6)*40+55)/256.0:0
                                                      alpha:1]];
    }
    for (i = 0; i < 24; i++) {
        [self setColorTable:i+232 color:[NSColor colorWithCalibratedWhite:(i*10+8)/256.0 alpha:1]];
    }

    // background image
    [self setBackgroundImagePath:[aDict objectForKey:KEY_BACKGROUND_IMAGE_LOCATION]];

    // colour scheme
    [self setCOLORFGBG_VALUE: [self ansiColorsMatchingForeground:[aDict objectForKey:KEY_FOREGROUND_COLOR]
                                                   andBackground:[aDict objectForKey:KEY_BACKGROUND_COLOR]
                                                      inBookmark:aDict]];

    // transparency
    [self setTransparency:[[aDict objectForKey:KEY_TRANSPARENCY] floatValue]];

    // bold
    NSNumber* useBoldFontEntry = [aDict objectForKey:KEY_USE_BOLD_FONT];
    NSNumber* disableBoldEntry = [aDict objectForKey:KEY_DISABLE_BOLD];
    if (useBoldFontEntry) {
        [self setUseBoldFont:[useBoldFontEntry boolValue]];
    } else if (disableBoldEntry) {
        // Only deprecated option is set.
        [self setUseBoldFont:![disableBoldEntry boolValue]];
    } else {
        [self setUseBoldFont:YES];
    }
    [TEXTVIEW setUseBrightBold:[aDict objectForKey:KEY_USE_BRIGHT_BOLD] ? [[aDict objectForKey:KEY_USE_BRIGHT_BOLD] boolValue] : YES];

    // set up the rest of the preferences
    [SCREEN setPlayBellFlag:![[aDict objectForKey:KEY_SILENCE_BELL] boolValue]];
    [SCREEN setShowBellFlag:[[aDict objectForKey:KEY_VISUAL_BELL] boolValue]];
    [SCREEN setFlashBellFlag:[[aDict objectForKey:KEY_FLASHING_BELL] boolValue]];
    [SCREEN setGrowlFlag:[[aDict objectForKey:KEY_BOOKMARK_GROWL_NOTIFICATIONS] boolValue]];
    [SCREEN setBlinkingCursor:[[aDict objectForKey: KEY_BLINKING_CURSOR] boolValue]];
    [TEXTVIEW setBlinkAllowed:[[aDict objectForKey:KEY_BLINK_ALLOWED] boolValue]];
    [TEXTVIEW setBlinkingCursor:[[aDict objectForKey: KEY_BLINKING_CURSOR] boolValue]];
    [TEXTVIEW setCursorType:([aDict objectForKey:KEY_CURSOR_TYPE] ? [[aDict objectForKey:KEY_CURSOR_TYPE] intValue] : [[PreferencePanel sharedInstance] legacyCursorType])];

    PTYTab* currentTab = [[[self tab] parentWindow] currentTab];
    if (currentTab == nil || currentTab == [self tab]) {
        [[self tab] recheckBlur];
    }
    BOOL asciiAA;
    BOOL nonasciiAA;
    if ([aDict objectForKey:KEY_ASCII_ANTI_ALIASED]) {
        asciiAA = [[aDict objectForKey:KEY_ASCII_ANTI_ALIASED] boolValue];
    } else {
        asciiAA = [[aDict objectForKey:KEY_ANTI_ALIASING] boolValue];
    }
    if ([aDict objectForKey:KEY_NONASCII_ANTI_ALIASED]) {
        nonasciiAA = [[aDict objectForKey:KEY_NONASCII_ANTI_ALIASED] boolValue];
    } else {
        nonasciiAA = [[aDict objectForKey:KEY_ANTI_ALIASING] boolValue];
    }
    [TEXTVIEW setAntiAlias:asciiAA nonAscii:nonasciiAA];
    [self setEncoding:[[aDict objectForKey:KEY_CHARACTER_ENCODING] unsignedIntValue]];
    [self setTERM_VALUE:[aDict objectForKey:KEY_TERMINAL_TYPE]];
    [self setAntiCode:[[aDict objectForKey:KEY_IDLE_CODE] intValue]];
    [self setAntiIdle:[[aDict objectForKey:KEY_SEND_CODE_WHEN_IDLE] boolValue]];
    [self setAutoClose:[[aDict objectForKey:KEY_CLOSE_SESSIONS_ON_END] boolValue]];
    [self setDoubleWidth:[[aDict objectForKey:KEY_AMBIGUOUS_DOUBLE_WIDTH] boolValue]];
    [self setXtermMouseReporting:[[aDict objectForKey:KEY_XTERM_MOUSE_REPORTING] boolValue]];
    [TERMINAL setDisableSmcupRmcup:[[aDict objectForKey:KEY_DISABLE_SMCUP_RMCUP] boolValue]];
    [SCREEN setUnlimitedScrollback:[[aDict objectForKey:KEY_UNLIMITED_SCROLLBACK] intValue]];
    [SCREEN setScrollback:[[aDict objectForKey:KEY_SCROLLBACK_LINES] intValue]];

    [self setFont:[ITAddressBookMgr fontWithDesc:[aDict objectForKey:KEY_NORMAL_FONT]]
           nafont:[ITAddressBookMgr fontWithDesc:[aDict objectForKey:KEY_NON_ASCII_FONT]]
        horizontalSpacing:[[aDict objectForKey:KEY_HORIZONTAL_SPACING] floatValue]
        verticalSpacing:[[aDict objectForKey:KEY_VERTICAL_SPACING] floatValue]];
}

// Contextual menu
- (void)menuForEvent:(NSEvent *)theEvent menu:(NSMenu *)theMenu
{
    // Ask the parent if it has anything to add
    if ([[self tab] realParentWindow] &&
        [[[self tab] realParentWindow] respondsToSelector:@selector(menuForEvent: menu:)]) {
        [[[self tab] realParentWindow] menuForEvent:theEvent menu: theMenu];
    }
}

- (NSString *)uniqueID
{
    return ([self tty]);
}

- (void)setUniqueID:(NSString*)uniqueID
{
    NSLog(@"Not allowed to set unique ID");
}

- (NSString*)formattedName:(NSString*)base
{
    BOOL baseIsBookmarkName = [base isEqualToString:bookmarkName];
    PreferencePanel* panel = [PreferencePanel sharedInstance];
    if ([panel jobName] && jobName_) {
        if (baseIsBookmarkName && ![panel showBookmarkName]) {
            return [NSString stringWithString:[self jobName]];
        } else {
            return [NSString stringWithFormat:@"%@ (%@)", base, [self jobName]];
        }
    } else {
        if (baseIsBookmarkName && ![panel showBookmarkName]) {
            return @"Shell";
        } else {
            return base;
        }
    }
}

- (NSString*)defaultName
{
    return [self formattedName:defaultName];
}

- (NSString*)joblessDefaultName
{
    return defaultName;
}

- (void)setDefaultName:(NSString*)theName
{
    if ([defaultName isEqualToString:theName]) {
        return;
    }

    if (defaultName) {
        // clear the window title if it is not different
        if (windowTitle == nil || [name isEqualToString:windowTitle]) {
            windowTitle = nil;
        }
        [defaultName release];
        defaultName = nil;
    }
    if (!theName) {
        theName = NSLocalizedStringFromTableInBundle(@"Untitled",
                                                     @"iTerm",
                                                     [NSBundle bundleForClass:[self class]],
                                                     @"Profiles");
    }

    defaultName = [theName retain];
}

- (PTYTab*)tab
{
    return tab_;
}

- (PTYTab*)ptytab
{
    return tab_;
}

- (void)setTab:(PTYTab*)tab
{
    tab_ = tab;
}

- (struct timeval)lastOutput
{
    return lastOutput;
}

- (void)setGrowlIdle:(BOOL)value
{
    growlIdle = value;
}

- (BOOL)growlIdle
{
    return growlIdle;
}

- (void)setGrowlNewOutput:(BOOL)value
{
    growlNewOutput = value;
}

- (BOOL)growlNewOutput
{
    return growlNewOutput;
}

- (NSString*)name
{
    return [self formattedName:name];
}

- (NSString*)rawName
{
    return name;
}

- (void)setBookmarkName:(NSString*)theName
{
    [bookmarkName release];
    bookmarkName = [theName copy];
}

- (void)setName:(NSString*)theName
{
    if (!bookmarkName) {
        bookmarkName = [theName copy];
    }
    if ([name isEqualToString:theName]) {
        return;
    }

    if (name) {
        // clear the window title if it is not different
        if ([name isEqualToString:windowTitle]) {
            windowTitle = nil;
        }
        [name release];
        name = nil;
    }
    if (!theName) {
        theName = NSLocalizedStringFromTableInBundle(@"Untitled",
                                                     @"iTerm",
                                                     [NSBundle bundleForClass:[self class]],
                                                     @"Profiles");
    }

    name = [theName retain];
    // sync the window title if it is not set to something else
    if (windowTitle == nil) {
        [self setWindowTitle:theName];
    }

    [[self tab] nameOfSession:self didChangeTo:[self name]];
    [self setBell:NO];

    // get the session submenu to be rebuilt
    if ([[iTermController sharedInstance] currentTerminal] == [[self tab] parentWindow]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermNameOfSessionDidChange"
                                                            object:[[self tab] parentWindow]
                                                          userInfo:nil];
    }
}

- (NSString*)windowTitle
{
    if (!windowTitle) {
        return nil;
    }
    return [self formattedName:windowTitle];
}

- (void)setWindowTitle:(NSString*)theTitle
{
    if ([theTitle isEqualToString:windowTitle]) {
        return;
    }

    [windowTitle autorelease];
    windowTitle = nil;

    if (theTitle != nil && [theTitle length] > 0) {
        windowTitle = [theTitle retain];
    }

    if ([[[self tab] parentWindow] currentTab] == [self tab]) {
        [[[self tab] parentWindow] setWindowTitle];
    }
}

- (PTYTask *)SHELL
{
    return SHELL;
}

- (void)setSHELL:(PTYTask *)theSHELL
{
    [SHELL autorelease];
    SHELL = [theSHELL retain];
}

- (VT100Terminal *)TERMINAL
{
    return TERMINAL;
}

- (void)setTERMINAL:(VT100Terminal *)theTERMINAL
{
    [TERMINAL autorelease];
    TERMINAL = [theTERMINAL retain];
}

- (NSString *)TERM_VALUE
{
    return TERM_VALUE;
}

- (void)setTERM_VALUE:(NSString *)theTERM_VALUE
{
    [TERM_VALUE autorelease];
    TERM_VALUE = [theTERM_VALUE retain];
    [TERMINAL setTermType:theTERM_VALUE];
}

- (NSString *)COLORFGBG_VALUE
{
    return (COLORFGBG_VALUE);
}

- (void)setCOLORFGBG_VALUE:(NSString *)theCOLORFGBG_VALUE
{
    [COLORFGBG_VALUE autorelease];
    COLORFGBG_VALUE = [theCOLORFGBG_VALUE retain];
}

- (VT100Screen *)SCREEN
{
    return SCREEN;
}

- (void)setSCREEN:(VT100Screen *)theSCREEN
{
    [SCREEN autorelease];
    SCREEN = [theSCREEN retain];
}

- (NSImage *)image
{
    return [SCROLLVIEW backgroundImage];
}

- (SessionView *)view
{
    return view;
}

- (void)setView:(SessionView*)newView
{
    // View holds a reference to us so we don't hold a reference to it.
    view = newView;
    [[view findViewController] setDelegate:self];
}

- (PTYTextView *)TEXTVIEW
{
    return TEXTVIEW;
}

- (void)setTEXTVIEW:(PTYTextView *)theTEXTVIEW
{
    [TEXTVIEW autorelease];
    TEXTVIEW = [theTEXTVIEW retain];
}

- (PTYScrollView *)SCROLLVIEW
{
    return SCROLLVIEW;
}

- (void)setSCROLLVIEW:(PTYScrollView *)theSCROLLVIEW
{
    [SCROLLVIEW autorelease];
    SCROLLVIEW = [theSCROLLVIEW retain];
}

- (NSStringEncoding)encoding
{
    return [TERMINAL encoding];
}

- (void)setEncoding:(NSStringEncoding)encoding
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession setEncoding:%d]",
          __FILE__, __LINE__, encoding);
#endif
    [TERMINAL setEncoding:encoding];
}


- (NSString *)tty
{
    return [SHELL tty];
}

- (NSString *)contents
{
    return [TEXTVIEW content];
}

- (NSString *)backgroundImagePath
{
    return backgroundImagePath;
}

- (void)setBackgroundImagePath:(NSString *)imageFilePath
{
    if ([imageFilePath length]) {
        [imageFilePath retain];
        [backgroundImagePath release];
        backgroundImagePath = nil;

        if ([imageFilePath isAbsolutePath] == NO) {
            NSBundle *myBundle = [NSBundle bundleForClass:[self class]];
            backgroundImagePath = [myBundle pathForResource:imageFilePath ofType:@""];
            [imageFilePath release];
            [backgroundImagePath retain];
        } else {
            backgroundImagePath = imageFilePath;
        }
        NSImage *anImage = [[NSImage alloc] initWithContentsOfFile:backgroundImagePath];
        if (anImage != nil) {
            [SCROLLVIEW setDrawsBackground:NO];
            [SCROLLVIEW setBackgroundImage:anImage];
            [anImage release];
        } else {
            [SCROLLVIEW setDrawsBackground:YES];
            [backgroundImagePath release];
            backgroundImagePath = nil;
        }
    } else {
        [SCROLLVIEW setDrawsBackground:YES];
        [SCROLLVIEW setBackgroundImage:nil];
        [backgroundImagePath release];
        backgroundImagePath = nil;
    }

    [TEXTVIEW setNeedsDisplay:YES];
}


- (NSColor *)foregroundColor
{
    return [TEXTVIEW defaultFGColor];
}

- (void)setForegroundColor:(NSColor*)color
{
    if (color == nil) {
        return;
    }

    if (([TEXTVIEW defaultFGColor] != color) ||
       ([[TEXTVIEW defaultFGColor] alphaComponent] != [color alphaComponent])) {
        // Change the fg color for future stuff
        [TEXTVIEW setFGColor: color];
    }
}

- (NSColor *)backgroundColor
{
    return [TEXTVIEW defaultBGColor];
}

- (void)setBackgroundColor:(NSColor*) color {
    if (color == nil) {
        return;
    }

    if (([TEXTVIEW defaultBGColor] != color) ||
        ([[TEXTVIEW defaultBGColor] alphaComponent] != [color alphaComponent])) {
        // Change the bg color for future stuff
        [TEXTVIEW setBGColor: color];
    }

    [[self SCROLLVIEW] setBackgroundColor: color];
}

- (NSColor *) boldColor
{
    return [TEXTVIEW defaultBoldColor];
}

- (void)setBoldColor:(NSColor*)color
{
    [[self TEXTVIEW] setBoldColor: color];
}

- (NSColor *)cursorColor
{
    return [TEXTVIEW defaultCursorColor];
}

- (void)setCursorColor:(NSColor*)color
{
    [[self TEXTVIEW] setCursorColor: color];
}

- (void)setSmartCursorColor:(BOOL)value
{
    [[self TEXTVIEW] setSmartCursorColor:value];
}

- (void)setMinimumContrast:(float)value
{
    [[self TEXTVIEW] setMinimumContrast:value];
}

- (NSColor *)selectionColor
{
    return [TEXTVIEW selectionColor];
}

- (void)setSelectionColor:(NSColor *)color
{
    [TEXTVIEW setSelectionColor:color];
}

- (NSColor *)selectedTextColor
{
    return [TEXTVIEW selectedTextColor];
}

- (void)setSelectedTextColor:(NSColor *)aColor
{
    [TEXTVIEW setSelectedTextColor: aColor];
}

- (NSColor *)cursorTextColor
{
    return [TEXTVIEW cursorTextColor];
}

- (void)setCursorTextColor:(NSColor *)aColor
{
    [TEXTVIEW setCursorTextColor: aColor];
}

// Changes transparency

- (float)transparency
{
    return [TEXTVIEW transparency];
}

- (void)setTransparency:(float)transparency
{
    // Limit transparency because fully transparent windows can't be clicked on.
    if (transparency > 0.9) {
        transparency = 0.9;
    }

    // set transparency of background image
    [SCROLLVIEW setTransparency:transparency];
    [TEXTVIEW setTransparency:transparency];
}

- (void)setColorTable:(int)theIndex color:(NSColor *)theColor
{
    [TEXTVIEW setColorTable:theIndex color:theColor];
}

- (BOOL)antiIdle
{
    return antiIdleTimer ? YES : NO;
}

- (int)antiCode
{
    return ai_code;
}

- (void)setAntiIdle:(BOOL)set
{
    if (set == [self antiIdle]) {
        return;
    }

    if (set) {
        antiIdleTimer = [[NSTimer scheduledTimerWithTimeInterval:30
                                                          target:self
                                                        selector:@selector(doAntiIdle)
                                                        userInfo:nil
                repeats:YES] retain];
    } else {
        [antiIdleTimer invalidate];
        [antiIdleTimer release];
        antiIdleTimer = nil;
    }
}

- (void)setAntiCode:(int)code
{
    ai_code = code;
}

- (BOOL)autoClose
{
    return autoClose;
}

- (void)setAutoClose:(BOOL)set
{
    autoClose = set;
}

- (BOOL)useBoldFont
{
    return [TEXTVIEW useBoldFont];
}

- (void)setUseBoldFont:(BOOL)boldFlag
{
    [TEXTVIEW setUseBoldFont:boldFlag];
}

- (BOOL)doubleWidth
{
    return doubleWidth;
}

- (void)setDoubleWidth:(BOOL)set
{
    doubleWidth = set;
}

- (BOOL)xtermMouseReporting
{
    return xtermMouseReporting;
}

- (void)setXtermMouseReporting:(BOOL)set
{
    xtermMouseReporting = set;
}


- (BOOL)logging
{
    return [SHELL logging];
}

- (void)logStart
{
    NSSavePanel *panel;
    int sts;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession logStart:%@]",
          __FILE__, __LINE__);
#endif
    panel = [NSSavePanel savePanel];
    sts = [panel runModalForDirectory:NSHomeDirectory() file:@""];
    if (sts == NSOKButton) {
        BOOL logsts = [SHELL loggingStartWithPath:[panel filename]];
        if (logsts == NO) {
            NSBeep();
        }
    }
}

- (void)logStop
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession logStop:%@]",
          __FILE__, __LINE__);
#endif
    [SHELL loggingStop];
}

- (void)clearBuffer
{
    //char formFeed = 0x0c; // ^L
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession clearBuffer:...]", __FILE__, __LINE__);
#endif
    //[TERMINAL cleanStream];

    [SCREEN clearBuffer];
    // tell the shell to clear the screen
    //[self writeTask:[NSData dataWithBytes:&formFeed length:1]];
}

- (void)clearScrollbackBuffer
{
    [SCREEN clearScrollbackBuffer];
}

- (BOOL)exited
{
    return EXIT;
}

- (BOOL)shouldSendEscPrefixForModifier:(unsigned int)modmask
{
    if ([self optionKey] == OPT_ESC) {
        if ((modmask & NSLeftAlternateKeyMask) == NSLeftAlternateKeyMask) {
            return YES;
        }
    }
    if ([self rightOptionKey] == OPT_ESC) {
        if ((modmask & NSRightAlternateKeyMask) == NSRightAlternateKeyMask) {
            return YES;
        }
    }
    return NO;
}

- (int)optionKey
{
    return [[[self addressBookEntry] objectForKey:KEY_OPTION_KEY_SENDS] intValue];
}

- (int)rightOptionKey
{
    NSNumber* rightOptPref = [[self addressBookEntry] objectForKey:KEY_RIGHT_OPTION_KEY_SENDS];
    if (rightOptPref == nil) {
        return [self optionKey];
    }
    return [rightOptPref intValue];
}

- (void)setAddressBookEntry:(NSDictionary*)entry
{
    if (!originalAddressBookEntry) {
        originalAddressBookEntry = [NSDictionary dictionaryWithDictionary:entry];
        [originalAddressBookEntry retain];
    }
    [addressBookEntry release];
    addressBookEntry = [entry retain];
}

- (NSDictionary *)addressBookEntry
{
    return addressBookEntry;
}

- (NSDictionary *)originalAddressBookEntry
{
    return originalAddressBookEntry;
}

- (iTermGrowlDelegate*)growlDelegate
{
    return gd;
}

- (void)sendCommand:(NSString *)command
{
    NSData *data = nil;
    NSString *aString = nil;

    if (command != nil) {
        aString = [NSString stringWithFormat:@"%@\n", command];
        data = [aString dataUsingEncoding: [TERMINAL encoding]];
    }

    if (data != nil) {
        [self writeTask:data];
    }
}

- (NSDictionary*)arrangement
{
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:3];
    [result setObject:[NSNumber numberWithInt:[SCREEN width]] forKey:SESSION_ARRANGEMENT_COLUMNS];
    [result setObject:[NSNumber numberWithInt:[SCREEN height]] forKey:SESSION_ARRANGEMENT_ROWS];
    [result setObject:addressBookEntry forKey:SESSION_ARRANGEMENT_BOOKMARK];
    NSString* pwd = [SHELL getWorkingDirectory];
    [result setObject:pwd ? pwd : @"" forKey:SESSION_ARRANGEMENT_WORKING_DIRECTORY];
    return result;
}

- (void)updateScroll
{
    if (![(PTYScroller*)([SCROLLVIEW verticalScroller]) userScroll]) {
        [TEXTVIEW scrollEnd];
    }
}

static long long timeInTenthsOfSeconds(struct timeval t)
{
    return t.tv_sec * 10 + t.tv_usec / 100000;
}

- (void)updateDisplay
{
    timerRunning_ = YES;
    BOOL isForegroundTab = [[self tab] isForegroundTab];
    if (!isForegroundTab) {
        // Set color, other attributes of a background tab.
        [[self tab] setLabelAttributes];
    }
    if ([[self tab] activeSession] == self) {
        // Update window info for the active tab.
        struct timeval now;
        gettimeofday(&now, NULL);
        if (!jobName_ ||
            timeInTenthsOfSeconds(now) >= timeInTenthsOfSeconds(lastUpdate) + 7) {
            // It has been more than 700ms since the last time we were here or
            // the job doesn't ahve a name
            if (isForegroundTab && [[[self tab] parentWindow] tempTitle]) {
                // Revert to the permanent tab title.
                [[[self tab] parentWindow] setWindowTitle];
                [[[self tab] parentWindow] resetTempTitle];
            } else {
                // Update the job name in the tab title.
                NSString* oldName = jobName_;
                jobName_ = [[SHELL currentJob:NO] copy];
                [jobName_ retain];
                if (![oldName isEqualToString:jobName_]) {
                    [[self tab] nameOfSession:self didChangeTo:[self name]];
                    [[[self tab] parentWindow] setWindowTitle];
                }
                [oldName release];
            }
            lastUpdate = now;
        }
    }

    [TEXTVIEW refresh];
    [self updateScroll];

    if ([[[self tab] parentWindow] currentTab] == [self tab]) {
        [self scheduleUpdateIn:kBlinkTimerIntervalSec];
    } else {
        [self scheduleUpdateIn:kBackgroundSessionIntervalSec];
    }
    timerRunning_ = NO;
}

- (void)scheduleUpdateIn:(NSTimeInterval)timeout
{
    float kEpsilon = 0.001;
    if (!timerRunning_ &&
        [updateTimer isValid] &&
        [[updateTimer userInfo] floatValue] - (float)timeout < kEpsilon) {
        // An update of at least the current frequency is already scheduled. Let
        // it run to avoid pushing it back repeatedly (which prevents it from firing).
        return;
    }

    [updateTimer invalidate];
    [updateTimer release];

    updateTimer = [[NSTimer scheduledTimerWithTimeInterval:timeout
                                                    target:self
                                                  selector:@selector(updateDisplay)
                                                  userInfo:[NSNumber numberWithFloat:(float)timeout]
                                                   repeats:NO] retain];
}

- (void)doAntiIdle
{
    struct timeval now;
    gettimeofday(&now, NULL);

    if (now.tv_sec >= lastInput.tv_sec+60) {
        [SHELL writeTask:[NSData dataWithBytes:&ai_code length:1]];
        lastInput = now;
    }
}

- (BOOL)canInstantReplayPrev
{
    if (dvrDecoder_) {
        return [dvrDecoder_ timestamp] != [dvr_ firstTimeStamp];
    } else {
        return YES;
    }
}

- (BOOL)canInstantReplayNext
{
    if (dvrDecoder_) {
        return YES;
    } else {
        return NO;
    }
}

- (int)rows
{
    return [SCREEN height];
}

- (int)columns
{
    return [SCREEN width];
}

- (NSFont*)fontWithRelativeSize:(int)dir from:(NSFont*)font
{
    int newSize = [font pointSize] + dir;
    if (newSize < 2) {
        newSize = 2;
    }
    if (newSize > 200) {
        newSize = 200;
    }
    return [NSFont fontWithName:[font fontName] size:newSize];
}

- (void)setFont:(NSFont*)font nafont:(NSFont*)nafont horizontalSpacing:(float)horizontalSpacing verticalSpacing:(float)verticalSpacing
{
    if ([[TEXTVIEW font] isEqualTo:font] &&
        [[TEXTVIEW nafont] isEqualTo:nafont] &&
        [TEXTVIEW horizontalSpacing] == horizontalSpacing &&
        [TEXTVIEW verticalSpacing] == verticalSpacing) {
        return;
    }
    [TEXTVIEW setFont:font nafont:nafont horizontalSpacing:horizontalSpacing verticalSpacing:verticalSpacing];
    if (![[[self tab] parentWindow] fullScreen]) {
        [[[self tab] parentWindow] fitWindowToTab:[self tab]];
    }
    // If the window isn't able to adjust, or adjust enough, make the session
    // work with whatever size we ended up having.
    [[self tab] fitSessionToCurrentViewSize:self];
}

- (void)setIgnoreResizeNotifications:(BOOL)ignore
{
    ignoreResizeNotifications_ = ignore;
}

- (BOOL)ignoreResizeNotifications
{
    return ignoreResizeNotifications_;
}

- (void)changeFontSizeDirection:(int)dir
{
    NSFont* font = [self fontWithRelativeSize:dir from:[TEXTVIEW font]];
    NSFont* nafont = [self fontWithRelativeSize:dir from:[TEXTVIEW nafont]];
    [self setFont:font nafont:nafont horizontalSpacing:[TEXTVIEW horizontalSpacing] verticalSpacing:[TEXTVIEW verticalSpacing]];

    // Move this bookmark into the sessions model.
    NSString* guid = [self divorceAddressBookEntryFromPreferences];

    // Set the font in the bookmark dictionary
    NSMutableDictionary* temp = [NSMutableDictionary dictionaryWithDictionary:addressBookEntry];
    [temp setObject:[ITAddressBookMgr descFromFont:font] forKey:KEY_NORMAL_FONT];
    [temp setObject:[ITAddressBookMgr descFromFont:nafont] forKey:KEY_NON_ASCII_FONT];

    // Update this session's copy of the bookmark
    [self setAddressBookEntry:[NSDictionary dictionaryWithDictionary:temp]];

    // Update the model's copy of the bookmark.
    [[BookmarkModel sessionsInstance] setBookmark:[self addressBookEntry] withGuid:guid];

    // Update an existing one-bookmark prefs dialog, if open.
    if ([[[PreferencePanel sessionsInstance] window] isVisible]) {
        [[PreferencePanel sessionsInstance] underlyingBookmarkDidChange];
    }
}

- (NSString*)divorceAddressBookEntryFromPreferences
{
    Bookmark* bookmark = [self addressBookEntry];
    NSString* guid = [bookmark objectForKey:KEY_GUID];
    if (isDivorced) {
        return guid;
    }
    isDivorced = YES;
    [[BookmarkModel sessionsInstance] removeBookmarkWithGuid:guid];
    [[BookmarkModel sessionsInstance] addBookmark:bookmark];

    // Change the GUID so that this session can follow a different path in life
    // than its bookmark. Changes to the bookmark will no longer affect this
    // session, and changes to this session won't affect its originating bookmark
    // (which may not evene exist any longer).
    bookmark = [[BookmarkModel sessionsInstance] setObject:guid
                                                    forKey:KEY_ORIGINAL_GUID
                                                inBookmark:bookmark];
    guid = [BookmarkModel freshGuid];
    [[BookmarkModel sessionsInstance] setObject:guid
                                         forKey:KEY_GUID
                                     inBookmark:bookmark];
    [self setAddressBookEntry:[[BookmarkModel sessionsInstance] bookmarkWithGuid:guid]];
    return guid;
}

- (NSString*)jobName
{
    return jobName_;
}

- (NSString*)uncachedJobName
{
    return [SHELL currentJob:YES];
}

- (void)setLastActiveAt:(NSDate*)date
{
    [lastActiveAt_ release];
    lastActiveAt_ = [date copy];
}

- (NSDate*)lastActiveAt
{
    return lastActiveAt_;
}

// Save the current scroll position
- (void)saveScrollPosition
{
    savedScrollPosition_ = [TEXTVIEW absoluteScrollPosition];
}

// Jump to the saved scroll position
- (void)jumpToSavedScrollPosition
{
    assert(savedScrollPosition_ != -1);
    if (savedScrollPosition_ < [SCREEN totalScrollbackOverflow]) {
        NSBeep();
    } else {
        [TEXTVIEW scrollToAbsoluteOffset:savedScrollPosition_];
    }
}

// Is there a saved scroll position?
- (BOOL)hasSavedScrollPosition
{
    return savedScrollPosition_ != -1;
}

- (void)findWithSelection
{
    if ([TEXTVIEW selectedText]) {
        [[view findViewController] findString:[TEXTVIEW selectedText]];
    }
}

- (void)toggleFind
{
    [[view findViewController] toggleVisibility];
}

- (void)searchNext
{
    [[view findViewController] searchNext];
}

- (void)searchPrevious
{
    [[view findViewController] searchPrevious];
}

- (void)resetFindCursor
{
    [TEXTVIEW resetFindCursor];
}

- (BOOL)findInProgress
{
    return [TEXTVIEW findInProgress];
}

- (BOOL)continueFind
{
    return [TEXTVIEW continueFind];
}

- (BOOL)growSelectionLeft
{
    return [TEXTVIEW growSelectionLeft];
}

- (void)growSelectionRight
{
    [TEXTVIEW growSelectionRight];
}

- (NSString*)selectedText
{
    return [TEXTVIEW selectedText];
}

- (NSString*)unpaddedSelectedText
{
    return [TEXTVIEW selectedTextWithPad:NO];
}

- (void)copySelection
{
    return [TEXTVIEW copy:self];
}

- (void)takeFocus
{
    [[[[self tab] realParentWindow] window] makeFirstResponder:TEXTVIEW];
}

- (void)clearHighlights
{
    [TEXTVIEW clearHighlights];
}

@end

@implementation PTYSession (ScriptingSupport)

// Object specifier
- (NSScriptObjectSpecifier *)objectSpecifier
{
    NSUInteger theIndex = 0;
    id classDescription = nil;

    NSScriptObjectSpecifier *containerRef = nil;
    if (![[self tab] realParentWindow]) {
        // TODO(georgen): scripting is broken while in instant replay.
        return nil;
    }
    // TODO: Test this with multiple panes per tab.
    theIndex = [[[[self tab] realParentWindow] tabView] indexOfTabViewItem:[[self tab] tabViewItem]];

    if (theIndex != NSNotFound) {
        containerRef = [[[self tab] realParentWindow] objectSpecifier];
        classDescription = [containerRef keyClassDescription];
        //create and return the specifier
        return [[[NSIndexSpecifier allocWithZone:[self zone]]
               initWithContainerClassDescription: classDescription
                              containerSpecifier: containerRef
                                             key: @ "sessions"
                                           index: theIndex] autorelease];
    } else {
        // NSLog(@"recipient not found!");
        return nil;
    }

}

// Handlers for supported commands:
-(void)handleExecScriptCommand:(NSScriptCommand *)aCommand
{
    // if we are already doing something, get out.
    if ([SHELL pid] > 0) {
        NSBeep();
        return;
    }

    // Get the command's arguments:
    NSDictionary *args = [aCommand evaluatedArguments];
    NSString *command = [args objectForKey:@"command"];
    BOOL isUTF8 = [[args objectForKey:@"isUTF8"] boolValue];

    NSString *cmd;
    NSArray *arg;

    [PseudoTerminal breakDown:command cmdPath:&cmd cmdArgs:&arg];
    [self startProgram:cmd arguments:arg environment:[NSDictionary dictionary] isUTF8:isUTF8 asLoginSession:NO];

    return;
}

-(void)handleSelectScriptCommand:(NSScriptCommand *)command
{
    [[[[self tab] parentWindow] tabView] selectTabViewItemWithIdentifier:[self tab]];
}

-(void)handleWriteScriptCommand: (NSScriptCommand *)command
{
    // Get the command's arguments:
    NSDictionary *args = [command evaluatedArguments];
    // optional argument follows (might be nil):
    NSString *contentsOfFile = [args objectForKey:@"contentsOfFile"];
    // optional argument follows (might be nil):
    NSString *text = [args objectForKey:@"text"];
    NSData *data = nil;
    NSString *aString = nil;

    if (text != nil) {
        if ([text characterAtIndex:[text length]-1]==' ') {
            data = [text dataUsingEncoding:[TERMINAL encoding]];
        } else {
            aString = [NSString stringWithFormat:@"%@\n", text];
            data = [aString dataUsingEncoding:[TERMINAL encoding]];
        }
    }

    if (contentsOfFile != nil) {
        aString = [NSString stringWithContentsOfFile:contentsOfFile];
        data = [aString dataUsingEncoding:[TERMINAL encoding]];
    }

    if (data != nil && [SHELL pid] > 0) {
        int i = 0;
        // wait here until we have had some output
        while ([SHELL hasOutput] == NO && i < 1000000) {
            usleep(50000);
            i += 50000;
        }

        [self writeTask:data];
    }
}


- (void)handleTerminateScriptCommand:(NSScriptCommand *)command
{
    [[self tab] closeSession:self];
}

@end

@implementation PTYSession (Private)

- (NSString*)encodingName
{
    // Get the encoding, perhaps as a fully written out name.
    CFStringEncoding cfEncoding = CFStringConvertNSStringEncodingToEncoding([self encoding]);
    // Convert it to the expected (IANA) format.
    NSString* ianaEncoding = (NSString*)CFStringConvertEncodingToIANACharSetName(cfEncoding);
    
    // Fix up lowercase letters.
    static NSDictionary* lowerCaseEncodings;
    if (!lowerCaseEncodings) {
        NSString* plistFile = [[NSBundle bundleForClass: [self class]] pathForResource:@"EncodingsWithLowerCase" ofType:@"plist"];
        lowerCaseEncodings = [NSDictionary dictionaryWithContentsOfFile:plistFile];
        [lowerCaseEncodings retain];
    }
    if ([ianaEncoding rangeOfCharacterFromSet:[NSCharacterSet lowercaseLetterCharacterSet]].length) {
        // Some encodings are improperly returned as lower case. For instance,
        // "utf-8" instead of "UTF-8". If this isn't in the allowed list of
        // lower-case encodings, then uppercase it.
        if (lowerCaseEncodings) {
            if (![lowerCaseEncodings objectForKey:ianaEncoding]) {
                ianaEncoding = [ianaEncoding uppercaseString];
            }
        }
    }
    
    if (ianaEncoding != nil) {
        // Mangle the names slightly
        NSMutableString* encoding = [[[NSMutableString alloc] initWithString:ianaEncoding] autorelease];
        [encoding replaceOccurrencesOfString:@"ISO-" withString:@"ISO" options:0 range:NSMakeRange(0, [encoding length])];
        [encoding replaceOccurrencesOfString:@"EUC-" withString:@"euc" options:0 range:NSMakeRange(0, [encoding length])];
        return encoding;
    }

    return nil;
}

- (NSString*)_getLocale
{
    NSString* theLocale = nil;
    NSString* languageCode = [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode];
    NSString* countryCode = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
    if (languageCode && countryCode) {
        theLocale = [NSString stringWithFormat:@"%@_%@", languageCode, countryCode];
    }
    return theLocale;
}

- (BOOL)_localeIsSupported:(NSString*)theLocale
{
    // Keep a copy of the current locale setting for this process
    char* backupLocale = setlocale(LC_CTYPE, NULL);

    // Try to set it to the proposed locale
    BOOL supported;
    if (setlocale(LC_CTYPE, [theLocale UTF8String])) {
        supported = YES;
    } else {
        supported = NO;
    }

    // Restore locale and return
    setlocale(LC_CTYPE, backupLocale);
    return supported;
}

- (NSString*)_lang
{
    NSString* theLocale = [self _getLocale];
    NSString* encoding = [self encodingName];
    if (encoding && theLocale) {
        NSString* result = [NSString stringWithFormat:@"%@.%@", theLocale, encoding];
        if ([self _localeIsSupported:result]) {
            return result;
        } else {
            return nil;
        }
    } else {
        return nil;
    }
}

- (void)setDvrFrame
{
    screen_char_t* s = (screen_char_t*)[dvrDecoder_ decodedFrame];
    int len = [dvrDecoder_ length];
    DVRFrameInfo info = [dvrDecoder_ info];
    if (info.width != [SCREEN width] || info.height != [SCREEN height]) {
        [[[self tab] realParentWindow] sessionInitiatedResize:self
                                                        width:info.width
                                                       height:info.height];
    }
    [SCREEN setFromFrame:s len:len info:info];
    [[[self tab] realParentWindow] resetTempTitle];
    [[[self tab] realParentWindow] setWindowTitle];
}

@end
