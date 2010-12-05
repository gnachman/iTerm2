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
    return (self);
}

- (void)dealloc
{
#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif
    [slowPasteBuffer release];
    if (slowPasteTimer) {
        [slowPasteTimer invalidate];
    }
    [TERM_VALUE release];
    [COLORFGBG_VALUE release];
    [view release];
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

// Session specific methods
- (BOOL)setScreenSize:(NSRect)aRect parent:(id<WindowControllerInterface>)parent
{
    NSSize aSize;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession setScreenSize:parent:]", __FILE__, __LINE__);
#endif

    [SCREEN setSession:self];

    // Allocate a container to hold the scrollview
    view = [[SessionView alloc] initWithFrame:NSMakeRect(0, 0, aRect.size.width, aRect.size.height)
                                      session:self];
    [view retain];

    // Allocate a scrollview
    SCROLLVIEW = [[PTYScrollView alloc] initWithFrame: NSMakeRect(0, 0, aRect.size.width, aRect.size.height)];
    [SCROLLVIEW setHasVerticalScroller:(![parent fullScreen] &&
                                        ![[PreferencePanel sharedInstance] hideScrollbar])];
    NSParameterAssert(SCROLLVIEW != nil);
    [SCROLLVIEW setAutoresizingMask: NSViewWidthSizable|NSViewHeightSizable];

    // assign the main view
    [view addSubview:SCROLLVIEW];
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
    aSize = [SCROLLVIEW contentSize];
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
    int width = aRect.size.width / [TEXTVIEW charWidth];
    int height = aRect.size.height / [TEXTVIEW lineHeight];
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

        // register for some notifications
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tabViewWillRedraw:)
                                                     name:@"iTermTabViewWillRedraw"
                                                   object:nil];

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

- (void)setWidth:(int)width height:(int)height
{
    [SCREEN resizeWidth:width height:height];
    [SHELL setWidth:width height:height];
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

    NSString* locale = [self _getLocale];
    if (locale) {
        [env setObject:locale forKey:@"LANG"];
    }

    if ([env objectForKey:PWD_ENVNAME] == nil)
        [env setObject:[PWD_ENVVALUE stringByExpandingTildeInPath] forKey:PWD_ENVNAME];

    [SHELL launchWithPath:path
                arguments:argv
              environment:env
                    width:[SCREEN width]
                   height:[SCREEN height]
                   isUTF8:isUTF8
    ];

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

    [addressBookEntry release];
    addressBookEntry = nil;

    [TEXTVIEW setDataSource: nil];
    [TEXTVIEW setDelegate: nil];
    [TEXTVIEW removeFromSuperview];

    [SHELL setDelegate:nil];
    [SCREEN setShellTask:nil];
    [SCREEN setSession: nil];
    [SCREEN setTerminal: nil];
    [TERMINAL setScreen: nil];

    [updateTimer invalidate];
    [updateTimer release];
    updateTimer = nil;
}

- (void)writeTask:(NSData*)data
{
    // check if we want to send this input to all the sessions
    id<WindowControllerInterface> parent = [[self tab] parentWindow];
    if ([parent sendInputToAllSessions] == NO) {
        if (!EXIT) {
            [self setBell: NO];
            PTYScroller* ptys=(PTYScroller*)[SCROLLVIEW verticalScroller];
            [SHELL writeTask: data];
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
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession brokenPipe]", __FILE__, __LINE__);
#endif
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

    EXIT=YES;
    [[self tab] setLabelAttributes];

    if ([self autoClose]) {
        [[self tab] closeSession:self];
    } else {
        [self updateDisplay];
    }
}

- (BOOL)hasKeyMappingForEvent:(NSEvent *)event highPriority:(BOOL)priority
{
    unsigned int modflag;
    NSString *unmodkeystr;
    unichar unmodunicode;
    int keyBindingAction;
    NSString *keyBindingText;
    BOOL keyBindingPriority;

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
                                               highPriority:&keyBindingPriority
                                                       text:&keyBindingText
                                                keyMappings:[[self addressBookEntry] objectForKey: KEY_KEYBOARD_MAP]];


    return (keyBindingAction >= 0);
}

