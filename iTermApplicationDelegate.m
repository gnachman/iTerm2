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
#import <BookmarksWindow.h>

#include <unistd.h>

static NSString *SCRIPT_DIRECTORY = @"~/Library/Application Support/iTerm/Scripts";
static NSString* AUTO_LAUNCH_SCRIPT = @"~/Library/Application Support/iTerm/AutoLaunch.scpt";

NSMutableString* gDebugLogStr = nil;
NSMutableString* gDebugLogStr2 = nil;
static BOOL usingAutoLaunchScript = NO;
BOOL gDebugLogging = NO;
int gDebugLogFile = -1;


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
        [self buildAddressBookMenu:nil];

        // register for services
        [NSApp registerServicesMenuSendTypes: [NSArray arrayWithObjects: NSStringPboardType, nil]
                                                         returnTypes: [NSArray arrayWithObjects: NSFilenamesPboardType, NSStringPboardType, nil]];

}

- (BOOL) applicationShouldTerminate: (NSNotification *) theNotification
{
        NSArray *terminals;

        terminals = [[iTermController sharedInstance] terminals];

        // Display prompt if we need to
    if ([[PreferencePanel sharedInstance] promptOnClose] && [terminals count] && (![[PreferencePanel sharedInstance] onlyWhenMoreTabs] || [terminals count] >1 || 
                                                             [[[[iTermController sharedInstance] currentTerminal] tabView] numberOfTabViewItems] > 1 )
        && 
            NSRunAlertPanel(NSLocalizedStringFromTableInBundle(@"Quit iTerm?",@"iTerm", [NSBundle bundleForClass: [self class]], @"Close window"),
                                           NSLocalizedStringFromTableInBundle(@"All sessions will be closed",@"iTerm", [NSBundle bundleForClass: [self class]], @"Close window"),
                                           NSLocalizedStringFromTableInBundle(@"OK",@"iTerm", [NSBundle bundleForClass: [self class]], @"OK"),
                                           NSLocalizedStringFromTableInBundle(@"Cancel",@"iTerm", [NSBundle bundleForClass: [self class]], @"Cancel")
                                           ,nil)!=NSAlertDefaultReturn)
                return (NO);

        // Ensure [iTermController dealloc] is called before prefs are saved
        [iTermController sharedInstanceRelease];

        // save preferences
        [[PreferencePanel sharedInstance] savePreferences];

        return (YES);
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
        //NSLog(@"%s: %@", __PRETTY_FUNCTION__, filename);

        if (filename) {
                // Verify whether filename is a script or a folder
                BOOL isDir;
                [[NSFileManager defaultManager] fileExistsAtPath:filename isDirectory:&isDir];
                if (!isDir) {
                        NSString *aString = [NSString stringWithFormat:@"\"%@\"", filename];
                        [[iTermController sharedInstance] launchBookmark:nil inTerminal:nil withCommand:aString];
                }
                else {
                        NSString *aString = [NSString stringWithFormat:@"cd \"%@\"\n", filename];
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
    if(usingAutoLaunchScript == NO &&
       [[NSFileManager defaultManager] fileExistsAtPath: [AUTO_LAUNCH_SCRIPT stringByExpandingTildeInPath]])
    {
                usingAutoLaunchScript = YES;

                NSAppleScript *autoLaunchScript;
                NSDictionary *errorInfo = [NSDictionary dictionary];
                NSURL *aURL = [NSURL fileURLWithPath: [AUTO_LAUNCH_SCRIPT stringByExpandingTildeInPath]];

                // Make sure our script suite registry is loaded
                [NSScriptSuiteRegistry sharedScriptSuiteRegistry];

                autoLaunchScript = [[NSAppleScript alloc] initWithContentsOfURL: aURL error: &errorInfo];
                [autoLaunchScript executeAndReturnError: &errorInfo];
                [autoLaunchScript release];
    }
    else {
        if ([[PreferencePanel sharedInstance] openBookmark])
            [self showBookmarkWindow:nil];
        else
            [self newWindow:nil];
    }
    usingAutoLaunchScript = YES;

    return YES;
}

// sent when application is made visible after a hide operation. Should not really need to implement this,
// but some users reported that keyboard input is blocked after a hide/unhide operation.
- (void)applicationDidUnhide:(NSNotification *)aNotification
{
        // PseudoTerminal *frontTerminal = [[iTermController sharedInstance] currentTerminal];
    // Make sure that the first responder stuff is set up OK.
    // [frontTerminal selectSessionAtIndex: [frontTerminal currentSessionIndex]];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
    return [[PreferencePanel sharedInstance] quitWhenAllWindowsClosed];
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
                                             selector: @selector(buildAddressBookMenu:)
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

        [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self andSelector:@selector(getUrl:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];

        aboutController = nil;

    return self;
}

- (void)getUrl:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
        NSString *urlStr = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
        NSURL *url = [NSURL URLWithString: urlStr];
        NSString *urlType = [url scheme];

        id bm = [[PreferencePanel sharedInstance] handlerBookmarkForURL: urlType];

        //NSLog(@"Got the URL:%@\n%@", urlType, bm);
        [[iTermController sharedInstance] launchBookmark:bm inTerminal:[[iTermController sharedInstance] currentTerminal] withURL:urlStr];
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

- (IBAction)showPrefWindow:(id)sender
{
    [[PreferencePanel sharedInstance] run];
}

- (IBAction)showBookmarkWindow:(id)sender
{
    [[BookmarksWindow sharedInstance] showWindow:sender];
}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender
{
    NSMenu *aMenu, *bookmarksMenu;
    NSMenuItem *newMenuItem;
        PseudoTerminal *frontTerminal;

    aMenu = [[NSMenu alloc] initWithTitle: @"Dock Menu"];
    //new session menu
        newMenuItem = [[NSMenuItem alloc] initWithTitle: NSLocalizedStringFromTableInBundle(@"New",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu") action:nil keyEquivalent:@"" ]; 
    [aMenu addItem: newMenuItem];
    [newMenuItem release];

    // Create the bookmark submenus for new session
        frontTerminal = [[iTermController sharedInstance] currentTerminal];
    // Build the bookmark menu
        bookmarksMenu = [[[NSMenu alloc] init] autorelease];

    [[iTermController sharedInstance] addBookmarksToMenu:bookmarksMenu target:frontTerminal withShortcuts:NO];
        [newMenuItem setSubmenu:bookmarksMenu];

        [bookmarksMenu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *tip = [[[NSMenuItem alloc] initWithTitle: NSLocalizedStringFromTableInBundle(@"Press Option for New Window",@"iTerm", [NSBundle bundleForClass: [self class]], @"Toolbar Item: New") action:@selector(xyz) keyEquivalent: @""] autorelease];
    [tip setKeyEquivalentModifierMask: 0];
    [bookmarksMenu addItem: tip];
    tip = [[tip copy] autorelease];
    [tip setTitle:NSLocalizedStringFromTableInBundle(@"Open In New Window",@"iTerm", [NSBundle bundleForClass: [self class]], @"Toolbar Item: New")];
    [tip setKeyEquivalentModifierMask: NSAlternateKeyMask];
    [tip setAlternate:YES];
    [bookmarksMenu addItem: tip];
    return ([aMenu autorelease]);
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

- (IBAction)showAbout:(id)sender
{
        // check if an About window is shown already
        if (aboutController) return;

    NSURL *webURL, *bugsURL, *creditsURL;
    NSAttributedString *webAString, *bugsAString, *creditsAString;
    NSDictionary *linkTextViewAttributes, *linkAttributes;
    NSString *web = @"http://sites.google.com/site/iterm2home/";
    NSString *bugs = @"http://code.google.com/p/iterm2/issues/entry";
    NSString *credits = @"http://code.google.com/p/iterm2/wiki/Credits";
//    [NSApp orderFrontStandardAboutPanel:nil];

    linkTextViewAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithInt: NSSingleUnderlineStyle], NSUnderlineStyleAttributeName,
                              [NSColor blueColor], NSForegroundColorAttributeName,
                              [NSCursor pointingHandCursor], NSCursorAttributeName,
                              NULL];

    // Web URL
    webURL = [NSURL URLWithString: web];
    linkAttributes = [NSDictionary dictionaryWithObjectsAndKeys: webURL, NSLinkAttributeName, NULL];
    webAString = [[NSAttributedString alloc] initWithString: NSLocalizedStringFromTableInBundle(@"Home Page", @"iTerm", [NSBundle bundleForClass: [self class]], @"About") attributes: linkAttributes];

    // Bug report
    bugsURL = [NSURL URLWithString: bugs];
    linkAttributes = [NSDictionary dictionaryWithObjectsAndKeys: bugsURL, NSLinkAttributeName, NULL];
    bugsAString= [[NSAttributedString alloc] initWithString: NSLocalizedStringFromTableInBundle(@"Report a bug", @"iTerm", [NSBundle bundleForClass: [self class]], @"About") attributes: linkAttributes];

    // Credits
    creditsURL = [NSURL URLWithString: credits];
    linkAttributes = [NSDictionary dictionaryWithObjectsAndKeys: creditsURL, NSLinkAttributeName, NULL];
    creditsAString = [[NSAttributedString alloc] initWithString: NSLocalizedStringFromTableInBundle(@"Credits", @"iTerm", [NSBundle bundleForClass: [self class]], @"About") attributes: linkAttributes];

    // version number and mode
    NSDictionary *myDict = [[NSBundle bundleForClass:[self class]] infoDictionary];
    NSString *versionString = [@"Build " stringByAppendingString: (NSString *)[myDict objectForKey:@"CFBundleVersion"]];

    [AUTHORS setLinkTextAttributes: linkTextViewAttributes];
    [[AUTHORS textStorage] deleteCharactersInRange: NSMakeRange(0, [[AUTHORS textStorage] length])];
    [[AUTHORS textStorage] appendAttributedString: [[NSAttributedString alloc] initWithString: versionString]];
    [[AUTHORS textStorage] appendAttributedString: [[NSAttributedString alloc] initWithString: @"\n\n"]];
    [[AUTHORS textStorage] appendAttributedString: webAString];
    [[AUTHORS textStorage] appendAttributedString: [[NSAttributedString alloc] initWithString: @"\n"]];
    [[AUTHORS textStorage] appendAttributedString: bugsAString];
    [[AUTHORS textStorage] appendAttributedString: [[NSAttributedString alloc] initWithString: @"\n\n"]];
    [[AUTHORS textStorage] appendAttributedString: creditsAString]; 
    [AUTHORS setAlignment: NSCenterTextAlignment range: NSMakeRange(0, [[AUTHORS textStorage] length])];

    aboutController = [[NSWindowController alloc] initWithWindow:ABOUT];
    [aboutController showWindow:ABOUT];

    [webAString release];
    [bugsAString release];
    [creditsAString release];
}

- (IBAction)aboutOK:(id)sender
{
    [ABOUT close];
    [aboutController release];
    aboutController = nil;
}

// size
- (IBAction) returnToDefaultSize: (id) sender
{
    PseudoTerminal *frontTerminal = [[iTermController sharedInstance] currentTerminal];
    NSDictionary *abEntry = [[frontTerminal currentSession] addressBookEntry];

    NSString* fontDesc = [abEntry objectForKey:KEY_NORMAL_FONT];
    NSFont* font = [ITAddressBookMgr fontWithDesc:fontDesc];
    NSFont* nafont = [ITAddressBookMgr fontWithDesc:[abEntry objectForKey:KEY_NON_ASCII_FONT]];
    float hs = [[abEntry objectForKey:KEY_HORIZONTAL_SPACING] floatValue];
    float vs = [[abEntry objectForKey:KEY_VERTICAL_SPACING] floatValue];
    PTYSession* session = [frontTerminal currentSession];
    PTYTextView* textview = [session TEXTVIEW];
    [textview setFont:font nafont:nafont horizontalSpacing:hs verticalSpacing:vs];
    [session setWidth:[[abEntry objectForKey:KEY_COLUMNS] intValue] height:[[abEntry objectForKey:KEY_ROWS] intValue]];
}


// Notifications
- (void) reloadMenus: (NSNotification *) aNotification
{
        PseudoTerminal *frontTerminal = [self currentTerminal];
    if (frontTerminal != [aNotification object]) return;

        unsigned int drawerState;

        [previousTerminal setAction: (frontTerminal?@selector(previousTerminal:):nil)];
        [nextTerminal setAction: (frontTerminal?@selector(nextTerminal:):nil)];

        [self buildSessionSubmenu: aNotification];
        [self buildAddressBookMenu: aNotification];
        // reset the close tab/window shortcuts
        [closeTab setAction: @selector(closeCurrentSession:)];
        [closeTab setTarget: frontTerminal];
        [closeTab setKeyEquivalent: @"w"];
        [closeWindow setKeyEquivalent: @"W"];
        [closeWindow setKeyEquivalentModifierMask: NSCommandKeyMask];


        // set some menu item states
        if (frontTerminal && [[frontTerminal tabView] numberOfTabViewItems]) {
                [toggleBookmarksView setEnabled:YES];
                [sendInputToAllSessions setEnabled:YES];

                if([frontTerminal sendInputToAllSessions] == YES)
                [sendInputToAllSessions setState: NSOnState];
                else
                [sendInputToAllSessions setState: NSOffState];

                // reword some menu items
                drawerState = [[(PTYWindow *)[frontTerminal window] drawer] state];
                if(drawerState == NSDrawerClosedState || drawerState == NSDrawerClosingState)
                {
                        [toggleBookmarksView setTitle: 
                                NSLocalizedStringFromTableInBundle(@"Show Bookmark Drawer", @"iTerm", [NSBundle bundleForClass: [self class]], @"Bookmarks")];
                }
                else
                {
                        [toggleBookmarksView setTitle: 
                                NSLocalizedStringFromTableInBundle(@"Hide Bookmark Drawer", @"iTerm", [NSBundle bundleForClass: [self class]], @"Bookmarks")];
                }
        }
        else {
                [toggleBookmarksView setEnabled:NO];
                [sendInputToAllSessions setEnabled:NO];
        }
}

- (void) nonTerminalWindowBecameKey: (NSNotification *) aNotification
{
    [closeTab setAction: nil];
    [closeTab setKeyEquivalent: @""];
    [closeWindow setKeyEquivalent: @"w"];
    [closeWindow setKeyEquivalentModifierMask: NSCommandKeyMask];
}

- (void) buildSessionSubmenu: (NSNotification *) aNotification
{
        // build a submenu to select tabs
        PseudoTerminal *currentTerminal = [self currentTerminal];

        if (currentTerminal != [aNotification object] || ![[currentTerminal window] isKeyWindow]) return;

    NSMenu *aMenu = [[NSMenu alloc] initWithTitle: @"SessionMenu"];
    PTYTabView *aTabView = [currentTerminal tabView];
    PTYSession *aSession;
    NSArray *tabViewItemArray = [aTabView tabViewItems];
        NSEnumerator *enumerator = [tabViewItemArray objectEnumerator];
        NSTabViewItem *aTabViewItem;
        int i=1;

    // clear whatever menu we already have
    [selectTab setSubmenu: nil];

        while ((aTabViewItem = [enumerator nextObject])) {
                aSession = [aTabViewItem identifier];
        NSMenuItem *aMenuItem;

        if(i < 10)
        {
            aMenuItem  = [[NSMenuItem alloc] initWithTitle: [aSession name] action: @selector(selectSessionAtIndexAction:) keyEquivalent:@""];
            [aMenuItem setTag: i-1];

            [aMenu addItem: aMenuItem];
            [aMenuItem release];
        }
                i++;
        }

    [selectTab setSubmenu: aMenu];

    [aMenu release];
}

- (void)buildAddressBookMenu:(NSNotification *)aNotification
{
    // clear Bookmark menu
    const int kNumberOfStaticMenuItems = 5;
    for (; [bookmarkMenu numberOfItems] > kNumberOfStaticMenuItems;) [bookmarkMenu removeItemAtIndex:kNumberOfStaticMenuItems];

    // add bookmarks into Bookmark menu
    [[iTermController sharedInstance] addBookmarksToMenu:bookmarkMenu 
                                                  target:[[iTermController sharedInstance] currentTerminal]
                                           withShortcuts:YES];
}

- (void) reloadSessionMenus: (NSNotification *) aNotification
{
        PseudoTerminal *currentTerminal = [self currentTerminal];
    PTYSession *aSession = [aNotification object];

        if (currentTerminal != [aSession parent] || ![[currentTerminal window] isKeyWindow]) return;

    if(aSession == nil || [aSession exited]) {
                [logStart setEnabled: NO];
                [logStop setEnabled: NO];
        }
        else {
                [logStart setEnabled: ![aSession logging]];
                [logStop setEnabled: [aSession logging]];
        }
}

- (BOOL) validateMenuItem: (NSMenuItem *) menuItem
{
  return YES;
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

    while ((file = [directoryEnumerator nextObject]))
    {
                if ([[NSWorkspace sharedWorkspace] isFilePackageAtPath: [NSString stringWithFormat: @"%@/%@", [SCRIPT_DIRECTORY stringByExpandingTildeInPath], file]])
                        [directoryEnumerator skipDescendents];

                if ([[file pathExtension] isEqualToString: @"scpt"] || [[file pathExtension] isEqualToString: @"app"] ) {
                        NSMenuItem *scriptItem = [[NSMenuItem alloc] initWithTitle: file action: @selector(launchScript:) keyEquivalent: @""];
                        [scriptItem setTarget: [iTermController sharedInstance]];
                        [scriptMenu addItem: scriptItem];
                        count ++;
                        [scriptItem release];
                }
    }
        if (count>0) {
                [scriptMenu addItem:[NSMenuItem separatorItem]];
                NSMenuItem *scriptItem = [[NSMenuItem alloc] initWithTitle: NSLocalizedStringFromTableInBundle(@"Refresh",@"iTerm", [NSBundle bundleForClass: [iTermController class]], @"Script")
                                                                                                                        action: @selector(buildScriptMenu:) 
                                                                                                         keyEquivalent: @""];
                [scriptItem setTarget: self];
                [scriptMenu addItem: scriptItem];
                count ++;
                [scriptItem release];
        }
        [scriptMenu release];

    // add new menu item
    if (count) {
        [[NSApp mainMenu] insertItem: scriptMenuItem atIndex: 5];
        [scriptMenuItem release];
        [scriptMenuItem setTitle: NSLocalizedStringFromTableInBundle(@"Script",@"iTerm", [NSBundle bundleForClass: [iTermController class]], @"Script")];
    }
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

- (IBAction) findNext: (id) sender
{
    PseudoTerminal* pty = [[iTermController sharedInstance] currentTerminal];
    if (pty) {
        [pty searchNext:nil];
    }
}

- (IBAction) findPrevious: (id) sender
{
    PseudoTerminal* pty = [[iTermController sharedInstance] currentTerminal];
    if (pty) {
        [pty searchPrevious:nil];
    }
}

- (IBAction) findWithSelection: (id) sender
{
    PseudoTerminal* pty = [[iTermController sharedInstance] currentTerminal];
    if (pty) {
        [pty findWithSelection];
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
