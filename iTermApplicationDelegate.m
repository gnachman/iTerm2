// -*- mode:objc -*-
// $Id: iTermApplicationDelegate.m,v 1.70 2008-10-23 04:57:13 yfabian Exp $
/*
 **  iTermApplicationDelegate.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **          Initial code by Kiichi Kusama
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

#import <iTerm/iTermApplicationDelegate.h>
#import <iTerm/iTermController.h>
#import <iTerm/ITAddressBookMgr.h>
#import <iTerm/PreferencePanel.h>
#import <iTerm/PseudoTerminal.h>
#import <iTerm/PTYSession.h>
#import <iTerm/VT100Terminal.h>
#import <iTerm/FindCommandHandler.h>
#import <iTerm/PTYWindow.h>
#import <iTerm/PTYTextView.h>
#import "iTerm/NSStringITerm.h"
#import <BookmarksWindow.h>
#import "PTYTab.h"
#import "iTermExpose.h"
#include <unistd.h>

static NSString *SCRIPT_DIRECTORY = @"~/Library/Application Support/iTerm/Scripts";
static NSString* AUTO_LAUNCH_SCRIPT = @"~/Library/Application Support/iTerm/AutoLaunch.scpt";

NSMutableString* gDebugLogStr = nil;
NSMutableString* gDebugLogStr2 = nil;
static BOOL usingAutoLaunchScript = NO;
BOOL gDebugLogging = NO;
int gDebugLogFile = -1;

@implementation iTermAboutWindow

- (IBAction)closeCurrentSession:(id)sender
{
    [self close];
}

@end


@implementation iTermApplicationDelegate

// NSApplication delegate methods
- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
    // Check the system version for minimum requirements.
    SInt32 gSystemVersion;
    Gestalt(gestaltSystemVersion, &gSystemVersion);
    if(gSystemVersion < 0x1020)
    {
                NSRunAlertPanel(NSLocalizedStringFromTableInBundle(@"Sorry",@"iTerm", [NSBundle bundleForClass: [iTermController class]], @"Sorry"),
                         NSLocalizedStringFromTableInBundle(@"Minimum_OS", @"iTerm", [NSBundle bundleForClass: [iTermController class]], @"OS Version"),
                        NSLocalizedStringFromTableInBundle(@"Quit",@"iTerm", [NSBundle bundleForClass: [iTermController class]], @"Quit"),
                         nil, nil);
                [NSApp terminate: self];
    }

    // set the TERM_PROGRAM environment variable
    putenv("TERM_PROGRAM=iTerm.app");

        [self buildScriptMenu:nil];

        // read preferences
    [PreferencePanel migratePreferences];
    [ITAddressBookMgr sharedInstance];
    [PreferencePanel sharedInstance];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Prevent the input manager from swallowing control-q. See explanation here:
    // http://b4winckler.wordpress.com/2009/07/19/coercing-the-cocoa-text-system/
    CFPreferencesSetAppValue(CFSTR("NSQuotedKeystrokeBinding"),
                             CFSTR(""),
                             kCFPreferencesCurrentApplication);
    // This is off by default, but would wreack havoc if set globally.
    CFPreferencesSetAppValue(CFSTR("NSRepeatCountBinding"),
                             CFSTR(""),
                             kCFPreferencesCurrentApplication);

    PreferencePanel* ppanel = [PreferencePanel sharedInstance];
    if ([ppanel hotkey]) {
        [[iTermController sharedInstance] registerHotkey:[ppanel hotkeyCode] modifiers:[ppanel hotkeyModifiers]];
    }
    if ([ppanel isAnyModifierRemapped]) {
        [[iTermController sharedInstance] beginRemappingModifiers];
    }
    // register for services
    [NSApp registerServicesMenuSendTypes:[NSArray arrayWithObjects:NSStringPboardType, nil]
                                                       returnTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, NSStringPboardType, nil]];
}

- (BOOL)applicationShouldTerminate: (NSNotification *) theNotification
{
    NSArray *terminals;

    terminals = [[iTermController sharedInstance] terminals];

    // Display prompt if we need to

    int numTerminals = [terminals count];
    int numNontrivialWindows = numTerminals;
    BOOL promptOnQuit = quittingBecauseLastWindowClosed_ ? NO : (numNontrivialWindows > 0 && [[PreferencePanel sharedInstance] promptOnQuit]);
    quittingBecauseLastWindowClosed_ = NO;
    BOOL promptOnClose = [[PreferencePanel sharedInstance] promptOnClose];
    BOOL onlyWhenMoreTabs = [[PreferencePanel sharedInstance] onlyWhenMoreTabs];
    int numTabs = 0;
    if (numTerminals > 0) {
        numTabs = [[[[iTermController sharedInstance] currentTerminal] tabView] numberOfTabViewItems];
    }
    BOOL shouldShowAlert = (!onlyWhenMoreTabs ||
                            numTerminals > 1 ||
                            numTabs > 1);
    if (promptOnQuit || (promptOnClose &&
                         numTerminals &&
                         shouldShowAlert)) {
        BOOL stayput = NSRunAlertPanel(@"Quit iTerm2?",
                                       @"All sessions will be closed",
                                       @"OK",
                                       @"Cancel",
                                       nil) != NSAlertDefaultReturn;
        if (stayput) {
            return NO;
        }
    }

    // Ensure [iTermController dealloc] is called before prefs are saved
    [[iTermController sharedInstance] stopEventTap];
    [iTermController sharedInstanceRelease];

    // save preferences
    [[PreferencePanel sharedInstance] savePreferences];

    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    [[iTermController sharedInstance] stopEventTap];
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
        //NSLog(@"%s: %@", __PRETTY_FUNCTION__, filename);
        filename = [filename stringWithEscapedShellCharacters];
        if (filename) {
                // Verify whether filename is a script or a folder
                BOOL isDir;
                [[NSFileManager defaultManager] fileExistsAtPath:filename isDirectory:&isDir];
                if (!isDir) {
                    NSString *aString = [NSString stringWithFormat:@"%@; exit;\n", filename];
                    [[iTermController sharedInstance] launchBookmark:nil inTerminal:nil];
                    // Sleeping a while waiting for the login.
                    sleep(1);
                    [[[[iTermController sharedInstance] currentTerminal] currentSession] insertText:aString];
                }
                else {
                        NSString *aString = [NSString stringWithFormat:@"cd %@\n", filename];
                        [[iTermController sharedInstance] launchBookmark:nil inTerminal:nil];
                        // Sleeping a while waiting for the login.
                        sleep(1);
                        [[[[iTermController sharedInstance] currentTerminal] currentSession] insertText:aString];
                }
        }
        return (YES);
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)app
{
    // Check if we have an autolauch script to execute. Do it only once, i.e. at application launch.
    if (usingAutoLaunchScript == NO &&
        [[NSFileManager defaultManager] fileExistsAtPath:[AUTO_LAUNCH_SCRIPT stringByExpandingTildeInPath]]) {
        usingAutoLaunchScript = YES;

        NSAppleScript *autoLaunchScript;
        NSDictionary *errorInfo = [NSDictionary dictionary];
        NSURL *aURL = [NSURL fileURLWithPath: [AUTO_LAUNCH_SCRIPT stringByExpandingTildeInPath]];

        // Make sure our script suite registry is loaded
        [NSScriptSuiteRegistry sharedScriptSuiteRegistry];

        autoLaunchScript = [[NSAppleScript alloc] initWithContentsOfURL: aURL error: &errorInfo];
        [autoLaunchScript executeAndReturnError: &errorInfo];
        [autoLaunchScript release];
    } else {
        if ([[PreferencePanel sharedInstance] openBookmark]) {
            [self showBookmarkWindow:nil];
            if ([[PreferencePanel sharedInstance] openArrangementAtStartup]) {
                // Open both bookmark window and arrangement!
                [[iTermController sharedInstance] loadWindowArrangement];
            }
        } else if ([[PreferencePanel sharedInstance] openArrangementAtStartup]) {
            [[iTermController sharedInstance] loadWindowArrangement];
        } else {
            [self newWindow:nil];
        }
    }
    usingAutoLaunchScript = YES;

    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
    NSNumber* pref = [[NSUserDefaults standardUserDefaults] objectForKey:@"MinRunningTime"];
    const double kMinRunningTime =  pref ? [pref floatValue] : 10;
    if ([[NSDate date] timeIntervalSinceDate:launchTime_] < kMinRunningTime) {
        return NO;
    }
    quittingBecauseLastWindowClosed_ = [[PreferencePanel sharedInstance] quitWhenAllWindowsClosed];
    return quittingBecauseLastWindowClosed_;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag
{
    PreferencePanel* prefPanel = [PreferencePanel sharedInstance];
    if ([prefPanel hotkey] &&
        [prefPanel hotkeyTogglesWindow]) {
        // The hotkey window is configured.
        PseudoTerminal* hotkeyTerm = [[iTermController sharedInstance] hotKeyWindow];
        if (hotkeyTerm) {
            // Hide the existing window or open it if enabled by preference.
            if ([[hotkeyTerm window] alphaValue] == 1) {
                [[iTermController sharedInstance] hideHotKeyWindow:hotkeyTerm];
                return NO;
            } else if ([prefPanel dockIconTogglesWindow]) {
                [[iTermController sharedInstance] showHotKeyWindow];
                return NO;
            }
        } else if ([prefPanel dockIconTogglesWindow]) {
            // No existing hotkey window but preference is to toggle it by dock icon so open a new
            // one.
            [[iTermController sharedInstance] showHotKeyWindow];
            return NO;
        }
    }
    return YES;
}

- (void)applicationDidChangeScreenParameters:(NSNotification *)aNotification
{
    // Make sure that all top-of-screen windows are the proper width.
    for (PseudoTerminal* term in [self terminals]) {
        [term screenParametersDidChange];
    }
}

// init
- (id)init
{
    self = [super init];

    // Add ourselves as an observer for notifications.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadMenus:)
                                                 name:@"iTermWindowBecameKey"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(updateAddressBookMenu:)
                                                 name: @"iTermReloadAddressBook"
                                               object: nil];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(buildSessionSubmenu:)
                                                 name: @"iTermNumberOfSessionsDidChange"
                                               object: nil];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(buildSessionSubmenu:)
                                                 name: @"iTermNameOfSessionDidChange"
                                               object: nil];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(reloadSessionMenus:)
                                                 name: @"iTermSessionBecameKey"
                                               object: nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(nonTerminalWindowBecameKey:)
                                                 name:@"nonTerminalWindowBecameKey"
                                               object:nil];

    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
                                                       andSelector:@selector(getUrl:withReplyEvent:)
                                                     forEventClass:kInternetEventClass
                                                        andEventID:kAEGetURL];

    aboutController = nil;
    launchTime_ = [[NSDate date] retain];

    return self;
}

- (void)awakeFromNib
{
    secureInputDesired_ = [[[NSUserDefaults standardUserDefaults] objectForKey:@"Secure Input"] boolValue];
}

- (void)getUrl:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
    NSString *urlStr = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
    NSURL *url = [NSURL URLWithString: urlStr];
    NSString *urlType = [url scheme];

    id bm = [[PreferencePanel sharedInstance] handlerBookmarkForURL:urlType];
    if (bm) {
        [[iTermController sharedInstance] launchBookmark:bm
                                              inTerminal:[[iTermController sharedInstance] currentTerminal] withURL:urlStr];
    }
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [super dealloc];
}

// Action methods
- (IBAction)newWindow:(id)sender
{
    [[iTermController sharedInstance] newWindow:sender];
}

- (IBAction)newSession:(id)sender
{
    [[iTermController sharedInstance] newSession:sender];
}

// navigation
- (IBAction) previousTerminal: (id) sender
{
    [[iTermController sharedInstance] previousTerminal:sender];
}

- (IBAction) nextTerminal: (id) sender
{
    [[iTermController sharedInstance] nextTerminal:sender];
}

- (IBAction)arrangeHorizontally:(id)sender
{
    [[iTermController sharedInstance] arrangeHorizontally];
}

- (IBAction)showPrefWindow:(id)sender
{
    [[PreferencePanel sharedInstance] run];
}

- (IBAction)showBookmarkWindow:(id)sender
{
    [[BookmarksWindow sharedInstance] showWindow:sender];
}

- (IBAction)instantReplayPrev:(id)sender
{
    [[iTermController sharedInstance] irAdvance:-1];
}

- (IBAction)instantReplayNext:(id)sender
{
    [[iTermController sharedInstance] irAdvance:1];
}

- (void)_newSessionMenu:(NSMenu*)superMenu title:(NSString*)title target:(id)aTarget selector:(SEL)selector openAllSelector:(SEL)openAllSelector
{
    //new window menu
    NSMenuItem *newMenuItem;
    NSMenu *bookmarksMenu;
    newMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(title,
                                                                                       @"iTerm",
                                                                                       [NSBundle bundleForClass:[self class]],
                                                                                       @"Context menu")
                                             action:nil
                                      keyEquivalent:@""];
    [superMenu addItem:newMenuItem];
    [newMenuItem release];

    // Create the bookmark submenus for new session
    // Build the bookmark menu
    bookmarksMenu = [[[NSMenu alloc] init] autorelease];

    [[iTermController sharedInstance] addBookmarksToMenu:bookmarksMenu
                                            withSelector:selector
                                         openAllSelector:openAllSelector
                                              startingAt:0];
    [newMenuItem setSubmenu:bookmarksMenu];
}

- (NSMenu*)bookmarksMenu
{
    return bookmarkMenu;
}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender
{
    NSMenu* aMenu = [[NSMenu alloc] initWithTitle: @"Dock Menu"];

    PseudoTerminal *frontTerminal;
    frontTerminal = [[iTermController sharedInstance] currentTerminal];
    [self _newSessionMenu:aMenu title:@"New Window"
                   target:[iTermController sharedInstance]
                 selector:@selector(newSessionInWindowAtIndex:)
          openAllSelector:@selector(newSessionsInNewWindow:)];
    [self _newSessionMenu:aMenu title:@"New Tab"
                   target:frontTerminal
                 selector:@selector(newSessionInTabAtIndex:)
          openAllSelector:@selector(newSessionsInWindow:)];

    return ([aMenu autorelease]);
}

- (void)applicationWillBecomeActive:(NSNotification *)aNotification
{
    DLog(@"******** Become Active");
    for (PseudoTerminal* term in [self terminals]) {
        if ([term isHotKeyWindow]) {
            //NSLog(@"Visor is open; not rescuing orphans.");
            return;
        }
    }
    for (PseudoTerminal* term in [self terminals]) {
        if ([term isOrderedOut]) {
            //NSLog(@"term %p was orphaned, order front.", term);
            [[term window] orderFront:nil];
        }
    }
}

// font control
- (IBAction) biggerFont: (id) sender
{
    [[[[iTermController sharedInstance] currentTerminal] currentSession] changeFontSizeDirection:1];
}

- (IBAction) smallerFont: (id) sender
{
    [[[[iTermController sharedInstance] currentTerminal] currentSession] changeFontSizeDirection:-1];
}



static void SwapDebugLog() {
        NSMutableString* temp;
        temp = gDebugLogStr;
        gDebugLogStr = gDebugLogStr2;
        gDebugLogStr2 = temp;
}

static void FlushDebugLog() {
        NSData* data = [gDebugLogStr dataUsingEncoding:NSUTF8StringEncoding];
        int written = write(gDebugLogFile, [data bytes], [data length]);
        assert(written == [data length]);
        [gDebugLogStr setString:@""];
}

- (IBAction)maximizePane:(id)sender
{
    [[[iTermController sharedInstance] currentTerminal] toggleMaximizeActivePane];
    [self updateMaximizePaneMenuItem];
}

- (IBAction)toggleUseTransparency:(id)sender
{
    [[[iTermController sharedInstance] currentTerminal] toggleUseTransparency:sender];
    [self updateUseTransparencyMenuItem];
}

- (IBAction)toggleSecureInput:(id)sender
{
    // Set secureInputDesired_ to the opposite of the current state.
    secureInputDesired_ = [secureInput state] == NSOffState;

    // Try to set the system's state of secure input to the desired state.
    if (secureInputDesired_) {
        if (EnableSecureEventInput() != noErr) {
            NSLog(@"Failed to enable secure input.");
        }
    } else {
        if (DisableSecureEventInput() != noErr) {
            NSLog(@"Failed to disable secure input.");
        }
    }

    // Set the state of the control to the new true state.
    [secureInput setState:IsSecureEventInputEnabled() ? NSOnState : NSOffState];

    // Save the preference, independent of whether it succeeded or not.
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:secureInputDesired_]
                                              forKey:@"Secure Input"];
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
    if (secureInputDesired_) {
        if (EnableSecureEventInput() != noErr) {
            NSLog(@"Failed to enable secure input.");
        }
    }
    // Set the state of the control to the new true state.
    [secureInput setState:IsSecureEventInputEnabled() ? NSOnState : NSOffState];
}

- (void)applicationDidResignActive:(NSNotification *)aNotification
{
    if (secureInputDesired_) {
        if (DisableSecureEventInput() != noErr) {
            NSLog(@"Failed to disable secure input.");
        }
    }
    // Set the state of the control to the new true state.
    [secureInput setState:IsSecureEventInputEnabled() ? NSOnState : NSOffState];
}

// Debug logging
-(IBAction)debugLogging:(id)sender
{
        if (!gDebugLogging) {
                NSRunAlertPanel(@"Debug Logging Enabled",
                                                @"Writing to /tmp/debuglog.txt",
                                                @"OK", nil, nil);
                gDebugLogFile = open("/tmp/debuglog.txt", O_TRUNC | O_CREAT | O_WRONLY, S_IRUSR | S_IWUSR);
                gDebugLogStr = [[NSMutableString alloc] init];
                gDebugLogStr2 = [[NSMutableString alloc] init];
                gDebugLogging = !gDebugLogging;
        } else {
                gDebugLogging = !gDebugLogging;
                SwapDebugLog();
                FlushDebugLog();
                SwapDebugLog();
                FlushDebugLog();

                close(gDebugLogFile);
                gDebugLogFile=-1;
                NSRunAlertPanel(@"Debug Logging Stopped",
                                                @"Please compress and send /tmp/debuglog.txt to the developers.",
                                                @"OK", nil, nil);
                [gDebugLogStr release];
                [gDebugLogStr2 release];
        }
}

void DebugLog(NSString* value)
{
        if (gDebugLogging) {
                [gDebugLogStr appendString:value];
                [gDebugLogStr appendString:@"\n"];
                if ([gDebugLogStr length] > 100000000) {
                        SwapDebugLog();
                        [gDebugLogStr2 setString:@""];
                }
        }
}

/// About window

- (NSAttributedString *)_linkTo:(NSString *)urlString title:(NSString *)title
{
    NSDictionary *linkAttributes = [NSDictionary dictionaryWithObject:[NSURL URLWithString:urlString]
                                                               forKey:NSLinkAttributeName];
    NSString *localizedTitle = NSLocalizedStringFromTableInBundle(title, @"iTerm",
                                                                  [NSBundle bundleForClass:[self class]],
                                                                  @"About");

    NSAttributedString *string = [[NSAttributedString alloc] initWithString:localizedTitle
                                                                 attributes:linkAttributes];
    return [string autorelease];
}

- (IBAction)showAbout:(id)sender
{
    // check if an About window is shown already
    if (aboutController) {
        [aboutController showWindow:self];
        return;
    }

    NSDictionary *myDict = [[NSBundle bundleForClass:[self class]] infoDictionary];
    NSString *versionString = [NSString stringWithFormat: @"Build %@\n\n", [myDict objectForKey:@"CFBundleVersion"]];

    NSAttributedString *webAString = [self _linkTo:@"http://iterm2.com/" title:@"Home Page\n"];
    NSAttributedString *bugsAString = [self _linkTo:@"http://code.google.com/p/iterm2/issues/entry" title:@"Report a bug\n\n"];
    NSAttributedString *creditsAString = [self _linkTo:@"http://code.google.com/p/iterm2/wiki/Credits" title:@"Credits"];

    NSDictionary *linkTextViewAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt: NSSingleUnderlineStyle], NSUnderlineStyleAttributeName,
        [NSColor blueColor], NSForegroundColorAttributeName,
        [NSCursor pointingHandCursor], NSCursorAttributeName,
        NULL];

    [AUTHORS setLinkTextAttributes: linkTextViewAttributes];
    [[AUTHORS textStorage] deleteCharactersInRange: NSMakeRange(0, [[AUTHORS textStorage] length])];
    [[AUTHORS textStorage] appendAttributedString:[[[NSAttributedString alloc] initWithString:versionString] autorelease]];
    [[AUTHORS textStorage] appendAttributedString: webAString];
    [[AUTHORS textStorage] appendAttributedString: bugsAString];
    [[AUTHORS textStorage] appendAttributedString: creditsAString];
    [AUTHORS setAlignment: NSCenterTextAlignment range: NSMakeRange(0, [[AUTHORS textStorage] length])];

    aboutController = [[NSWindowController alloc] initWithWindow:ABOUT];
    [aboutController showWindow:ABOUT];
}

// size
- (IBAction)returnToDefaultSize:(id)sender
{
    PseudoTerminal *frontTerminal = [[iTermController sharedInstance] currentTerminal];
    PTYTab* theTab = [frontTerminal currentTab];
    PTYSession* aSession = [theTab activeSession];

    NSDictionary *abEntry = [aSession originalAddressBookEntry];

    NSString* fontDesc = [abEntry objectForKey:KEY_NORMAL_FONT];
    NSFont* font = [ITAddressBookMgr fontWithDesc:fontDesc];
    NSFont* nafont = [ITAddressBookMgr fontWithDesc:[abEntry objectForKey:KEY_NON_ASCII_FONT]];
    float hs = [[abEntry objectForKey:KEY_HORIZONTAL_SPACING] floatValue];
    float vs = [[abEntry objectForKey:KEY_VERTICAL_SPACING] floatValue];
    PTYSession* session = [frontTerminal currentSession];
    PTYTextView* textview = [session TEXTVIEW];
    [textview setFont:font nafont:nafont horizontalSpacing:hs verticalSpacing:vs];
    [frontTerminal sessionInitiatedResize:session
                                    width:[[abEntry objectForKey:KEY_COLUMNS] intValue]
                                   height:[[abEntry objectForKey:KEY_ROWS] intValue]];
}

- (IBAction)exposeForTabs:(id)sender
{
    [iTermExpose toggle];
}

// Notifications
- (void)reloadMenus:(NSNotification *)aNotification
{
    PseudoTerminal *frontTerminal = [self currentTerminal];
    if (frontTerminal != [aNotification object]) {
        return;
    }
    [previousTerminal setAction: (frontTerminal ? @selector(previousTerminal:) : nil)];
    [nextTerminal setAction: (frontTerminal ? @selector(nextTerminal:) : nil)];

    [self buildSessionSubmenu: aNotification];
    // reset the close tab/window shortcuts
    [closeTab setAction:@selector(closeCurrentTab:)];
    [closeTab setTarget:frontTerminal];
    [closeTab setKeyEquivalent:@"w"];
    [closeWindow setKeyEquivalent:@"W"];
    [closeWindow setKeyEquivalentModifierMask: NSCommandKeyMask];


    // set some menu item states
    if (frontTerminal && [[frontTerminal tabView] numberOfTabViewItems]) {
        [toggleBookmarksView setEnabled:YES];
        [sendInputToAllSessions setEnabled:YES];
        if ([frontTerminal sendInputToAllSessions] == YES) {
            [sendInputToAllSessions setState: NSOnState];
        } else {
            [sendInputToAllSessions setState: NSOffState];
        }
    } else {
        [toggleBookmarksView setEnabled:NO];
        [sendInputToAllSessions setEnabled:NO];
    }
}

- (void) nonTerminalWindowBecameKey: (NSNotification *) aNotification
{
    [closeTab setAction:nil];
    [closeTab setKeyEquivalent:@""];
    [closeWindow setKeyEquivalent:@"w"];
    [closeWindow setKeyEquivalentModifierMask:NSCommandKeyMask];
}

- (void)buildSessionSubmenu:(NSNotification *)aNotification
{
    [self updateMaximizePaneMenuItem];

    // build a submenu to select tabs
    PseudoTerminal *currentTerminal = [self currentTerminal];

    if (currentTerminal != [aNotification object] ||
        ![[currentTerminal window] isKeyWindow]) {
        return;
    }

    NSMenu *aMenu = [[NSMenu alloc] initWithTitle: @"SessionMenu"];
    PTYTabView *aTabView = [currentTerminal tabView];
    NSArray *tabViewItemArray = [aTabView tabViewItems];
    NSEnumerator *enumerator = [tabViewItemArray objectEnumerator];
    NSTabViewItem *aTabViewItem;
    int i=1;

    // clear whatever menu we already have
    [selectTab setSubmenu: nil];

    while ((aTabViewItem = [enumerator nextObject])) {
        PTYTab *aTab = [aTabViewItem identifier];
        NSMenuItem *aMenuItem;

        if (i < 10 && [aTab activeSession]) {
            aMenuItem  = [[NSMenuItem alloc] initWithTitle:[[aTab activeSession] name]
                                                    action:@selector(selectSessionAtIndexAction:)
                                             keyEquivalent:@""];
            [aMenuItem setTag:i-1];
            [aMenu addItem:aMenuItem];
            [aMenuItem release];
        }
        i++;
    }

    [selectTab setSubmenu:aMenu];

    [aMenu release];
}

- (void)_removeItemsFromMenu:(NSMenu*)menu
{
    while ([menu numberOfItems] > 0) {
        NSMenuItem* item = [menu itemAtIndex:0];
        NSMenu* sub = [item submenu];
        if (sub) {
            [self _removeItemsFromMenu:sub];
        }
        [menu removeItemAtIndex:0];
    }
}

- (void)updateAddressBookMenu:(NSNotification*)aNotification
{
    JournalParams params;
    params.selector = @selector(newSessionInTabAtIndex:);
    params.openAllSelector = @selector(newSessionsInWindow:);
    params.alternateSelector = @selector(newSessionInWindowAtIndex:);
    params.alternateOpenAllSelector = @selector(newSessionsInWindow:);
    params.target = [iTermController sharedInstance];

    [BookmarkModel applyJournal:[aNotification userInfo]
                         toMenu:bookmarkMenu
                 startingAtItem:5
                         params:&params];
}

// This is called whenever a tab becomes key or logging starts/stops.
- (void)reloadSessionMenus:(NSNotification *)aNotification
{
    [self updateMaximizePaneMenuItem];

    PseudoTerminal *currentTerminal = [self currentTerminal];
    PTYSession* aSession = [aNotification object];

    if (currentTerminal != [[aSession tab] parentWindow] ||
        ![[currentTerminal window] isKeyWindow]) {
        return;
    }

    if (aSession == nil || [aSession exited]) {
        [logStart setEnabled: NO];
        [logStop setEnabled: NO];
    } else {
        [logStart setEnabled: ![aSession logging]];
        [logStop setEnabled: [aSession logging]];
    }
}

- (void)makeHotKeyWindowKeyIfOpen
{
    for (PseudoTerminal* term in [self terminals]) {
        if ([term isHotKeyWindow] && [[term window] alphaValue] == 1) {
            [[term window] makeKeyAndOrderFront:self];
        }
    }
}

- (void)updateMaximizePaneMenuItem
{
    [maximizePane setState:[[[[iTermController sharedInstance] currentTerminal] currentTab] hasMaximizedPane] ? NSOnState : NSOffState];
}

- (void)updateUseTransparencyMenuItem
{
    [useTransparency setState:[[[iTermController sharedInstance] currentTerminal] useTransparency] ? NSOnState : NSOffState];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    if (menuItem == maximizePane) {
        if ([[[iTermController sharedInstance] currentTerminal] inInstantReplay]) {
            // Things get too complex if you allow this. It crashes.
            return NO;
        } else if ([[[[iTermController sharedInstance] currentTerminal] currentTab] hasMaximizedPane]) {
            return YES;
        } else if ([[[[iTermController sharedInstance] currentTerminal] currentTab] hasMultipleSessions]) {
            return YES;
        } else {
            return NO;
        }
    } else {
        return YES;
    }
}

- (IBAction)buildScriptMenu:(id)sender
{
    if ([[[[NSApp mainMenu] itemAtIndex: 5] title] isEqualToString:NSLocalizedStringFromTableInBundle(@"Script",@"iTerm", [NSBundle bundleForClass: [iTermController class]], @"Script")])
            [[NSApp mainMenu] removeItemAtIndex:5];

        // add our script menu to the menu bar
    // get image
    NSImage *scriptIcon = [NSImage imageNamed: @"script"];
    [scriptIcon setScalesWhenResized: YES];
    [scriptIcon setSize: NSMakeSize(16, 16)];

    // create menu item with no title and set image
    NSMenuItem *scriptMenuItem = [[NSMenuItem alloc] initWithTitle: @"" action: nil keyEquivalent: @""];
    [scriptMenuItem setImage: scriptIcon];

    // create submenu
    int count = 0;
    NSMenu *scriptMenu = [[NSMenu alloc] initWithTitle: NSLocalizedStringFromTableInBundle(@"Script",@"iTerm", [NSBundle bundleForClass: [iTermController class]], @"Script")];
    [scriptMenuItem setSubmenu: scriptMenu];
    // populate the submenu with ascripts found in the script directory
    NSDirectoryEnumerator *directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtPath: [SCRIPT_DIRECTORY stringByExpandingTildeInPath]];
    NSString *file;

    while ((file = [directoryEnumerator nextObject])) {
        if ([[NSWorkspace sharedWorkspace] isFilePackageAtPath:[NSString stringWithFormat:@"%@/%@",
                                                                [SCRIPT_DIRECTORY stringByExpandingTildeInPath],
                                                                file]]) {
                [directoryEnumerator skipDescendents];
        }
        if ([[file pathExtension] isEqualToString: @"scpt"] ||
            [[file pathExtension] isEqualToString: @"app"] ) {
            NSMenuItem *scriptItem = [[NSMenuItem alloc] initWithTitle:file
                                                                action:@selector(launchScript:)
                                                         keyEquivalent:@""];
            [scriptItem setTarget:[iTermController sharedInstance]];
            [scriptMenu addItem:scriptItem];
            count++;
            [scriptItem release];
        }
    }
    if (count > 0) {
            [scriptMenu addItem:[NSMenuItem separatorItem]];
            NSMenuItem *scriptItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Refresh",
                                                                                                          @"iTerm",
                                                                                                          [NSBundle bundleForClass:[iTermController class]],
                                                                                                          @"Script")
                                                                action:@selector(buildScriptMenu:)
                                                         keyEquivalent:@""];
            [scriptItem setTarget:self];
            [scriptMenu addItem:scriptItem];
            count++;
            [scriptItem release];
    }
    [scriptMenu release];

    // add new menu item
    if (count) {
        [[NSApp mainMenu] insertItem:scriptMenuItem atIndex:5];
        [scriptMenuItem release];
        [scriptMenuItem setTitle:NSLocalizedStringFromTableInBundle(@"Script",
                                                                    @"iTerm",
                                                                    [NSBundle bundleForClass:[iTermController class]],
                                                                    @"Script")];
    }
}

- (IBAction)saveWindowArrangement:(id)sender
{
    [[iTermController sharedInstance] saveWindowArrangement];
}

- (IBAction)loadWindowArrangement:(id)sender
{
    [[iTermController sharedInstance] loadWindowArrangement];
}

// TODO(georgen): Disable "Edit Current Session..." when there are no current sessions.
- (IBAction)editCurrentSession:(id)sender
{
    PseudoTerminal* pty = [[iTermController sharedInstance] currentTerminal];
    if (!pty) {
        return;
    }
    [pty editCurrentSession:sender];
}


@end

// Scripting support
@implementation iTermApplicationDelegate (KeyValueCoding)

- (BOOL)application:(NSApplication *)sender delegateHandlesKey:(NSString *)key
{
    //NSLog(@"iTermApplicationDelegate: delegateHandlesKey: '%@'", key);
    return [[iTermController sharedInstance] application:sender delegateHandlesKey:key];
}

// accessors for to-one relationships:
- (PseudoTerminal *)currentTerminal
{
    //NSLog(@"iTermApplicationDelegate: currentTerminal");
    return [[iTermController sharedInstance] currentTerminal];
}

- (void) setCurrentTerminal: (PseudoTerminal *) aTerminal
{
    //NSLog(@"iTermApplicationDelegate: setCurrentTerminal '0x%x'", aTerminal);
    [[iTermController sharedInstance] setCurrentTerminal: aTerminal];
}


// accessors for to-many relationships:
- (NSArray*)terminals
{
    return [[iTermController sharedInstance] terminals];
}

-(void)setTerminals: (NSArray*)terminals
{
    // no-op
}

// accessors for to-many relationships:
// (See NSScriptKeyValueCoding.h)
-(id)valueInTerminalsAtIndex:(unsigned)idx
{
    return [[iTermController sharedInstance] valueInTerminalsAtIndex:idx];
}

-(void)replaceInTerminals:(PseudoTerminal *)object atIndex:(unsigned)idx
{
    [[iTermController sharedInstance] replaceInTerminals:object atIndex:idx];
}

- (void)addInTerminals:(PseudoTerminal *) object
{
    [[iTermController sharedInstance] addInTerminals:object];
}

- (void)insertInTerminals:(PseudoTerminal *) object
{
    [[iTermController sharedInstance] insertInTerminals:object];
}

-(void)insertInTerminals:(PseudoTerminal *)object atIndex:(unsigned)idx
{
    [[iTermController sharedInstance] insertInTerminals:object atIndex:idx];
}

-(void)removeFromTerminalsAtIndex:(unsigned)idx
{
    // NSLog(@"iTerm: removeFromTerminalsAtInde %d", idx);
    [[iTermController sharedInstance] removeFromTerminalsAtIndex: idx];
}

// a class method to provide the keys for KVC:
+(NSArray*)kvcKeys
{
    return [[iTermController sharedInstance] kvcKeys];
}


@end

@implementation iTermApplicationDelegate (Find_Actions)

- (IBAction) showFindPanel: (id) sender
{
        [[iTermController sharedInstance] showHideFindBar];
}

// findNext and findPrevious are reversed here because in the search UI next
// goes backwards and previous goes forwards.
// Internally, next=forward and prev=backwards.
- (IBAction)findPrevious:(id)sender
{
    PseudoTerminal* pty = [[iTermController sharedInstance] currentTerminal];
    if (pty) {
        [[pty currentSession] searchNext];
    }
}

- (IBAction)findNext:(id)sender
{
    PseudoTerminal* pty = [[iTermController sharedInstance] currentTerminal];
    if (pty) {
        [[pty currentSession] searchPrevious];
    }
}

- (IBAction)findWithSelection:(id)sender
{
    NSString* selection = [[[[[iTermController sharedInstance] currentTerminal] currentSession] TEXTVIEW] selectedText];
    if (selection) {
        for (PseudoTerminal* pty in [[iTermController sharedInstance] terminals]) {
            for (PTYSession* session in [pty sessions]) {
                [session useStringForFind:selection];
            }
        }
    }
}

- (IBAction) jumpToSelection: (id) sender
{
    [[FindCommandHandler sharedInstance] jumpToSelection];
}

@end

@implementation iTermApplicationDelegate (MoreActions)

- (void)newSessionInTabAtIndex:(id)sender
{
    [[iTermController sharedInstance] newSessionInTabAtIndex:sender];
}

- (void)newSessionInWindowAtIndex: (id) sender
{
    [[iTermController sharedInstance] newSessionInWindowAtIndex:sender];
}

@end