// Screen for special keys
- (void)keyDown:(NSEvent *)event
{
    unsigned char *send_str = NULL;
    unsigned char *dataPtr = NULL;
    int dataLength = 0;
    size_t send_strlen = 0;
    int send_pchr = -1;
    int keyBindingAction;
    NSString *keyBindingText;
    BOOL priority;

    unsigned int modflag;
    NSString *keystr;
    NSString *unmodkeystr;
    unichar unicode, unmodunicode;

#if DEBUG_METHOD_TRACE || DEBUG_KEYDOWNDUMP
    NSLog(@"%s(%d):-[PTYSession keyDown:%@]",
          __FILE__, __LINE__, event);
#endif

    if (EXIT) {
      return;
    }

    modflag = [event modifierFlags];
    keystr  = [event characters];
    unmodkeystr = [event charactersIgnoringModifiers];
    unicode = [keystr length]>0?[keystr characterAtIndex:0]:0;
    unmodunicode = [unmodkeystr length]>0?[unmodkeystr characterAtIndex:0]:0;

    gettimeofday(&lastInput, NULL);

    /*
    unsigned short keycode = [event keyCode];
    NSLog(@"event:%@ (%x+%x)[%@][%@]:%x(%c) <%d>", event,modflag,keycode,keystr,unmodkeystr,unicode,unicode,(modflag & NSNumericPadKeyMask));
    */

    // Check if we have a custom key mapping for this event
    keyBindingAction = [iTermKeyBindingMgr actionForKeyCode:unmodunicode
                                                  modifiers:modflag
                                               highPriority:&priority
                                                       text:&keyBindingText
                                                keyMappings:[[self addressBookEntry] objectForKey:KEY_KEYBOARD_MAP]];

    if (keyBindingAction >= 0) {
        // A special action was bound to this key combination.
        NSString *aString;
        unsigned char hexCode;
        int hexCodeTmp;

        switch (keyBindingAction) {
            case KEY_ACTION_NEXT_SESSION:
                [[[self tab] parentWindow] nextSession: nil];
                break;
            case KEY_ACTION_NEXT_WINDOW:
                [[iTermController sharedInstance] nextTerminal: nil];
                break;
            case KEY_ACTION_PREVIOUS_SESSION:
                [[[self tab] parentWindow] previousSession: nil];
                break;
            case KEY_ACTION_PREVIOUS_WINDOW:
                [[iTermController sharedInstance] previousTerminal: nil];
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
                [TEXTVIEW scrollLineDown: self];
                [(PTYScrollView *)[TEXTVIEW enclosingScrollView] detectUserScroll];
                break;
            case KEY_ACTION_SCROLL_LINE_UP:
                [TEXTVIEW scrollLineUp: self];
                [(PTYScrollView *)[TEXTVIEW enclosingScrollView] detectUserScroll];
                break;
            case KEY_ACTION_SCROLL_PAGE_DOWN:
                [TEXTVIEW scrollPageDown: self];
                [(PTYScrollView *)[TEXTVIEW enclosingScrollView] detectUserScroll];
                break;
            case KEY_ACTION_SCROLL_PAGE_UP:
                [TEXTVIEW scrollPageUp: self];
                [(PTYScrollView *)[TEXTVIEW enclosingScrollView] detectUserScroll];
                break;
            case KEY_ACTION_ESCAPE_SEQUENCE:
                if ([keyBindingText length] > 0) {
                    aString = [NSString stringWithFormat:@"\e%@", keyBindingText];
                    [self writeTask: [aString dataUsingEncoding: NSUTF8StringEncoding]];
                }
                break;
            case KEY_ACTION_HEX_CODE:
                if ([keyBindingText length] > 0 &&
                    sscanf([keyBindingText UTF8String], "%x", &hexCodeTmp) == 1) {
                    hexCode = (unsigned char) hexCodeTmp;
                    [self writeTask:[NSData dataWithBytes:&hexCode length: sizeof(hexCode)]];
                }
                break;
            case KEY_ACTION_TEXT:
                if([keyBindingText length] > 0) {
                    NSMutableString *bindingText = [NSMutableString stringWithString: keyBindingText];
                    [bindingText replaceOccurrencesOfString:@"\\n" withString:@"\n" options:NSLiteralSearch range:NSMakeRange(0,[bindingText length])];
                    [bindingText replaceOccurrencesOfString:@"\\e" withString:@"\e" options:NSLiteralSearch range:NSMakeRange(0,[bindingText length])];
                    [bindingText replaceOccurrencesOfString:@"\\a" withString:@"\a" options:NSLiteralSearch range:NSMakeRange(0,[bindingText length])];
                    [bindingText replaceOccurrencesOfString:@"\\t" withString:@"\t" options:NSLiteralSearch range:NSMakeRange(0,[bindingText length])];
                    [self writeTask: [bindingText dataUsingEncoding: NSUTF8StringEncoding]];
                }
                break;
            case KEY_ACTION_SEND_C_H_BACKSPACE:
                [self writeTask:[@"\010" dataUsingEncoding:NSUTF8StringEncoding]];
                break;
            case KEY_ACTION_SEND_C_QM_BACKSPACE:
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
            default:
                NSLog(@"Unknown key action %d", keyBindingAction);
                break;
        }
    } else {
        // No special binding for this key combination.
        if (modflag & NSFunctionKeyMask) {
            // Handle all "special" keys (arrows, etc.)
            NSData *data = nil;

            switch (unicode) {
                case NSUpArrowFunctionKey:
                    data = [TERMINAL keyArrowUp:modflag];
                    break;
                case NSDownArrowFunctionKey:
                    data = [TERMINAL keyArrowDown:modflag];
                    break;
                case NSLeftArrowFunctionKey:
                    data = [TERMINAL keyArrowLeft:modflag];
                    break;
                case NSRightArrowFunctionKey:
                    data = [TERMINAL keyArrowRight:modflag];
                    break;
                case NSInsertFunctionKey:
                    data = [TERMINAL keyInsert];
                    break;
                case NSDeleteFunctionKey:
                    data = [TERMINAL keyDelete];
                    break;
                case NSHomeFunctionKey:
                    data = [TERMINAL keyHome:modflag];
                    break;
                case NSEndFunctionKey:
                    data = [TERMINAL keyEnd:modflag];
                    break;
                case NSPageUpFunctionKey:
                    data = [TERMINAL keyPageUp];
                    break;
                case NSPageDownFunctionKey:
                    data = [TERMINAL keyPageDown];
                    break;
                case NSClearLineFunctionKey:
                    data = [@"\e" dataUsingEncoding: NSUTF8StringEncoding];
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
                data = [TERMINAL keypadData: unicode keystr: keystr];
            }

            if (data != nil ) {
                send_str = (unsigned char *)[data bytes];
                send_strlen = [data length];
            }

            DebugLog([NSString stringWithFormat:@"modflag = 0x%x; send_strlen = %d; send_str[0] = '%c (0x%x)'", modflag, send_strlen, send_str[0]]);
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

- (BOOL)willHandleEvent: (NSEvent *) theEvent
{
    return NO;
}

- (void)handleEvent: (NSEvent *) theEvent
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

    //    NSLog(@"insertText: %@",string);
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
    [self writeTask:[TERMINAL keyPageUp]];
}

- (void)pageDown:(id)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession pageDown:%@]",
          __FILE__, __LINE__, sender);
