// -*- mode:objc -*-
// $Id: iTermController.m,v 1.78 2008-10-17 04:02:45 yfabian Exp $
/*
 **  iTermController.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **      Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: Implements the main application delegate and handles the addressbook functions.
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

#import <iTerm/iTermController.h>
#import <iTerm/PreferencePanel.h>
#import <iTerm/PseudoTerminal.h>
#import <iTerm/PTYSession.h>
#import <iTerm/VT100Screen.h>
#import <iTerm/NSStringITerm.h>
#import <iTerm/ITAddressBookMgr.h>
#import <iTerm/iTermGrowlDelegate.h>
#import "PasteboardHistory.h"
#import <Carbon/Carbon.h>
#import "iTermApplicationDelegate.h"

@interface NSApplication (Undocumented)
- (void)_cycleWindowsReversed:(BOOL)back;
@end


static NSString* APPLICATION_SUPPORT_DIRECTORY = @"~/Library/Application Support";
static NSString *SUPPORT_DIRECTORY = @"~/Library/Application Support/iTerm";
static NSString *SCRIPT_DIRECTORY = @"~/Library/Application Support/iTerm/Scripts";

// Comparator for sorting encodings
static NSInteger _compareEncodingByLocalizedName(id a, id b, void *unused)
{
    NSString *sa = [NSString localizedNameOfStringEncoding: [a unsignedIntValue]];
    NSString *sb = [NSString localizedNameOfStringEncoding: [b unsignedIntValue]];
    return [sa caseInsensitiveCompare: sb];
}


@implementation iTermController

static iTermController* shared = nil;
static BOOL initDone = NO;

+ (iTermController*)sharedInstance;
{
    if(!shared && !initDone) {
        shared = [[iTermController alloc] init];
        initDone = YES;
    }

    return shared;
}

+ (void)sharedInstanceRelease
{
    [shared release];
    shared = nil;
}


// init
- (id)init
{
#if DEBUG_ALLOC
    NSLog(@"%s(%d):-[iTermController init]",
          __FILE__, __LINE__);
#endif
    self = [super init];


    // create the iTerm directory if it does not exist
    NSFileManager *fileManager = [NSFileManager defaultManager];

    // create the "~/Library/Application Support" directory if it does not exist
    if([fileManager fileExistsAtPath: [APPLICATION_SUPPORT_DIRECTORY stringByExpandingTildeInPath]] == NO)
        [fileManager createDirectoryAtPath: [APPLICATION_SUPPORT_DIRECTORY stringByExpandingTildeInPath] attributes: nil];

    if([fileManager fileExistsAtPath: [SUPPORT_DIRECTORY stringByExpandingTildeInPath]] == NO)
        [fileManager createDirectoryAtPath: [SUPPORT_DIRECTORY stringByExpandingTildeInPath] attributes: nil];

    terminalWindows = [[NSMutableArray alloc] init];

    // Activate Growl
    /*
     * Need to add routine in iTerm prefs for Growl support and
     * PLIST check here.
     */
    gd = [iTermGrowlDelegate sharedInstance];

    return (self);
}

- (void) dealloc
{
#if DEBUG_ALLOC
    NSLog(@"%s(%d):-[iTermController dealloc]",
        __FILE__, __LINE__);
#endif
    // Close all terminal windows
    while ([terminalWindows count] > 0) {
        [[terminalWindows objectAtIndex:0] close];
    }
    NSAssert([terminalWindows count] == 0, @"Expected terminals to be gone");
    [terminalWindows release];

    // Release the GrowlDelegate
    if(gd)
        [gd release];

    [super dealloc];
}

// Action methods
- (IBAction)newWindow:(id)sender
{
    [self launchBookmark:nil inTerminal: nil];
}

- (void) newSessionInTabAtIndex: (id) sender
{
    Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:[sender representedObject]];
    if (bookmark) {
        [self launchBookmark:bookmark inTerminal:FRONT];
    }
}

- (void) showHideFindBar
{
    [[self currentTerminal] showHideFindBar];
}

- (void)newSessionInWindowAtIndex: (id) sender
{
    Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:[sender representedObject]];
    if (bookmark) {
        [self launchBookmark:bookmark inTerminal:nil];
    }
}

// meant for action for menu items that have a submenu
- (void) noAction: (id) sender
{

}

- (IBAction)newSession:(id)sender
{
    [self launchBookmark:nil inTerminal: FRONT];
}

