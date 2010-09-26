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
#import <iTerm/PseudoTerminal.h>
#import <iTerm/iTermController.h>
#import <iTerm/NSStringITerm.h>
#import <iTerm/iTermKeyBindingMgr.h>
#import <iTerm/ITAddressBookMgr.h>
#import <iTerm/iTermGrowlDelegate.h>

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

// tab label attributes
static NSColor *normalStateColor;
static NSColor *chosenStateColor;
static NSColor *idleStateColor;
static NSColor *newOutputStateColor;
static NSColor *deadStateColor;

static NSImage *warningImage;

+ (void)initialize
{
    NSBundle *thisBundle;
    NSString *imagePath;

    thisBundle = [NSBundle bundleForClass: [self class]];
    imagePath = [thisBundle pathForResource:@"important" ofType:@"png"];
    if (imagePath) {
        warningImage = [[NSImage alloc] initByReferencingFile: imagePath];
        //NSLog(@"%@\n%@",imagePath,warningImage);
    }

    normalStateColor = [NSColor blackColor];
    chosenStateColor = [NSColor blackColor];
    idleStateColor = [NSColor redColor];
    newOutputStateColor = [NSColor purpleColor];
    deadStateColor = [NSColor grayColor];
}

// init/dealloc
- (id)init
{
    if ((self = [super init]) == nil) {
        return (nil);
    }

    isDivorced = NO;
    gettimeofday(&lastInput, NULL);
    lastOutput = lastBlink = lastInput;
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

    return (self);
}

- (void)dealloc
{
#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif

    [icon release];
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

    [SHELL release];
    SHELL = nil;
    [SCREEN release];
    SCREEN = nil;
    [TERMINAL release];
    TERMINAL = nil;

    [[NSNotificationCenter defaultCenter] removeObserver: self];

    [super dealloc];
#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x, done", __PRETTY_FUNCTION__, self);
#endif
}

// Session specific methods
- (BOOL)initScreen:(NSRect)aRect vmargin:(float)vmargin
{
    NSSize aSize;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession initScreen]", __FILE__, __LINE__);
