// -*- mode:objc -*-
// $Id: iTermApplicationDelegate.m,v 1.70 2008-10-23 04:57:13 yfabian Exp $
/*
 **  iTermApplicationDelegate.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **	     Initial code by Kiichi Kusama
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
#import <iTerm/FindPanelWindowController.h>
#import <iTerm/PTYWindow.h>
#import <iTermProfileWindowController.h>
#import <iTermBookmarkController.h>
#import <iTermDisplayProfileMgr.h>
#import <Tree.h>

#include <unistd.h>

static NSString *SCRIPT_DIRECTORY = @"~/Library/Application Support/iTerm/Scripts";
static NSString* AUTO_LAUNCH_SCRIPT = @"~/Library/Application Support/iTerm/AutoLaunch.scpt";

static BOOL usingAutoLaunchScript = NO;

#define ABOUT_SCROLL_FPS	30.0
#define ABOUT_SCROLL_RATE	1.0


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
	[iTermProfileWindowController sharedInstance];
    [iTermBookmarkController sharedInstance];
    [PreferencePanel sharedInstance];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
		
    id prefs = [NSUserDefaults standardUserDefaults];
    NSString *version = [prefs objectForKey: @"Last Updated Version"];
    
    if (!version || ![version isEqualToString:[prefs objectForKey: @"iTerm Version"]]) {
        [prefs setObject:[prefs objectForKey: @"iTerm Version"] forKey:@"Last Updated Version"];
        [self showAbout:nil];
    }
    
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
       [[NSFileManager defaultManager] fileExistsAtPath: [AUTO_LAUNCH_SCRIPT stringByExpandingTildeInPath]] != nil)
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
	[[iTermController sharedInstance] launchBookmark:[bm nodeData] inTerminal:[[iTermController sharedInstance] currentTerminal] withURL:urlStr];
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
    [[iTermBookmarkController sharedInstance] showWindow];
}

- (IBAction)showProfileWindow:(id)sender
{
    [[iTermProfileWindowController sharedInstance] showProfilesWindow: nil];
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
    [[iTermController sharedInstance] alternativeMenu: bookmarksMenu 
                                              forNode: [[ITAddressBookMgr sharedInstance] rootNode] 
                                               target: frontTerminal
                                        withShortcuts: NO];
	[newMenuItem setSubmenu: bookmarksMenu];

	[bookmarksMenu addItem: [NSMenuItem separatorItem]];
    
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
    [[[iTermController sharedInstance] currentTerminal] changeFontSize: YES];
}

- (IBAction) smallerFont: (id) sender
{
    [[[iTermController sharedInstance] currentTerminal] changeFontSize: NO];
}

// transparency
- (IBAction) useTransparency: (id) sender
{
	[[[iTermController sharedInstance] currentTerminal] setUseTransparency:![sender state]];
	
  // Post a notification
  [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermWindowDidResize" object: self userInfo: nil];    
}


/// About window

- (IBAction)showAbout:(id)sender
{
	// check if an About window is shown already
	if (aboutController) return;
	
    NSURL *webURL, *bugURL;
    NSAttributedString *webSite, *bugReport;
    NSAttributedString *tmpAttrString;
    NSDictionary *linkAttributes, *otherAttributes;
//    [NSApp orderFrontStandardAboutPanel:nil];

	otherAttributes= [NSDictionary dictionaryWithObjectsAndKeys: [NSCursor pointingHandCursor], NSCursorAttributeName,
		NULL];
	
    // Web URL
    webURL = [NSURL URLWithString: @"http://iterm.sourceforge.net"];
    linkAttributes= [NSDictionary dictionaryWithObjectsAndKeys: webURL, NSLinkAttributeName,
                        [NSNumber numberWithInt: NSSingleUnderlineStyle], NSUnderlineStyleAttributeName,
					    [NSColor blueColor], NSForegroundColorAttributeName,
						[NSCursor pointingHandCursor], NSCursorAttributeName,
					    NULL];
    webSite = [[NSAttributedString alloc] initWithString: @"http://iterm.sourceforge.net" attributes: linkAttributes];

    // Bug report
    bugURL = [NSURL URLWithString: @"http://iterm.sourceforge.net/tracker-bug"];
    linkAttributes= [NSDictionary dictionaryWithObjectsAndKeys: bugURL, NSLinkAttributeName,
        [NSNumber numberWithInt: NSSingleUnderlineStyle], NSUnderlineStyleAttributeName,
        [NSColor blueColor], NSForegroundColorAttributeName,
		[NSCursor pointingHandCursor], NSCursorAttributeName,
        NULL];
    bugReport = [[NSAttributedString alloc] initWithString: NSLocalizedStringFromTableInBundle(@"Report A Bug", @"iTerm", [NSBundle bundleForClass: [self class]], @"About") attributes: linkAttributes];

    // version number and mode
    NSDictionary *myDict = [[NSBundle bundleForClass:[self class]] infoDictionary];
    NSString *versionString = [@"Build " stringByAppendingString: (NSString *)[myDict objectForKey:@"CFBundleVersion"]];
    
    [[AUTHORS textStorage] deleteCharactersInRange: NSMakeRange(0, [[AUTHORS textStorage] length])];
    tmpAttrString = [[[NSAttributedString alloc] initWithString: versionString attributes: otherAttributes] autorelease];
    [[AUTHORS textStorage] appendAttributedString: tmpAttrString];
    tmpAttrString = [[[NSAttributedString alloc] initWithString: @"\n\n" attributes: otherAttributes] autorelease];
    [[AUTHORS textStorage] appendAttributedString: tmpAttrString];
    [[AUTHORS textStorage] appendAttributedString: webSite];
    tmpAttrString = [[[NSAttributedString alloc] initWithString: @"\n" attributes: otherAttributes] autorelease];
    [[AUTHORS textStorage] appendAttributedString: tmpAttrString];
    [[AUTHORS textStorage] appendAttributedString: bugReport];
    [AUTHORS setAlignment: NSCenterTextAlignment range: NSMakeRange(0, [[AUTHORS textStorage] length])];

	[[scrollingInfo enclosingScrollView] setLineScroll:0.0];
    [[scrollingInfo enclosingScrollView] setPageScroll:0.0];
	[[scrollingInfo enclosingScrollView] setVerticalScroller:nil];
    
    //Start scrolling    
    scrollLocation = 0; 
    scrollRate = ABOUT_SCROLL_RATE;
    maxScroll = [[scrollingInfo textStorage] size].height - [[scrollingInfo enclosingScrollView] documentVisibleRect].size.height;
    scrollTimer = [[NSTimer scheduledTimerWithTimeInterval:(1.0/ABOUT_SCROLL_FPS)
													target:self
												  selector:@selector(_scrollTimer:)
												  userInfo:nil
												   repeats:YES] retain];
	eventLoopScrollTimer = [[NSTimer timerWithTimeInterval:(1.0/ABOUT_SCROLL_FPS)
													target:self
												  selector:@selector(_scrollTimer:)
												  userInfo:nil
												   repeats:YES] retain];
    [[NSRunLoop currentRunLoop] addTimer:eventLoopScrollTimer forMode:NSEventTrackingRunLoopMode];
	
    aboutController = [[NSWindowController alloc] initWithWindow:ABOUT];
    [aboutController showWindow:ABOUT];

    [webSite release];	
	
	
}

- (IBAction)aboutOK:(id)sender
{
    [ABOUT close];
	[scrollTimer invalidate]; [scrollTimer release]; scrollTimer = nil;
	[eventLoopScrollTimer invalidate]; [eventLoopScrollTimer release]; eventLoopScrollTimer = nil;
	[aboutController release];
	aboutController = nil;
}

// size
- (IBAction) returnToDefaultSize: (id) sender
{
    PseudoTerminal *frontTerminal = [[iTermController sharedInstance] currentTerminal];
    NSDictionary *abEntry = [[frontTerminal currentSession] addressBookEntry];
    NSString *displayProfile = [abEntry objectForKey: KEY_DISPLAY_PROFILE];
    iTermDisplayProfileMgr *displayProfileMgr = [iTermDisplayProfileMgr singleInstance];

    if(displayProfile == nil)
        displayProfile = [displayProfileMgr defaultProfileName];
    
    [frontTerminal setFont: [displayProfileMgr windowFontForProfile: displayProfile] 
                    nafont: [displayProfileMgr windowNAFontForProfile: displayProfile]];
    [frontTerminal resizeWindow: [displayProfileMgr windowColumnsForProfile: displayProfile]
                         height: [displayProfileMgr windowRowsForProfile: displayProfile]];
					
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
		[toggleTransparency setEnabled:YES];
		[fontSizeFollowWindowResize setEnabled:YES];
		[sendInputToAllSessions setEnabled:YES];

		if([frontTerminal sendInputToAllSessions] == YES)
		[sendInputToAllSessions setState: NSOnState];
		else
		[sendInputToAllSessions setState: NSOffState];

		if([frontTerminal fontSizeFollowWindowResize] == YES)
			[fontSizeFollowWindowResize setState: NSOnState];
		else
			[fontSizeFollowWindowResize setState: NSOffState];
		
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
		[toggleTransparency setEnabled:NO];
		[fontSizeFollowWindowResize setEnabled:NO];
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

- (void) buildAddressBookMenu : (NSNotification *) aNotification
{
    // clear Bookmark menu
    for (; [bookmarkMenu numberOfItems]>7;) [bookmarkMenu removeItemAtIndex: 7];
    
    // add bookmarks into Bookmark menu
    [[iTermController sharedInstance] alternativeMenu: bookmarkMenu 
                                              forNode: [[ITAddressBookMgr sharedInstance] rootNode] 
                                               target: [[iTermController sharedInstance] currentTerminal] 
                                        withShortcuts: YES];    
}

- (void) reloadSessionMenus: (NSNotification *) aNotification
{
	PseudoTerminal *currentTerminal = [self currentTerminal];
    PTYSession *aSession = [aNotification object];

	if (currentTerminal != [aSession parent] || ![[currentTerminal window] isKeyWindow]) return;

    if(aSession == nil || [aSession exited]) {
		[logStart setEnabled: NO];
		[logStop setEnabled: NO];
		[toggleTransparency setEnabled: NO];
	}
	else {
		[logStart setEnabled: ![aSession logging]];
		[logStop setEnabled: [aSession logging]];
		[toggleTransparency setState: [currentTerminal useTransparency] ? NSOnState : NSOffState];
		[toggleTransparency setEnabled: YES];
	}
}

- (BOOL) validateMenuItem: (NSMenuItem *) menuItem
{
  if ([menuItem action] == @selector(useTransparency:)) 
  {
    BOOL b = [[[iTermController sharedInstance] currentTerminal] useTransparency];
    [menuItem setState: b == YES ? NSOnState : NSOffState];
  }
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
    [[FindPanelWindowController sharedInstance] showWindow:self];
}

- (IBAction) findNext: (id) sender
{
    [[FindCommandHandler sharedInstance] findNext];
}

- (IBAction) findPrevious: (id) sender
{
    [[FindCommandHandler sharedInstance] findPrevious];
}

- (IBAction) findWithSelection: (id) sender
{
    [[FindCommandHandler sharedInstance] findWithSelection];
}

- (IBAction) jumpToSelection: (id) sender
{
    [[FindCommandHandler sharedInstance] jumpToSelection];
}

@end

@implementation iTermApplicationDelegate (MoreActions)

- (void) newSessionInTabAtIndex: (id) sender
{
    [[iTermController sharedInstance] newSessionInTabAtIndex:sender];
}

- (void)newSessionInWindowAtIndex: (id) sender
{
    [[iTermController sharedInstance] newSessionInWindowAtIndex:sender];
}

@end

@implementation iTermApplicationDelegate (Private)

//Scroll the credits
- (void)_scrollTimer:(NSTimer *)scrollTimer
{    
	scrollLocation += scrollRate;
	
	if (scrollLocation > maxScroll) scrollLocation = 0;    
	if (scrollLocation < 0) scrollLocation = maxScroll;
	
	[scrollingInfo scrollPoint:NSMakePoint(0, scrollLocation)];
}

@end