#endif
    [self writeTask:[TERMINAL keyPageDown]];
}

- (void)paste:(id)sender
{
    NSPasteboard *board;
    NSMutableString *str;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession paste:...]", __FILE__, __LINE__);
#endif

    board = [NSPasteboard generalPasteboard];
    NSParameterAssert(board != nil );
    str = [[[NSMutableString alloc] initWithString:[board stringForType:NSStringPboardType]] autorelease];
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
        [self pasteString: str];
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
    }
}

- (void) pasteString: (NSString *) aString
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

    [SCREEN resizeWidth:w height:h];
    [SHELL setWidth:w  height:h];

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
            if ([TEXTVIEW keyIsARepeat] == NO && ![[TEXTVIEW window] isKeyWindow]) {
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

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession setPreferencesFromAddressBookEntry:");
#endif

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
    for (i = 0; i < 8; i++) {
        colorTable[0][i] = [ITAddressBookMgr decodeColor:[aDict objectForKey:[NSString stringWithFormat:KEYTEMPLATE_ANSI_X_COLOR, i]]];
        colorTable[1][i] = [ITAddressBookMgr decodeColor:[aDict objectForKey:[NSString stringWithFormat:KEYTEMPLATE_ANSI_X_COLOR, i + 8]]];
    }
    for(i=0;i<8;i++) {
        [self setColorTable:i color:colorTable[0][i]];
        [self setColorTable:i+8 color:colorTable[1][i]];
    }
    for (i=0;i<216;++i) {
        [self setColorTable:i+16 color:[NSColor colorWithCalibratedRed:(i/36) ? ((i/36)*40+55)/256.0:0
                                                  green:(i%36)/6 ? (((i%36)/6)*40+55)/256.0:0
                                                    blue:(i%6) ?((i%6)*40+55)/256.0:0
                                                  alpha:1]];
    }
    for (i=0;i<24;++i) {
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
    [SCREEN setBlinkingCursor: [[aDict objectForKey: KEY_BLINKING_CURSOR] boolValue]];
    [TEXTVIEW setBlinkingCursor: [[aDict objectForKey: KEY_BLINKING_CURSOR] boolValue]];
    [TEXTVIEW setUseTransparency:[[aDict objectForKey:KEY_TRANSPARENCY] boolValue]];
    PTYTab* currentTab = [[[self tab] parentWindow] currentTab];
    if (currentTab == nil || currentTab == [self tab]) {
        if ([[aDict objectForKey:KEY_BLUR] boolValue]) {
            [[[self tab] parentWindow] enableBlur];
        } else {
            [[[self tab] parentWindow] disableBlur];
        }
    }
    [TEXTVIEW setAntiAlias:[[aDict objectForKey:KEY_ANTI_ALIASING] boolValue]];
    [self setEncoding:[[aDict objectForKey:KEY_CHARACTER_ENCODING] unsignedIntValue]];
    [self setTERM_VALUE:[aDict objectForKey:KEY_TERMINAL_TYPE]];
    [self setAntiCode:[[aDict objectForKey:KEY_IDLE_CODE] intValue]];
    [self setAntiIdle:[[aDict objectForKey:KEY_SEND_CODE_WHEN_IDLE] boolValue]];
    [self setAutoClose:[[aDict objectForKey:KEY_CLOSE_SESSIONS_ON_END] boolValue]];
    [self setDoubleWidth:[[aDict objectForKey:KEY_AMBIGUOUS_DOUBLE_WIDTH] boolValue]];
    [self setXtermMouseReporting:[[aDict objectForKey:KEY_XTERM_MOUSE_REPORTING] boolValue]];
    [SCREEN setScrollback:[[aDict objectForKey:KEY_SCROLLBACK_LINES] intValue]];

    [self setFont:[ITAddressBookMgr fontWithDesc:[aDict objectForKey:KEY_NORMAL_FONT]]
           nafont:[ITAddressBookMgr fontWithDesc:[aDict objectForKey:KEY_NON_ASCII_FONT]]
    horizontalSpacing:[[aDict objectForKey:KEY_HORIZONTAL_SPACING] floatValue]
  verticalSpacing:[[aDict objectForKey:KEY_VERTICAL_SPACING] floatValue]];
}

// Contextual menu
- (void)menuForEvent:(NSEvent *)theEvent menu:(NSMenu *)theMenu
{
    NSMenuItem *aMenuItem;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession menuForEvent]", __FILE__, __LINE__);
#endif

    // Clear buffer
    aMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Clear Buffer",
                                                                                     @"iTerm",
                                                                                     [NSBundle bundleForClass: [self class]],
                                                                                     @"Context menu")
                                           action:@selector(clearBuffer:)
                                    keyEquivalent:@""];
    [aMenuItem setTarget:[[self tab] parentWindow]];
    [theMenu addItem: aMenuItem];
    [aMenuItem release];

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

