// -*- mode:objc -*-
// $Id: iTermController.m,v 1.78 2008-10-17 04:02:45 yfabian Exp $
/*
 **  iTermController.m
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
#import <iTerm/Tree.h>
#import <iTerm/ITConfigPanelController.h>
#import <iTerm/iTermGrowlDelegate.h>
#import <iTermProfileWindowController.h>
#import <iTermBookmarkController.h>


@interface NSApplication (Undocumented)
- (void)_cycleWindowsReversed:(BOOL)back;
@end


static NSString* APPLICATION_SUPPORT_DIRECTORY = @"~/Library/Application Support";
static NSString *SUPPORT_DIRECTORY = @"~/Library/Application Support/iTerm";
static NSString *SCRIPT_DIRECTORY = @"~/Library/Application Support/iTerm/Scripts";

// Comparator for sorting encodings
static int _compareEncodingByLocalizedName(id a, id b, void *unused)
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
	if(!shared && initDone) {
		NSLog(@"Bad call to [iTermController sharedInstance]");
	}

	return shared;
}

+ (void)sharedInstanceRelease
{
	[shared release];
	shared = nil;
}


// init
- (id) init
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
	NSEnumerator* iterator;
	PseudoTerminal* terminal;

	// Close all terminal windows
	iterator = [terminalWindows objectEnumerator];
	while(terminal = [iterator nextObject]) {
		[[terminal window] close];
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
    [self launchBookmark:[sender representedObject] inTerminal:FRONT];
}

- (void)newSessionInWindowAtIndex: (id) sender
{
    [self launchBookmark:[sender representedObject] inTerminal:nil];
}

// Open all childs within a given window
- (PseudoTerminal *) newSessionsInWindow:(PseudoTerminal *) terminal forNode:(TreeNode*)theNode
{
	NSEnumerator *entryEnumerator;
	NSDictionary *dataDict;
	TreeNode *childNode;
	PseudoTerminal *term =terminal;
	
	entryEnumerator = [[theNode children] objectEnumerator];
	
	while ((childNode = [entryEnumerator nextObject]))
	{
		dataDict = [childNode nodeData];
		if([childNode isGroup])
		{
			[self newSessionsInWindow:terminal forNode:childNode];
		}
		else
		{
			if (!term) {
				term = [[PseudoTerminal alloc] init];
				[term initWindowWithAddressbook: [childNode nodeData]];
				[self addInTerminals: term];
				[term release];
			}
			[self launchBookmark:[childNode nodeData] inTerminal:term];
		}
	}
	
	return term;
}

- (void) newSessionsInWindow: (id) sender
{
	[self newSessionsInWindow:FRONT forNode:[sender representedObject]];
}

- (void) newSessionsInNewWindow: (id) sender
{
	[self newSessionsInWindow:nil forNode:[sender representedObject]];
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

- (PseudoTerminal *) currentTerminal
{
    return (FRONT);
}

- (void) terminalWillClose: (PseudoTerminal *) theTerminalWindow
{
    if(FRONT == theTerminalWindow)
		[self setCurrentTerminal: nil];
	
    if(theTerminalWindow)
        [self removeFromTerminalsAtIndex: [terminalWindows indexOfObject: theTerminalWindow]];
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

- (void) alternativeMenu: (NSMenu *)aMenu forNode: (TreeNode *) theNode target: (id) aTarget withShortcuts: (BOOL) withShortcuts
{
    NSMenu *subMenu;
	NSMenuItem *aMenuItem;
	NSEnumerator *entryEnumerator;
	NSDictionary *dataDict;
	TreeNode *childNode;
	NSString *shortcut;
	unsigned int modifierMask = NSCommandKeyMask | NSControlKeyMask;
	int count = 0;
    
	entryEnumerator = [[theNode children] objectEnumerator];
	
	while ((childNode = [entryEnumerator nextObject]))
	{
		count ++;
		dataDict = [childNode nodeData];
		aMenuItem = [[[NSMenuItem alloc] initWithTitle: [dataDict objectForKey: KEY_NAME] action:@selector(newSessionInTabAtIndex:) keyEquivalent:@""] autorelease];
		if([childNode isGroup])
		{
			subMenu = [[[NSMenu alloc] init] autorelease];
            [self alternativeMenu: subMenu forNode: childNode target: aTarget withShortcuts: withShortcuts]; 
			[aMenuItem setSubmenu: subMenu];
			[aMenuItem setAction:@selector(noAction:)];
			[aMenuItem setTarget: self];
			[aMenu addItem: aMenuItem];
			
		}
		else
		{
            if(withShortcuts)
			{
				if ([dataDict objectForKey: KEY_SHORTCUT] != nil)
				{
					shortcut=[dataDict objectForKey: KEY_SHORTCUT];
					shortcut = [shortcut lowercaseString];
                    
					[aMenuItem setKeyEquivalent: shortcut];
				}
			}
			
            [aMenuItem setKeyEquivalentModifierMask: modifierMask];
            [aMenuItem setRepresentedObject: dataDict];
			[aMenuItem setTarget: aTarget];
			[aMenu addItem: aMenuItem];
			
			aMenuItem = [[aMenuItem copy] autorelease];
			[aMenuItem setKeyEquivalentModifierMask: modifierMask | NSAlternateKeyMask];
			[aMenuItem setAlternate:YES];
			[aMenuItem setAction: @selector(newSessionInWindowAtIndex:)];
			[aMenuItem setTarget: self];
			[aMenu addItem: aMenuItem];
		}                
	}
	
	if (count>1) {
		[aMenu addItem:[NSMenuItem separatorItem]];
		aMenuItem = [[[NSMenuItem alloc] initWithTitle: NSLocalizedStringFromTableInBundle(@"Open All",@"iTerm", [NSBundle bundleForClass: [iTermController class]], @"Context Menu") action:@selector(newSessionsInWindow:) keyEquivalent:@""] autorelease];
		[aMenuItem setKeyEquivalentModifierMask: modifierMask];
		[aMenuItem setRepresentedObject: theNode];
		[aMenuItem setTarget: self];
		[aMenu addItem: aMenuItem];
		aMenuItem = [[aMenuItem copy] autorelease];
		[aMenuItem setKeyEquivalentModifierMask: modifierMask | NSAlternateKeyMask];
		[aMenuItem setAlternate:YES];
		[aMenuItem setAction: @selector(newSessionsInNewWindow:)];
		[aMenuItem setTarget: self];
		[aMenu addItem: aMenuItem];
	}
	
}

// Executes an addressbook command in new window or tab
- (void) launchBookmark: (NSDictionary *) bookmarkData inTerminal: (PseudoTerminal *) theTerm
{
    PseudoTerminal *term;
    NSDictionary *aDict;
	
	aDict = bookmarkData;
	if(aDict == nil)
		aDict = [[ITAddressBookMgr sharedInstance] defaultBookmarkData];
	
	// Where do we execute this command?
    if(theTerm == nil)
    {
        term = [[PseudoTerminal alloc] init];
		[term initWindowWithAddressbook: aDict];
		[self addInTerminals: term];
		[term release];
		
    }
    else
        term = theTerm;
	
	[term addNewSession: aDict];
}

- (void) launchBookmark: (NSDictionary *) bookmarkData inTerminal: (PseudoTerminal *) theTerm withCommand: (NSString *)command
{
    PseudoTerminal *term;
    NSDictionary *aDict;
	
	aDict = bookmarkData;
	if(aDict == nil)
		aDict = [[ITAddressBookMgr sharedInstance] defaultBookmarkData];
	
	// Where do we execute this command?
    if(theTerm == nil)
    {
        term = [[PseudoTerminal alloc] init];
		[term initWindowWithAddressbook: aDict];
		[self addInTerminals: term];
		[term release];
		
    }
    else
        term = theTerm;
	
	[term addNewSession: aDict withCommand: command];
}

- (void) launchBookmark: (NSDictionary *) bookmarkData inTerminal: (PseudoTerminal *) theTerm withURL: (NSString *)url
{
    PseudoTerminal *term;
    NSDictionary *aDict;
	
	aDict = bookmarkData;
	if(aDict == nil || [[aDict objectForKey:KEY_COMMAND] isEqualToString:@"$$"]) {
		NSMutableDictionary *tempDict = [NSMutableDictionary dictionaryWithDictionary: aDict ? aDict : [[ITAddressBookMgr sharedInstance] defaultBookmarkData]];
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
    if(theTerm == nil)
    {
        term = [[PseudoTerminal alloc] init];
		[term initWindowWithAddressbook: aDict];
		[self addInTerminals: term];
		[term release];
		
    }
    else
        term = theTerm;
	
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
-(id)valueInTerminalsAtIndex:(unsigned)index
{
    //NSLog(@"iTerm: valueInTerminalsAtIndex %d: %@", index, [terminalWindows objectAtIndex: index]);
    return ([terminalWindows objectAtIndex: index]);
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

-(void)replaceInTerminals:(PseudoTerminal *)object atIndex:(unsigned)index
{
    // NSLog(@"iTerm: replaceInTerminals 0x%x atIndex %d", object, index);
    [terminalWindows replaceObjectAtIndex: index withObject: object];
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

-(void)insertInTerminals:(PseudoTerminal *)object atIndex:(unsigned)index
{
    if([terminalWindows containsObject: object] == YES)
		return;
    
	[terminalWindows insertObject: object atIndex: index];
    // make sure we have a window
    [object initWindowWithAddressbook:NULL];
}

-(void)removeFromTerminalsAtIndex:(unsigned)index
{
    // NSLog(@"iTerm: removeFromTerminalsAtInde %d", index);
    [terminalWindows removeObjectAtIndex: index];
    if([terminalWindows count] == 0)
		[ITConfigPanelController close];
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

