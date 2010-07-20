/*
 **  FindPanelWindowController.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: Implements the find functions.
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

#import <iTerm/iTermController.h>
#import <iTerm/PTYTextView.h>
#import <iTerm/FindPanelWindowController.h>

#define DEBUG_ALLOC	0

static FindPanelWindowController *sharedInstance = nil;

@implementation FindPanelWindowController

//
// class methods
//
+ (id) sharedInstance
{
    if ( !sharedInstance )
	sharedInstance = [[self alloc] initWithWindowNibName: @"FindPanel"];

    return sharedInstance;
}

- (id) initWithWindowNibName: (NSString *) windowNibName
{
#if DEBUG_ALLOC
    NSLog(@"FindPanelWindowController: -initWithWindowNibName");
#endif

    self = [super initWithWindowNibName: windowNibName];

    // We finally set our autosave window frame name and restore the one from the user's defaults.
    [[self window] setFrameAutosaveName: @"FindPanel"];
    [[self window] setFrameUsingName: @"FindPanel"];

    [[self window] setDelegate: self];
        
    return (self);
}

- (void) dealloc
{
#if DEBUG_ALLOC
    NSLog(@"FindPanelWindowController: -dealloc");
#endif

    sharedInstance = nil;

    [super dealloc];
}

// NSWindow delegate methods
- (void)windowWillClose:(NSNotification *)aNotification
{
    [self autorelease];
}

- (void)windowDidLoad
{
    NSPasteboard *board = [NSPasteboard pasteboardWithName:NSFindPboard];
    NSString* findString = [board stringForType:NSStringPboardType];
    if ([findString length])
    {
        [self setSearchString:findString];	
        [[FindCommandHandler sharedInstance] setSearchString:findString];
    }
    
    [caseCheckBox setIntValue:[[FindCommandHandler sharedInstance] ignoresCase]];
    
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName: @"nonTerminalWindowBecameKey" object: nil userInfo: nil];        
}

- (IBAction)ignoreCaseSwitchAction:(id)sender;
{
    [[FindCommandHandler sharedInstance] setIgnoresCase:[sender intValue]];
}

// action methods
- (IBAction) findNext: (id) sender
{
    NSString* searchString = [self searchString];
    if([searchString length] <= 0)
    {
        NSBeep();
        return;
    }
    
    [[FindCommandHandler sharedInstance] setSearchString:searchString];
    [[FindCommandHandler sharedInstance] findNext];
	[[self window] close];
}

- (IBAction)findPrevious: (id) sender
{
    NSString* searchString = [self searchString];
    if([searchString length] <= 0)
    {
	NSBeep();
	return;
    }
    
    [[FindCommandHandler sharedInstance] setSearchString:searchString];
    [[FindCommandHandler sharedInstance] findPrevious];
	[[self window] close];
}

// get/set methods
- (id) delegate
{
    return (delegate);
}

- (void) setDelegate: (id) theDelegate
{
    delegate = theDelegate;
}

- (void)setSearchString: (NSString *) aString
{    
    if (aString && [aString length]>0) {
		[searchStringField setStringValue: aString];
		
	}		
    else
        [searchStringField setStringValue: @""];
}

- (NSString*)searchString;
{
	NSString *aString = [searchStringField stringValue];
	
	if ([aString length]>0) {
		NSPasteboard *pboard = [NSPasteboard pasteboardWithName: NSFindPboard];
		
		[pboard declareTypes: [NSArray arrayWithObject: NSStringPboardType] owner: self];
		[pboard setString: aString forType: NSStringPboardType];
	}
    return aString;
}

@end

// ==========================================================================================

@implementation FindCommandHandler : NSObject

- (id)init;
{
    self = [super init];
    
    _ignoresCase = [[NSUserDefaults standardUserDefaults] boolForKey:@"findIgnoreCase_iTerm"];

    return self;
}

- (void)dealloc;
{
    [_searchString release];

    [super dealloc];
}

+ (id)sharedInstance;
{
    static id shared = nil;
    
    if (!shared)
        shared = [[FindCommandHandler alloc] init];
    
    return shared;
}

- (PTYTextView*)currentTextView;
{
    id obj = [[NSApp mainWindow] firstResponder];
    return (obj && [obj isKindOfClass:[PTYTextView class]]) ? obj : nil;
}

- (IBAction) findNext
{
    [self findSubString: _searchString forwardDirection: YES ignoringCase: _ignoresCase];
}

- (IBAction) findPrevious
{
    [self findSubString: _searchString forwardDirection: NO ignoringCase: _ignoresCase];
}

- (IBAction) findWithSelection
{
    PTYTextView* textView = [self currentTextView];
    if (textView)
    {
        // get the selected text
        NSString *contentString = [textView selectedText];
		if (!contentString) {
            NSBeep();
            return;
        }
        [self setSearchString: contentString];
        [self findNext];
    }
    else
        NSBeep();
}

- (IBAction)jumpToSelection
{
    PTYTextView* textView = [self currentTextView];
    if (textView)
    {        
		[textView scrollToSelection];
    }
    else
        NSBeep();
}

- (void) findSubString: (NSString *) subString forwardDirection: (BOOL) direction ignoringCase: (BOOL) caseCheck
{
    PTYTextView* textView = [self currentTextView];
    if (textView)
    {        
        if ([subString length] <= 0)
        {
            NSBeep();
            return;
        }
        
		[textView findString:subString forwardDirection: direction ignoringCase: caseCheck];
	}
}

- (NSString*)searchString;
{
    return _searchString;
}

- (void) setSearchString: (NSString *) aString
{
	    
    [_searchString release];
    _searchString = [aString retain];
}

- (BOOL)ignoresCase;
{    
    return _ignoresCase;
}

- (void)setIgnoresCase:(BOOL)set;
{    
    _ignoresCase = set;
    [[NSUserDefaults standardUserDefaults] setBool:set forKey:@"findIgnoreCase_iTerm"];
}

@end