- (NSString*)defaultName
{
    if (jobName_) {
        return [NSString stringWithFormat:@"%@ (%@)", defaultName, [self jobName]];
    } else {
        return defaultName;
    }
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
    if (jobName_) {
        return [NSString stringWithFormat:@"%@ (%@)", name, [self jobName]];
    } else {
        return name;
    }
}

- (void)setName:(NSString*)theName
{
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
    NSString* jobName = [self jobName];
    if (jobName) {
        return [NSString stringWithFormat:@"%@ (%@)", windowTitle, [self jobName]];
    } else {
        return windowTitle;
    }
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
    [view autorelease];
    view = [newView retain];
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

    if ([[[self tab] parentWindow] fullScreen]) {
        transparency = 0;
    }
    // set transparency of background image
    [SCROLLVIEW setTransparency: transparency];
    [TEXTVIEW setTransparency: transparency];

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

-(void)sendCommand:(NSString *)command
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

    if (![[self tab] isForegroundTab]) {
        // Set color, other attributes of a background tab.
        [[self tab] setLabelAttributes];
    } else if ([[self tab] activeSession] == self) {
        // Update window info for the active tab.
        struct timeval now;
        gettimeofday(&now, NULL);
        if (timeInTenthsOfSeconds(now) >= timeInTenthsOfSeconds(lastUpdate) + 7) {
            // It has been more than 700ms since the last time we were here.
            if ([[[self tab] parentWindow] tempTitle]) {
                // Revert to the permanent tab title.
                [[[self tab] parentWindow] setWindowTitle];
                [[[self tab] parentWindow] resetTempTitle];
            } else {
                // Update the job name in the tab title.
                NSString* oldName = jobName_;
                jobName_ = [[SHELL currentJob] copy];
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

// Notification
- (void)tabViewWillRedraw:(NSNotification *)aNotification
{
    if ([aNotification object] == [[[self tab] tabViewItem] tabView]) {
        [TEXTVIEW setNeedsDisplay:YES];
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
    [TEXTVIEW setFont:font nafont:nafont horizontalSpacing:horizontalSpacing verticalSpacing:verticalSpacing];
    // Calling fitWindowToSession:self works but causes window size to change if self has an excess margin.
    // fitWIndowToSessions doesn't work because it may leave self too small (# rows) for the window when shrinking the font.

    // Adjust the window size to perfectly fit this session. But this may cause the excess margin to
    // be too small if another tab has a larger font.
    [[[self tab] parentWindow] fitWindowToSession:self];
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

    [self startProgram:cmd arguments:arg environment:[NSDictionary dictionary] isUTF8:isUTF8];

    return;
}

-(void)handleSelectScriptCommand:(NSScriptCommand *)command
{
    [[[[self tab] parentWindow] tabView] selectTabViewItemWithIdentifier:self];
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
            data = [text dataUsingEncoding: [TERMINAL encoding]];
        } else {
            aString = [NSString stringWithFormat:@"%@\n", text];
            data = [aString dataUsingEncoding: [TERMINAL encoding]];
        }
    }

    if (contentsOfFile != nil) {
        aString = [NSString stringWithContentsOfFile: contentsOfFile];
        data = [aString dataUsingEncoding: [TERMINAL encoding]];
    }

    if (data != nil && [SHELL pid] > 0) {
        int i = 0;
        // wait here until we have had some output
        while ([SHELL hasOutput] == NO && i < 1000000) {
            usleep(50000);
            i += 50000;
        }

        [self writeTask: data];
    }
}


- (void)handleTerminateScriptCommand:(NSScriptCommand *)command
{
    [[self tab] closeSession:self];
}

@end

@implementation PTYSession (Private)

- (NSString*)_getLocale
{
    // Keep a copy of the current locale setting for this process
    char* backupLocale = setlocale(LC_CTYPE, NULL);

    // Start with the locale
    NSString* locale = [[NSLocale currentLocale] localeIdentifier];

    // Append the encoding
    CFStringEncoding cfEncoding = CFStringConvertNSStringEncodingToEncoding([self encoding]);
    NSString* ianaEncoding = (NSString*)CFStringConvertEncodingToIANACharSetName(cfEncoding);

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
        NSMutableString* encoding = [[NSMutableString alloc] initWithString:ianaEncoding];
        [encoding replaceOccurrencesOfString:@"ISO-" withString:@"ISO" options:0 range:NSMakeRange(0, [encoding length])];
        [encoding replaceOccurrencesOfString:@"EUC-" withString:@"euc" options:0 range:NSMakeRange(0, [encoding length])];

        NSString* test = [locale stringByAppendingFormat:@".%@", encoding];
        if (NULL != setlocale(LC_CTYPE, [test UTF8String])) {
            locale = test;
        }

        [encoding release];
    }

    // Check the locale is valid
    if (NULL == setlocale(LC_CTYPE, [locale UTF8String])) {
        locale = nil;
    }

    // Restore locale and return
    setlocale(LC_CTYPE, backupLocale);
    return locale;
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