// navigation
- (IBAction) previousTerminal:(id)sender
{
    [NSApp _cycleWindowsReversed:YES];
}
- (IBAction)nextTerminal:(id)sender
{
    [NSApp _cycleWindowsReversed:NO];
}

- (PseudoTerminal*)currentTerminal
{
    return (FRONT);
}

- (void)terminalWillClose:(PseudoTerminal*)theTerminalWindow
{
    if (FRONT == theTerminalWindow) {
        [self setCurrentTerminal: nil];
    }
    if (theTerminalWindow) {
        [self removeFromTerminalsAtIndex:[terminalWindows indexOfObject:theTerminalWindow]];
    }
}

// Build sorted list of encodings
- (NSArray *) sortedEncodingList
{
    NSStringEncoding const *p;
    NSMutableArray *tmp = [NSMutableArray array];

    for (p = [NSString availableStringEncodings]; *p; ++p)
        [tmp addObject:[NSNumber numberWithUnsignedInt:*p]];
    [tmp sortUsingFunction: _compareEncodingByLocalizedName context:NULL];

    return (tmp);
}

- (void)_addBookmark:(Bookmark*)bookmark toMenu:(NSMenu*)aMenu target:(id)aTarget withShortcuts:(BOOL)withShortcuts
{
    NSMenuItem* aMenuItem = [[[NSMenuItem alloc] initWithTitle:[bookmark objectForKey:KEY_NAME]
                                                        action:@selector(newSessionInTabAtIndex:)
                                                 keyEquivalent:@""] autorelease];
    if (withShortcuts) {
        if ([bookmark objectForKey:KEY_SHORTCUT] != nil) {
            NSString* shortcut = [bookmark objectForKey:KEY_SHORTCUT];
            shortcut = [shortcut lowercaseString];
            [aMenuItem setKeyEquivalent:shortcut];
        }
    }

    unsigned int modifierMask = NSCommandKeyMask | NSControlKeyMask;
    [aMenuItem setKeyEquivalentModifierMask:modifierMask];
    [aMenuItem setRepresentedObject:[bookmark objectForKey:KEY_GUID]];
    [aMenuItem setTarget:aTarget];
    [aMenu addItem:aMenuItem];

    aMenuItem = [[aMenuItem copy] autorelease];
    [aMenuItem setKeyEquivalentModifierMask:modifierMask | NSAlternateKeyMask];
    [aMenuItem setAlternate:YES];
    [aMenuItem setAction:@selector(newSessionInWindowAtIndex:)];
    [aMenuItem setTarget:self];
    [aMenu addItem:aMenuItem];
}

- (void)_addBookmarksForTag:(NSString*)tag toMenu:(NSMenu*)aMenu target:(id)aTarget withShortcuts:(BOOL)withShortcuts
{
    NSMenuItem* aMenuItem = [[[NSMenuItem alloc] initWithTitle:tag action:@selector(noAction:) keyEquivalent:@""] autorelease];
    NSMenu* subMenu = [[[NSMenu alloc] init] autorelease];
    for (int i = 0; i < [[BookmarkModel sharedInstance] numberOfBookmarks]; ++i) {
        Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkAtIndex:i];
        NSArray* tags = [bookmark objectForKey:KEY_TAGS];
        for (int j = 0; j < [tags count]; ++j) {
            if ([tag localizedCaseInsensitiveCompare:[tags objectAtIndex:j]] == NSOrderedSame) {
                [self _addBookmark:bookmark toMenu:subMenu target:aTarget withShortcuts:withShortcuts];
                break;
            }
        }
    }
    [aMenuItem setSubmenu:subMenu];
    [aMenuItem setTarget:self];
    [aMenu addItem:aMenuItem];
}