#endif

    [SCREEN setSession:self];

    // Allocate a container to hold the scrollview
    view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, aRect.size.width, aRect.size.height)];
    [view retain];

    // Allocate a scrollview
    SCROLLVIEW = [[PTYScrollView alloc] initWithFrame: NSMakeRect(0, 0, aRect.size.width, aRect.size.height - vmargin)];
    [SCROLLVIEW setHasVerticalScroller:![parent fullScreen] && ![[PreferencePanel sharedInstance] hideScrollbar]];
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
    TEXTVIEW = [[PTYTextView alloc] initWithFrame: NSMakeRect(0, 0, aSize.width, aSize.height)];
    [TEXTVIEW setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [TEXTVIEW setFont:[ITAddressBookMgr fontWithDesc:[addressBookEntry objectForKey:KEY_NORMAL_FONT]]
               nafont:[ITAddressBookMgr fontWithDesc:[addressBookEntry objectForKey:KEY_NON_ASCII_FONT]]
    horizontalSpacing:[[addressBookEntry objectForKey:KEY_HORIZONTAL_SPACING] floatValue]
      verticalSpacing:[[addressBookEntry objectForKey:KEY_VERTICAL_SPACING] floatValue]];
    [self setTransparency:[[addressBookEntry objectForKey:KEY_TRANSPARENCY] floatValue]];

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
        [SCROLLVIEW setDocumentView:TEXTVIEW];
        [TEXTVIEW release];
        [SCROLLVIEW setDocumentCursor: [PTYTextView textViewCursor]];
        [SCROLLVIEW setLineScroll:[TEXTVIEW lineHeight]];
        [SCROLLVIEW setPageScroll:2*[TEXTVIEW lineHeight]];
        [SCROLLVIEW setHasVerticalScroller:![parent fullScreen] && ![[PreferencePanel sharedInstance] hideScrollbar]];


        ai_code=0;
        [antiIdleTimer release];
        antiIdleTimer = nil;
        newOutput = NO;

        // register for some notifications
        [[NSNotificationCenter defaultCenter] addObserver:self
                selector:@selector(tabViewWillRedraw:)
                name:@"iTermTabViewWillRedraw" object:nil];

        return YES;
    }
    else {
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

- (BOOL) isActiveSession
{
    return ([[[self tabViewItem] tabView] selectedTabViewItem] == [self tabViewItem]);
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

#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4
    NSString* locale = [self _getLocale];
    if (locale != nil) {
        [env setObject:locale forKey:@"LANG"];
        [env setObject:locale forKey:@"LC_COLLATE"];
        [env setObject:locale forKey:@"LC_CTYPE"];
        [env setObject:locale forKey:@"LC_MESSAGES"];
        [env setObject:locale forKey:@"LC_MONETARY"];
        [env setObject:locale forKey:@"LC_NUMERIC"];
        [env setObject:locale forKey:@"LC_TIME"];
    }
#endif
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


- (void) terminate
{
    // deregister from the notification center
    [[NSNotificationCenter defaultCenter] removeObserver:self];

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

    parent = nil;
}

- (void)writeTask:(NSData*)data
{
    // check if we want to send this input to all the sessions
    if ([parent sendInputToAllSessions] == NO) {
        if (!EXIT) {
            [self setBell: NO];
            PTYScroller* ptys=(PTYScroller*)[SCROLLVIEW verticalScroller];
            [SHELL writeTask: data];
            [ptys setUserScroll:NO];
        }
    }
    else {
        // send to all sessions
        [parent sendInputToAllSessions: data];
    }
}

- (void)readTask:(NSData*)data
{
    if ([data length] == 0 || EXIT) {
        return;
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
    newOutput=YES;

    // Make sure the screen gets redrawn soonish
    [self scheduleUpdateSoon:YES];
}

- (void)brokenPipe
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYSession brokenPipe]", __FILE__, __LINE__);
#endif
    [gd growlNotify:NSLocalizedStringFromTableInBundle(@"Broken Pipe",@"iTerm", [NSBundle bundleForClass: [self class]], @"Growl Alerts")
    withDescription:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Session %@ #%d just terminated.",@"iTerm", [NSBundle bundleForClass: [self class]], @"Growl Alerts"),[self name],[self realObjectCount]]
    andNotification:@"Broken Pipes"];

    EXIT=YES;
    [self setLabelAttribute];

    if ([self autoClose]) {
        [parent closeSession: self];
    }
    else
    {
        [self updateDisplay];
    }
}

- (BOOL) hasKeyMappingForEvent: (NSEvent *) event highPriority: (BOOL) priority
{
    unsigned int modflag;
    unsigned short keycode;
    NSString *keystr;
    NSString *unmodkeystr;
    unichar unicode, unmodunicode;
    int keyBindingAction;
    NSString *keyBindingText;
    BOOL keyBindingPriority;

    modflag = [event modifierFlags];
    keycode = [event keyCode];
    keystr  = [event characters];
    unmodkeystr = [event charactersIgnoringModifiers];
    unicode = [keystr length]>0?[keystr characterAtIndex:0]:0;
    unmodunicode = [unmodkeystr length]>0?[unmodkeystr characterAtIndex:0]:0;

    //NSLog(@"event:%@ (%x+%x)[%@][%@]:%x(%c) <%d>", event,modflag,keycode,keystr,unmodkeystr,unicode,unicode,(modflag & NSNumericPadKeyMask));

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
    unsigned short keycode;
    NSString *keystr;
    NSString *unmodkeystr;
    unichar unicode, unmodunicode;

#if DEBUG_METHOD_TRACE || DEBUG_KEYDOWNDUMP
    NSLog(@"%s(%d):-[PseudoTerminal keyDown:%@]",
          __FILE__, __LINE__, event);
#endif

    if (EXIT) return;

    modflag = [event modifierFlags];
    keycode = [event keyCode];
    keystr  = [event characters];
    unmodkeystr = [event charactersIgnoringModifiers];
    unicode = [keystr length]>0?[keystr characterAtIndex:0]:0;
    unmodunicode = [unmodkeystr length]>0?[unmodkeystr characterAtIndex:0]:0;

    gettimeofday(&lastInput, NULL);

    //NSLog(@"event:%@ (%x+%x)[%@][%@]:%x(%c) <%d>", event,modflag,keycode,keystr,unmodkeystr,unicode,unicode,(modflag & NSNumericPadKeyMask));

    // Check if we have a custom key mapping for this event
    keyBindingAction = [iTermKeyBindingMgr actionForKeyCode:unmodunicode
                                                  modifiers:modflag
                                               highPriority:&priority
                                                       text:&keyBindingText
                                                keyMappings:[[self addressBookEntry] objectForKey:KEY_KEYBOARD_MAP]];

    if (keyBindingAction >= 0) {
        NSString *aString;
        unsigned char hexCode;
        int hexCodeTmp;

        switch (keyBindingAction)
        {
            case KEY_ACTION_NEXT_SESSION:
                [parent nextSession: nil];
                break;
            case KEY_ACTION_NEXT_WINDOW:
                [[iTermController sharedInstance] nextTerminal: nil];
                break;
            case KEY_ACTION_PREVIOUS_SESSION:
                [parent previousSession: nil];
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
            case KEY_ACTION_IGNORE:
                break;
            default:
                NSLog(@"Unknown key action %d", keyBindingAction);
                break;
        }
    }
    // else do standard handling of event
    else
    {
        if (modflag & NSFunctionKeyMask)
        {
            NSData *data = nil;

            switch(unicode)
            {
                case NSUpArrowFunctionKey: data = [TERMINAL keyArrowUp:modflag]; break;
                case NSDownArrowFunctionKey: data = [TERMINAL keyArrowDown:modflag]; break;
                case NSLeftArrowFunctionKey: data = [TERMINAL keyArrowLeft:modflag]; break;
                case NSRightArrowFunctionKey: data = [TERMINAL keyArrowRight:modflag]; break;

                case NSInsertFunctionKey:
                    // case NSHelpFunctionKey:
                    data = [TERMINAL keyInsert]; break;
                case NSDeleteFunctionKey:
                    data = [TERMINAL keyDelete]; break;
                case NSHomeFunctionKey: data = [TERMINAL keyHome:modflag]; break;
                case NSEndFunctionKey: data = [TERMINAL keyEnd:modflag]; break;
                case NSPageUpFunctionKey: data = [TERMINAL keyPageUp]; break;
                case NSPageDownFunctionKey: data = [TERMINAL keyPageDown]; break;

                case NSPrintScreenFunctionKey:
                    break;
                case NSScrollLockFunctionKey:
                case NSPauseFunctionKey:
                    break;
                case NSClearLineFunctionKey:
                    data = [@"\e" dataUsingEncoding: NSUTF8StringEncoding];
                    break;
            }

            if (NSF1FunctionKey<=unicode&&unicode<=NSF35FunctionKey)
                data = [TERMINAL keyFunction:unicode-NSF1FunctionKey+1];

            if (data != nil) {
                send_str = (unsigned char *)[data bytes];
                send_strlen = [data length];
            }
            else if (keystr != nil) {
                NSData *keydat = ((modflag & NSControlKeyMask) && unicode>0)?
                    [keystr dataUsingEncoding:NSUTF8StringEncoding]:
                    [unmodkeystr dataUsingEncoding:NSUTF8StringEncoding];
                send_str = (unsigned char *)[keydat bytes];
                send_strlen = [keydat length];
            }
        }
        else if ((modflag & NSAlternateKeyMask) &&
                 ([self optionKey] != OPT_NORMAL))
        {
            NSData *keydat = ((modflag & NSControlKeyMask) && unicode>0)?
                [keystr dataUsingEncoding:NSUTF8StringEncoding]:
                [unmodkeystr dataUsingEncoding:NSUTF8StringEncoding];
            // META combination
            if (keydat != nil) {
                send_str = (unsigned char *)[keydat bytes];
                send_strlen = [keydat length];
            }
            if ([self optionKey] == OPT_ESC) {
                send_pchr = '\e';
            }
            else if ([self optionKey] == OPT_META && send_str != NULL)
            {
                int i;
                for (i = 0; i < send_strlen; ++i)
                    send_str[i] |= 0x80;
            }
        }
        else
        {
            int max = [keystr length];
            NSData *data=nil;

            if (max!=1||[keystr characterAtIndex:0] > 0x7f)
                data = [keystr dataUsingEncoding:[TERMINAL encoding]];
            else
                data = [keystr dataUsingEncoding:NSUTF8StringEncoding];

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

            // NSLog(@"modflag = 0x%x; send_strlen = %d; send_str[0] = '%c (0x%x)'", modflag, send_strlen, send_str[0]);
            if (modflag & NSControlKeyMask &&
                send_strlen == 1 &&
                send_str[0] == '|')
            {
                send_str = (unsigned char*)"\034"; // control-backslash
                send_strlen = 1;
            }

            else if ((modflag & NSControlKeyMask) &&
                (modflag & NSShiftKeyMask) &&
                send_strlen == 1 &&
                send_str[0] == '/')
            {
                send_str = (unsigned char*)"\177"; // control-?
                send_strlen = 1;
            }
            else if (modflag & NSControlKeyMask &&
                     send_strlen == 1 &&
                     send_str[0] == '/')
            {
                send_str = (unsigned char*)"\037"; // control-/
                send_strlen = 1;
            }
            else if (modflag & NSShiftKeyMask &&
                     send_strlen == 1 &&
                     send_str[0] == '\031')
            {
                send_str = (unsigned char*)"\033[Z"; // backtab
                send_strlen = 3;
            }

        }

        if (EXIT == NO )
        {
            if (send_pchr >= 0) {
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
    // Handle the option-click event
    return 0;
/*  return (([theEvent type] == NSLeftMouseDown) &&
            ([theEvent modifierFlags] & NSAlternateKeyMask));   */
}

- (void)handleEvent: (NSEvent *) theEvent
{
    // We handle option-click to position the cursor...
    /*if(([theEvent type] == NSLeftMouseDown) &&
       ([theEvent modifierFlags] & NSAlternateKeyMask))
        [self handleOptionClick: theEvent]; */
}

- (void) handleOptionClick: (NSEvent *) theEvent
{
    if (EXIT) return;

    // Here we will attempt to position the cursor to the mouse-click

    NSPoint locationInWindow, locationInTextView, locationInScrollView;
    int x, y;
    float w = [TEXTVIEW charWidth], h = [TEXTVIEW lineHeight];

    locationInWindow = [theEvent locationInWindow];
    locationInTextView = [TEXTVIEW convertPoint: locationInWindow fromView: nil];
    locationInScrollView = [SCROLLVIEW convertPoint: locationInWindow fromView: nil];

    x = locationInTextView.x/w;
    y = locationInScrollView.y/h + 1;

    // NSLog(@"loc_x = %f; loc_y = %f", locationInTextView.x, locationInScrollView.y);
    // NSLog(@"font width = %f, font height = %f", fontSize.width, fontSize.height);
    // NSLog(@"x = %d; y = %d", x, y);


    if (x == [SCREEN cursorX] && y == [SCREEN cursorY]) {
        return;
    }

    NSData *data;
    int i;
    // now move the cursor up or down
    for (i = 0; i < abs(y - [SCREEN cursorY]); i++) {
        if (y < [SCREEN cursorY]) {
            data = [TERMINAL keyArrowUp:0];
        } else {
            data = [TERMINAL keyArrowDown:0];
        }
        [self writeTask:[NSData dataWithBytes:[data bytes] length:[data length]]];
    }
    // now move the cursor left or right
    for (i = 0; i < abs(x - [SCREEN cursorX]); i++) {
        if (x < [SCREEN cursorX]) {
            data = [TERMINAL keyArrowLeft:0];
        } else {
            data = [TERMINAL keyArrowRight:0];
        }
        [self writeTask:[NSData dataWithBytes:[data bytes] length:[data length]]];
    }

    // trigger an update of the display.
    [TEXTVIEW setNeedsDisplay:YES];
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
        // in MacJapanese, the backslash char (ASCII 0x5C) is mapped to Unicode 0xA5.
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
    // let the update thred update display if a key is being held down
    /*if([TEXTVIEW keyIsARepeat] == NO)
        [self updateDisplay];*/
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
    if ([sender tag]) {
        // paste with escape;
        [str replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:NSLiteralSearch range:NSMakeRange(0, [str length])];
        [str replaceOccurrencesOfString:@"'" withString:@"\\'" options:NSLiteralSearch range:NSMakeRange(0, [str length])];
        [str replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:NSLiteralSearch range:NSMakeRange(0, [str length])];
        [str replaceOccurrencesOfString:@" " withString:@"\\ " options:NSLiteralSearch range:NSMakeRange(0, [str length])];
    }
    [self pasteString: str];
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

- (void)setLabelAttribute
{
    struct timeval now;

    gettimeofday(&now, NULL);
    if ([self exited]) {
        // dead
        [parent setLabelColor: deadStateColor forTabViewItem: tabViewItem];
        if (isProcessing) {
            [self setIsProcessing: NO];
        }
    } else if ([[tabViewItem tabView] selectedTabViewItem] != tabViewItem) {
        if (now.tv_sec > lastOutput.tv_sec+2) {
            if (isProcessing) {
                [self setIsProcessing: NO];
            }

            if (newOutput) {
                // Idle after new output
                if (!growlIdle && now.tv_sec > lastOutput.tv_sec+1) {
                    [gd growlNotify:NSLocalizedStringFromTableInBundle(@"Idle",@"iTerm", [NSBundle bundleForClass: [self class]], @"Growl Alerts")
                    withDescription:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Session %@ #%d becomes idle.",@"iTerm", [NSBundle bundleForClass: [self class]], @"Growl Alerts"),[self name],[self realObjectCount]]
                    andNotification:@"Idle"];
                    growlIdle = YES;
                    growlNewOutput = NO;
                }
                [parent setLabelColor: idleStateColor forTabViewItem: tabViewItem];
            } else {
                // normal state
                [parent setLabelColor: normalStateColor forTabViewItem: tabViewItem];
            }
        } else {
            if (newOutput) {
                if (isProcessing == NO && ![[PreferencePanel sharedInstance] useCompactLabel]) {
                    [self setIsProcessing: YES];
                }

                if (!growlNewOutput && ![parent sendInputToAllSessions]) {
                    [gd growlNotify:NSLocalizedStringFromTableInBundle(@"New Output",@"iTerm", [NSBundle bundleForClass: [self class]], @"Growl Alerts")
                    withDescription:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"New Output was received in %@ #%d.",@"iTerm", [NSBundle bundleForClass: [self class]], @"Growl Alerts"),[self name],[self realObjectCount]]
                    andNotification:@"New Output"];
                    growlNewOutput = YES;
                }

                [parent setLabelColor: newOutputStateColor forTabViewItem: tabViewItem];
            }
        }
    } else {
        // front tab
        if (isProcessing) {
            [self setIsProcessing: NO];
        }
        growlNewOutput = NO;
        newOutput = NO;
        [parent setLabelColor: chosenStateColor forTabViewItem: tabViewItem];
    }
}

- (BOOL) bell
{
    return bell;
}

- (void)setBell:(BOOL)flag
{
    if (flag != bell) {
        bell = flag;
        if (bell) {
            [self setIcon: warningImage];
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
                                 [self realObjectCount]]
                andNotification:@"Bells"];
            }
        } else {
            [self setIcon: nil];
        }
    }
}