- (void)addBookmarksToMenu:(NSMenu *)aMenu target:(id)aTarget withShortcuts:(BOOL)withShortcuts
{
    NSArray* tags = [[BookmarkModel sharedInstance] allTags];
    int count = 0;
    for (int i = 0; i < [tags count]; ++i) {
        [self _addBookmarksForTag:[tags objectAtIndex:i]
                           toMenu:aMenu
                           target:aTarget
                    withShortcuts:withShortcuts];
        ++count;
    }
    for (int i = 0; i < [[BookmarkModel sharedInstance] numberOfBookmarks]; ++i) {
        Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkAtIndex:i];
        if ([[bookmark objectForKey:KEY_TAGS] count] == 0) {
            ++count;
            [self _addBookmark:bookmark
                        toMenu:aMenu
                        target:aTarget
                 withShortcuts:withShortcuts];
        }
    }

    if (count > 1) {
        [aMenu addItem:[NSMenuItem separatorItem]];
        NSMenuItem* aMenuItem = [[[NSMenuItem alloc] initWithTitle:
                                  NSLocalizedStringFromTableInBundle(@"Open All",
                                                                     @"iTerm",
                                                                     [NSBundle bundleForClass: [iTermController class]],
                                                                     @"Context Menu")
                                                            action:@selector(newSessionsInWindow:)
                                                     keyEquivalent:@""] autorelease];
        unsigned int modifierMask = NSCommandKeyMask | NSControlKeyMask;
        [aMenuItem setKeyEquivalentModifierMask:modifierMask];
        [aMenuItem setRepresentedObject:@""];
        [aMenuItem setTarget:self];
        [aMenu addItem:aMenuItem];
        aMenuItem = [[aMenuItem copy] autorelease];
        [aMenuItem setKeyEquivalentModifierMask:modifierMask | NSAlternateKeyMask];
        [aMenuItem setAlternate:YES];
        [aMenuItem setAction:@selector(newSessionsInNewWindow:)];
        [aMenuItem setTarget:self];
        [aMenu addItem:aMenuItem];
    }
}

- (void)irAdvance:(int)dir
{
    [FRONT irAdvance:dir];
}

// Executes an addressbook command in new window or tab
- (void)launchBookmark:(NSDictionary *)bookmarkData inTerminal:(PseudoTerminal *)theTerm
{
    PseudoTerminal *term;
    NSDictionary *aDict;

    aDict = bookmarkData;
    if (aDict == nil) {
        aDict = [[BookmarkModel sharedInstance] defaultBookmark];
        if (!aDict) {
            NSMutableDictionary* temp = [[[NSMutableDictionary alloc] init] autorelease];
            [ITAddressBookMgr setDefaultsInBookmark:temp];
            aDict = temp;
        }
    }

    // Where do we execute this command?
    if (theTerm == nil) {
        term = [[[PseudoTerminal alloc] initWithSmartLayout:YES fullScreen:nil] autorelease];
        [self addInTerminals:term];
    } else {
        term = theTerm;
    }

    [term addNewSession:aDict];

    // This function is activated from the dock icon's context menu so make sure
    // that the new window is on top of all other apps' windows. For some reason,
    // makeKeyAndOrderFront does nothing.
    if (![[term window] isKeyWindow]) {
        [NSApp arrangeInFront:self];
    }
}

- (void) launchBookmark: (NSDictionary *) bookmarkData inTerminal: (PseudoTerminal *) theTerm withCommand: (NSString *)command
{
    PseudoTerminal *term;
    NSDictionary *aDict;

    aDict = bookmarkData;
    if (aDict == nil) {
        aDict = [[BookmarkModel sharedInstance] defaultBookmark];
        if (!aDict) {
            NSMutableDictionary* temp = [[[NSMutableDictionary alloc] init] autorelease];
            [ITAddressBookMgr setDefaultsInBookmark:temp];
            aDict = temp;
        }
    }

    // Where do we execute this command?
    if (theTerm == nil) {
        term = [[[PseudoTerminal alloc] initWithSmartLayout:YES fullScreen:nil] autorelease];
        [self addInTerminals: term];
    } else {
        term = theTerm;
    }

    [term addNewSession: aDict withCommand: command];
}