- (BOOL) isProcessing
{
    return (isProcessing);
}

- (void) setIsProcessing: (BOOL) aFlag
{
    isProcessing = aFlag;
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
        NSString* key = [NSString stringWithFormat:@"KEY_ANSI_%d_COLOR", i];
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
    ITAddressBookMgr *bookmarkManager;

    // get our shared managers
    bookmarkManager = [ITAddressBookMgr sharedInstance];

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
    [self setDisableBold:[[aDict objectForKey:KEY_DISABLE_BOLD] boolValue]];

    // set up the rest of the preferences
    [SCREEN setPlayBellFlag:![[aDict objectForKey:KEY_SILENCE_BELL] boolValue]];
    [SCREEN setShowBellFlag:[[aDict objectForKey:KEY_VISUAL_BELL] boolValue]];
    [SCREEN setGrowlFlag:[[aDict objectForKey:KEY_BOOKMARK_GROWL_NOTIFICATIONS] boolValue]];
    [SCREEN setBlinkingCursor: [[aDict objectForKey: KEY_BLINKING_CURSOR] boolValue]];
    [TEXTVIEW setBlinkingCursor: [[aDict objectForKey: KEY_BLINKING_CURSOR] boolValue]];
    [TEXTVIEW setUseTransparency:[[aDict objectForKey:KEY_TRANSPARENCY] boolValue]];
    if ([parent currentSession] == self) {
        if ([[aDict objectForKey:KEY_BLUR] boolValue]) {
            [parent enableBlur];
        } else {
            [parent disableBlur];
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
- (void) menuForEvent:(NSEvent *)theEvent menu: (NSMenu *) theMenu
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
    [aMenuItem setTarget: [self parent]];
    [theMenu addItem: aMenuItem];
    [aMenuItem release];

    // Ask the parent if it has anything to add
    if ([[self parent] respondsToSelector:@selector(menuForEvent: menu:)]) {
        [[self parent] menuForEvent:theEvent menu: theMenu];
    }
}

- (PseudoTerminal *)parent
{
    return (parent);
}

- (void)setParent:(PseudoTerminal *)theParent
{
    parent = theParent; // don't retain parent. parent retains self.
}

- (NSTabViewItem *)tabViewItem
{
    return (tabViewItem);
}

- (void)setTabViewItem:(NSTabViewItem *)theTabViewItem
{
    tabViewItem = theTabViewItem;
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

- (NSString*)name
{
    return name;
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

    [tabViewItem setLabel:name];
    [self setBell:NO];

    // get the session submenu to be rebuilt
    if ([[iTermController sharedInstance] currentTerminal] == [self parent]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermNameOfSessionDidChange"
                                                            object:[self parent]
                                                          userInfo:nil];
    }
}

- (NSString*)windowTitle
{
    return windowTitle;
}

- (void)setWindowTitle:(NSString*)theTitle
{
    if([theTitle isEqualToString:windowTitle]) return;

    [windowTitle autorelease];
    windowTitle = nil;

    if (theTitle != nil && [theTitle length] > 0) {
        windowTitle = [theTitle retain];
    }

    if ([[self parent] currentSession] == self) {
        [[self parent] setWindowTitle];
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

- (NSView *)view
{
    return view;
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
    NSLog(@"%s(%d):-[PseudoTerminal setEncoding:%d]",
          __FILE__, __LINE__, encoding);
#endif
    [TERMINAL setEncoding:encoding];
}


- (NSString *)tty
{
    return [SHELL tty];
}

// I think Applescript needs this method; need to check
- (int)number
{
    return [[tabViewItem tabView] indexOfTabViewItem: tabViewItem];
}

- (int)objectCount
{
    return [[PreferencePanel sharedInstance] useCompactLabel]?0:objectCount;
}

// This one is for purposes other than PSMTabBarControl
- (int)realObjectCount
{
    return objectCount;
}

- (void)setObjectCount:(int)value
{
    objectCount = value;
}

- (NSImage *)icon
{
    return icon;
}

- (void)setIcon:(NSImage *)anIcon
{
    [anIcon retain];
    [icon release];
    icon = anIcon;
}

- (NSString *)contents
{
    return [TEXTVIEW content];
}

- (NSString *)backgroundImagePath
{
    return backgroundImagePath;
}

+ (NSImage*)loadBackgroundImage:(NSString*)imageFilePath
{
    NSString* actualPath;
    if ([imageFilePath isAbsolutePath] == NO) {
        NSBundle *myBundle = [NSBundle bundleForClass:[PTYSession class]];
        actualPath = [myBundle pathForResource:imageFilePath ofType:@""];
    } else {
        actualPath = imageFilePath;
    }
    return [[NSImage alloc] initWithContentsOfFile:actualPath];
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
    if ([parent fullScreen]) {
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
                target:self selector:@selector(doAntiIdle) userInfo:nil
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

- (BOOL)disableBold
{
    return [TEXTVIEW disableBold];
}

- (void)setDisableBold:(BOOL)boldFlag
{
    [TEXTVIEW setDisableBold:boldFlag];
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

- (void) resetStatus;
{
    newOutput = NO;
}

- (BOOL)exited
{
    return EXIT;
}

- (int)optionKey
{
    return [[[self addressBookEntry] objectForKey:KEY_OPTION_KEY_SENDS] intValue];
}

- (void)setAddressBookEntry:(NSDictionary*)entry
{
    [addressBookEntry release];
    addressBookEntry = [entry retain];
}

- (NSDictionary *)addressBookEntry
{
    return addressBookEntry;
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

- (void)updateDisplay
{
    if ([[tabViewItem tabView] selectedTabViewItem] != tabViewItem) {
        [self setLabelAttribute];
    }

    if ([parent currentSession] == self) {
        struct timeval now;
        gettimeofday(&now, NULL);

        if (now.tv_sec*10+now.tv_usec/100000 >= lastBlink.tv_sec*10+lastBlink.tv_usec/100000+7) {
            if ([parent tempTitle]) {
                [parent setWindowTitle];
                [parent resetTempTitle];
            }
            lastBlink = now;
        }
    }

    [TEXTVIEW refresh];
    if (![(PTYScroller*)([SCROLLVIEW verticalScroller]) userScroll]) {
        [TEXTVIEW scrollEnd];
    }
    [self scheduleUpdateSoon:NO];
}

- (void)scheduleUpdateSoon:(BOOL)soon
{
    // This method ensures regular updates for text blinking, but allows
    // for quicker (soon=YES) updates to draw newly read text from PTYTask

    if (soon && [updateTimer isValid] && [[updateTimer userInfo] intValue]) {
        return;
    }

    [updateTimer invalidate];
    [updateTimer release];

    NSTimeInterval timeout = 0.5;
    if (soon) {
        timeout = (0.001 + 0.001*[[PreferencePanel sharedInstance] refreshRate]);
    }

    updateTimer = [[NSTimer scheduledTimerWithTimeInterval:timeout
            target:self selector:@selector(updateDisplay)
            userInfo:[NSNumber numberWithInt:soon?1:0]
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


// Notification
- (void) tabViewWillRedraw: (NSNotification *) aNotification
{
    if ([aNotification object] == [[self tabViewItem] tabView]) {
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
    [parent fitWindowToSession:self];
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
    guid = [BookmarkModel newGuid];
    [[BookmarkModel sessionsInstance] setObject:guid
                                         forKey:KEY_GUID
                                     inBookmark:bookmark];
    [self setAddressBookEntry:[[BookmarkModel sessionsInstance] bookmarkWithGuid:guid]];
    return guid;
}

@end

@implementation PTYSession (ScriptingSupport)

// Object specifier
- (NSScriptObjectSpecifier *)objectSpecifier
{
    NSUInteger theIndex = 0;
    id classDescription = nil;

    NSScriptObjectSpecifier *containerRef = nil;

    theIndex = [[[self parent] tabView] indexOfTabViewItem: [self tabViewItem]];

    if (theIndex != NSNotFound) {
        containerRef = [[self parent] objectSpecifier];
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

-(void)handleSelectScriptCommand: (NSScriptCommand *)command
{
    [[parent tabView] selectTabViewItemWithIdentifier: self];
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
    [parent closeSession: self];
}

@end

@implementation PTYSession (Private)

#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4
- (NSString*)_getLocale
{
    // Keep a copy of the current locale setting for this process
    char* backupLocale = setlocale(LC_CTYPE, NULL);

    // Start with the locale
    NSString* locale = [[NSLocale currentLocale] localeIdentifier];

    // Append the encoding
    CFStringEncoding cfEncoding = CFStringConvertNSStringEncodingToEncoding([self encoding]);
    NSString* ianaEncoding = (NSString*)CFStringConvertEncodingToIANACharSetName(cfEncoding);
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
#endif

@end