- (void) launchBookmark: (NSDictionary *) bookmarkData inTerminal: (PseudoTerminal *) theTerm withURL: (NSString *)url
{
    PseudoTerminal *term;
    NSDictionary *aDict;

    aDict = bookmarkData;
    // $$ is a prefix/suffix of a variabe.
    if (aDict == nil || [[ITAddressBookMgr bookmarkCommand:aDict] isEqualToString:@"$$"]) {
        Bookmark* prototype = aDict;
        if (!prototype) {
            prototype = [[BookmarkModel sharedInstance] defaultBookmark];
        }
        if (!prototype) {
            NSMutableDictionary* temp = [[[NSMutableDictionary alloc] init] autorelease];
            [ITAddressBookMgr setDefaultsInBookmark:temp];
            prototype = temp;
        }

        NSMutableDictionary *tempDict = [NSMutableDictionary dictionaryWithDictionary:prototype];
        NSURL *urlRep = [NSURL URLWithString: url];
        NSString *urlType = [urlRep scheme];

        if ([urlType compare:@"ssh" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            NSMutableString *tempString = [NSMutableString stringWithString:@"ssh "];
            if ([urlRep user]) [tempString appendFormat:@"-l %@ ", [urlRep user]];
            if ([urlRep port]) [tempString appendFormat:@"-p %@ ", [urlRep port]];
            if ([urlRep host]) [tempString appendString:[urlRep host]];
            [tempDict setObject:tempString forKey:KEY_COMMAND];
            aDict = tempDict;
        }
        else if ([urlType compare:@"ftp" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            NSMutableString *tempString = [NSMutableString stringWithFormat:@"ftp %@", url];
            [tempDict setObject:tempString forKey:KEY_COMMAND];
            aDict = tempDict;
        }
        else if ([urlType compare:@"telnet" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            NSMutableString *tempString = [NSMutableString stringWithString:@"telnet "];
            if ([urlRep user]) [tempString appendFormat:@"-l %@ ", [urlRep user]];
            if ([urlRep host]) {
                [tempString appendString:[urlRep host]];
                if ([urlRep port]) [tempString appendFormat:@" %@", [urlRep port]];
            }
            [tempDict setObject:tempString forKey:KEY_COMMAND];
            aDict = tempDict;
        }
    }

    // Where do we execute this command?
    if (theTerm == nil) {
        term = [[[PseudoTerminal alloc] initWithSmartLayout:YES fullScreen:nil] autorelease];
        [self addInTerminals: term];
    } else {
        term = theTerm;
    }

    [term addNewSession: aDict withURL: url];
}

- (void) launchScript: (id) sender
{
    NSString *fullPath = [NSString stringWithFormat: @"%@/%@", [SCRIPT_DIRECTORY stringByExpandingTildeInPath], [sender title]];

    if ([[[sender title] pathExtension] isEqualToString: @"scpt"]) {
        NSAppleScript *script;
        NSDictionary *errorInfo = [NSDictionary dictionary];
        NSURL *aURL = [NSURL fileURLWithPath: fullPath];

        // Make sure our script suite registry is loaded
        [NSScriptSuiteRegistry sharedScriptSuiteRegistry];

        script = [[NSAppleScript alloc] initWithContentsOfURL: aURL error: &errorInfo];
        [script executeAndReturnError: &errorInfo];
        [script release];
    }
    else {
        [[NSWorkspace sharedWorkspace] launchApplication:fullPath];
    }

}

- (PTYTextView *) frontTextView
{
    return ([[FRONT currentSession] TEXTVIEW]);
}

-(int)numberOfTerminals
{
    return [terminalWindows count];
}

-(PseudoTerminal*)terminalAtIndex:(int)i
{
    return [terminalWindows objectAtIndex:i];
}


static void OnHotKeyEvent()
{
    iTermController* controller = [iTermController sharedInstance];
    int n = [controller numberOfTerminals];
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    if (n == 0) {
        [controller newWindow:nil];
    }
}

/*
 * The callback is passed a proxy for the tap, the event type, the incoming event,
 * and the refcon the callback was registered with.
 * The function should return the (possibly modified) passed in event,
 * a newly constructed event, or NULL if the event is to be deleted.
 *
 * The CGEventRef passed into the callback is retained by the calling code, and is
 * released after the callback returns and the data is passed back to the event 
 * system.  If a different event is returned by the callback function, then that
 * event will be released by the calling code along with the original event, after
 * the event data has been passed back to the event system.
 */
static CGEventRef OnTappedEvent(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon)
{
    iTermController* cont = refcon;
    NSEvent* e = [NSEvent eventWithCGEvent:event];
    if (cont->hotkeyCode_ &&
        ([e modifierFlags] & cont->hotkeyModifiers_) == cont->hotkeyModifiers_ &&
        [e keyCode] == cont->hotkeyCode_) {
        OnHotKeyEvent();
    }
    
    return event;
}

- (void)unregisterHotkey
{
    hotkeyCode_ = 0;
    hotkeyModifiers_ = 0;
}

- (void)registerHotkey:(int)keyCode modifiers:(int)modifiers
{
    hotkeyCode_ = keyCode;
    hotkeyModifiers_ = modifiers;
    static CFMachPortRef machPortRef;
    if (!machPortRef) {
        DebugLog(@"Register event tap.");
        machPortRef = CGEventTapCreate(kCGHIDEventTap,
                                       kCGHeadInsertEventTap,
                                       kCGEventTapOptionListenOnly,
                                       CGEventMaskBit(kCGEventKeyDown),
                                       (CGEventTapCallBack)OnTappedEvent,
                                       self);
        if (machPortRef) {
            CFRunLoopSourceRef eventSrc;

            eventSrc = CFMachPortCreateRunLoopSource(NULL, machPortRef, 0);
            if (eventSrc == NULL) {
                DebugLog(@"CFMachPortCreateRunLoopSource failed.");
            } else {
                DebugLog(@"Adding run loop source.");
                // Get the CFRunLoop primitive for the Carbon Main Event Loop, and add the new event souce
                CFRunLoopAddSource(CFRunLoopGetCurrent(), eventSrc, kCFRunLoopDefaultMode);
                CFRelease(eventSrc);
            }
        } else {            
            switch (NSRunAlertPanel(@"Could not enable hotkey.",
                                    @"You have assigned a \"hotkey\" that opens iTerm2 at any time. To use it, you must turn on \"access for assistive devices\" in the Universal Access preferences panel in System Preferences and restart iTerm2.",
                                    @"OK",
                                    @"Open System Preferences",
                                    @"Disable Hotkey",
                                    nil)) {
                case NSAlertOtherReturn:
                    [[PreferencePanel sharedInstance] disableHotkey];
                    break;

                case NSAlertAlternateReturn:
                    [[NSWorkspace sharedWorkspace] openFile:@"/System/Library/PreferencePanes/UniversalAccessPref.prefPane"];
                    break;
            }
        }
    }
}

@end

// keys for to-many relationships:
NSString *terminalsKey = @"terminals";

// Scripting support
@implementation iTermController (KeyValueCoding)

- (BOOL)application:(NSApplication *)sender delegateHandlesKey:(NSString *)key
{
    BOOL ret;
    // NSLog(@"key = %@", key);
    ret = [key isEqualToString:@"terminals"] || [key isEqualToString:@"currentTerminal"];
    return (ret);
}

// accessors for to-many relationships:
-(NSArray*)terminals
{
    // NSLog(@"iTerm: -terminals");
    return (terminalWindows);
}

-(void)setTerminals: (NSArray*)terminals
{
    // no-op
}

// accessors for to-many relationships:
// (See NSScriptKeyValueCoding.h)
-(id)valueInTerminalsAtIndex:(unsigned)theIndex
{
    //NSLog(@"iTerm: valueInTerminalsAtIndex %d: %@", theIndex, [terminalWindows objectAtIndex: theIndex]);
    return ([terminalWindows objectAtIndex: theIndex]);
}

- (void) setCurrentTerminal: (PseudoTerminal *) thePseudoTerminal
{
    FRONT = thePseudoTerminal;

    // make sure this window is the key window
    if([thePseudoTerminal windowInited] && [[thePseudoTerminal window] isKeyWindow] == NO)
        [[thePseudoTerminal window] makeKeyAndOrderFront: self];

    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermWindowBecameKey" object: thePseudoTerminal userInfo: nil];

}

-(void)replaceInTerminals:(PseudoTerminal *)object atIndex:(unsigned)theIndex
{
    // NSLog(@"iTerm: replaceInTerminals 0x%x atIndex %d", object, theIndex);
    [terminalWindows replaceObjectAtIndex: theIndex withObject: object];
}

- (void) addInTerminals: (PseudoTerminal *) object
{
    // NSLog(@"iTerm: addInTerminals 0x%x", object);
    [self insertInTerminals: object atIndex: [terminalWindows count]];
}

- (void) insertInTerminals: (PseudoTerminal *) object
{
    // NSLog(@"iTerm: insertInTerminals 0x%x", object);
    [self insertInTerminals: object atIndex: [terminalWindows count]];
}

-(void)insertInTerminals:(PseudoTerminal *)object atIndex:(unsigned)theIndex
{
    if ([terminalWindows containsObject: object] == YES) {
        return;
    }

    [terminalWindows insertObject: object atIndex: theIndex];
    if (![object isInitialized]) {
        [object initWithSmartLayout:YES fullScreen:nil];
    }
}

-(void)removeFromTerminalsAtIndex:(unsigned)theIndex
{
    // NSLog(@"iTerm: removeFromTerminalsAtInde %d", theIndex);
    [terminalWindows removeObjectAtIndex: theIndex];
}

// a class method to provide the keys for KVC:
- (NSArray*)kvcKeys
{
    static NSArray *_kvcKeys = nil;
    if( nil == _kvcKeys ){
        _kvcKeys = [[NSArray alloc] initWithObjects:
            terminalsKey,  nil ];
    }
    return _kvcKeys;
}

@end

