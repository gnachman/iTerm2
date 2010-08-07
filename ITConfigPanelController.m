/*
 **  ITConfigPanelController.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **	     Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: controls the config sheet.
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

#import "ITConfigPanelController.h"
#import "ITViewLocalizer.h"
#import "ITAddressBookMgr.h"
#import "iTermController.h"
#import "PTYSession.h"
#import "PseudoTerminal.h"
#import "VT100Screen.h"
#import "PTYTextView.h"
#import "PTYScrollView.h"
#import "iTermDisplayProfileMgr.h"
#import "iTermTerminalProfileMgr.h"

static ITConfigPanelController *singleInstance = nil;
static BOOL onScreen = NO;

@implementation ITConfigPanelController

+ (void)show
{
    // controller will be deleted when closed
	if(singleInstance == nil)
	{
		singleInstance = [[ITConfigPanelController alloc] initWithWindowNibName:@"ITConfigPanel"];
		// Add ourselves as an observer for notifications.
		[[NSNotificationCenter defaultCenter] addObserver:singleInstance
												 selector:@selector(loadConfigWindow:)
													 name:@"iTermWindowBecameKey"
												   object:nil];		
		[[NSNotificationCenter defaultCenter] addObserver:singleInstance
												 selector:@selector(loadConfigWindow:)
													 name:@"iTermSessionBecameKey"
												   object:nil];		
		[[NSNotificationCenter defaultCenter] addObserver:singleInstance
												 selector:@selector(loadConfigWindow:)
													 name:@"iTermWindowDidResize"
												   object:nil];				
	}
	
    [singleInstance loadConfigWindow: nil];
	
	[[singleInstance window] setFrameAutosaveName: @"Config Panel"];
	[[singleInstance window] setLevel:NSFloatingWindowLevel];
	[[singleInstance window] makeKeyAndOrderFront: self];
    onScreen = YES;
}

+ (void) close
{
	if(singleInstance != nil)
	{
		[[singleInstance window] performClose: self];
	}
}

+ (BOOL) onScreen
{
    return onScreen;
}

+ (id) singleInstance
{
	return singleInstance;
}


- (id)init
{
    self = [super init];
    
    return self;
}

- (void)dealloc
{
    [backgroundImagePath release];
    backgroundImagePath = nil;
	[[NSNotificationCenter defaultCenter] removeObserver: self];
	singleInstance = nil;
    [super dealloc];
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName: @"nonTerminalWindowBecameKey" object: nil userInfo: nil];        
}

- (void)windowWillClose:(NSNotification *)notification
{
	[[NSColorPanel sharedColorPanel] close];
	[[NSFontPanel sharedFontPanel] close];
    onScreen = NO;
	
    // since this NSWindowController doesn't have a document, the releasing is not automatic when the window closes
    [self autorelease];
}

- (void)windowDidLoad
{
    [ITViewLocalizer localizeWindow:[self window] table:@"configPanel" bundle:[NSBundle bundleForClass: [self class]]];
}


// actions
- (IBAction) setWindowSize: (id) sender
{
    if ([CONFIG_COL intValue] < 1 || [CONFIG_ROW intValue] < 1)
    {
        NSRunAlertPanel(NSLocalizedStringFromTableInBundle(@"Wrong Input",@"iTerm", [NSBundle bundleForClass: [self class]], @"wrong input"),
                        NSLocalizedStringFromTableInBundle(@"Please enter a valid window size",@"iTerm", [NSBundle bundleForClass: [self class]], @"wrong input"),
                        NSLocalizedStringFromTableInBundle(@"OK",@"iTerm", [NSBundle bundleForClass: [self class]], @"OK"),
                        nil,nil);
		
		return;
    }
	
	// resize the window if asked for
	if(([_pseudoTerminal width] != [CONFIG_COL intValue]) || ([_pseudoTerminal height] != [CONFIG_ROW intValue]))
		[_pseudoTerminal resizeWindow:[CONFIG_COL intValue] height:[CONFIG_ROW intValue]];
	
}

- (IBAction) setCharacterSpacing: (id) sender
{
	[_pseudoTerminal setCharacterSpacingHorizontal: [charHorizontalSpacing floatValue] 
										  vertical: [charVerticalSpacing floatValue]];
	//[_pseudoTerminal setFont:configFont nafont:configNAFont];
	[_pseudoTerminal resizeWindow:[CONFIG_COL intValue] height:[CONFIG_ROW intValue]];
}

- (IBAction) toggleAntiAlias: (id) sender
{
	[_pseudoTerminal setAntiAlias: ([CONFIG_ANTIALIAS state] == NSOnState)];
}

- (IBAction) setTransparency: (id) sender
{
	int tr = [sender intValue];
	[[_pseudoTerminal currentSession] setTransparency: (float)tr/100.0];
	if(sender == CONFIG_TRANS2)
		[CONFIG_TRANSPARENCY setIntValue:tr];
	else if (sender == CONFIG_TRANSPARENCY)
		[CONFIG_TRANS2 setIntValue:tr];
}

- (IBAction) setBlur: (id) sender
{
	[_pseudoTerminal setBlur: ([CONFIG_BLUR state] == NSOnState)];
}

- (IBAction) setBold: (id) sender
{
	[[_pseudoTerminal currentSession] setDisableBold: ([boldButton state] == NSOffState)];
    [CONFIG_BOLD setEnabled:[boldButton state]];
}

- (IBAction) updateProfile: (id) sender
{
    [_pseudoTerminal updateCurrentSessionProfiles];
}

- (IBAction) setForegroundColor: (id) sender
{
	[CONFIG_EXAMPLE setTextColor:[CONFIG_FOREGROUND color]];
    [CONFIG_NAEXAMPLE setTextColor:[CONFIG_FOREGROUND color]];
	[[_pseudoTerminal currentSession] setForegroundColor:  [CONFIG_FOREGROUND color]];
}

- (IBAction) setBackgroundColor: (id) sender
{
	NSColor *bgColor;
	
	// set the background color for the scrollview with the appropriate transparency
	bgColor = [[CONFIG_BACKGROUND color] colorWithAlphaComponent: (1-[CONFIG_TRANSPARENCY floatValue]/100.0)];
	[[[_pseudoTerminal currentSession] SCROLLVIEW] setBackgroundColor: bgColor];
	[[_pseudoTerminal currentSession] setBackgroundColor:  bgColor];
	[[[_pseudoTerminal currentSession] TEXTVIEW] setNeedsDisplay:YES];
	
	[CONFIG_EXAMPLE setBackgroundColor:[CONFIG_BACKGROUND color]];
    [CONFIG_NAEXAMPLE setBackgroundColor:[CONFIG_BACKGROUND color]];
}

- (IBAction) setBoldColor: (id) sender
{
	[[_pseudoTerminal currentSession] setBoldColor: [CONFIG_BOLD color]];
}

- (IBAction) setSelectionColor: (id) sender
{
	[[[_pseudoTerminal currentSession] TEXTVIEW] setSelectionColor: [CONFIG_SELECTION color]];
}

- (IBAction) setSelectedTextColor: (id) sender
{
	[[[_pseudoTerminal currentSession] TEXTVIEW] setSelectedTextColor: [CONFIG_SELECTIONTEXT color]];
}

- (IBAction) setCursorColor: (id) sender
{
	[[_pseudoTerminal currentSession] setCursorColor: [CONFIG_CURSOR color]];
}

- (IBAction) setCursorTextColor: (id) sender
{
	[[[_pseudoTerminal currentSession] TEXTVIEW] setCursorTextColor: [CONFIG_CURSORTEXT color]];
}

- (IBAction) setSessionName: (id) sender
{
	[_pseudoTerminal setCurrentSessionName: [CONFIG_NAME stringValue]]; 
}

- (IBAction) setSessionEncoding: (id) sender
{
	[[_pseudoTerminal currentSession] setEncoding:[[CONFIG_ENCODING selectedItem] tag]];
}

- (IBAction) setAntiIdle: (id) sender
{
	[[_pseudoTerminal currentSession] setAntiIdle:([AI_ON state]==NSOnState)];
}

- (IBAction) setAntiIdleCode: (id) sender
{
	[[_pseudoTerminal currentSession] setAntiCode:[AI_CODE intValue]];
}

- (IBAction)windowConfigFont:(id)sender
{
	NSFontPanel *aFontPanel;
	
    changingNA=NO;
    [[CONFIG_EXAMPLE window] makeFirstResponder:[CONFIG_EXAMPLE window]];
    [[CONFIG_EXAMPLE window] setDelegate:self];
	aFontPanel = [[NSFontManager sharedFontManager] fontPanel: YES];
	[aFontPanel setAccessoryView: nil];
    [[NSFontManager sharedFontManager] setSelectedFont:configFont isMultiple:NO];
    [[NSFontManager sharedFontManager] orderFrontFontPanel:self];
	[aFontPanel setLevel:CGShieldingWindowLevel()];
}

- (IBAction)windowConfigNAFont:(id)sender
{
	NSFontPanel *aFontPanel;

    changingNA=YES;
    [[CONFIG_NAEXAMPLE window] makeFirstResponder:[CONFIG_NAEXAMPLE window]];
    [[CONFIG_NAEXAMPLE window] setDelegate:self];
	aFontPanel = [[NSFontManager sharedFontManager] fontPanel: YES];
	[aFontPanel setAccessoryView: nil];
    [[NSFontManager sharedFontManager] setSelectedFont:configNAFont isMultiple:NO];
    [[NSFontManager sharedFontManager] orderFrontFontPanel:self];
	[aFontPanel setLevel:CGShieldingWindowLevel()];
}


- (void)changeFont:(id)sender
{
    if (changingNA)
    {
        configNAFont=[[NSFontManager sharedFontManager] convertFont:configNAFont];
        if (configNAFont!=nil)
        {
            [CONFIG_NAEXAMPLE setStringValue:[NSString stringWithFormat:@"%@ %g", [configNAFont fontName], [configNAFont pointSize]]];
            [CONFIG_NAEXAMPLE setFont:configNAFont];
        }
    }
    else
    {
        configFont=[[NSFontManager sharedFontManager] convertFont:configFont];
        if (configFont!=nil) 
        {
            [CONFIG_EXAMPLE setStringValue:[NSString stringWithFormat:@"%@ %g", [configFont fontName], [configFont pointSize]]];
            [CONFIG_EXAMPLE setFont:configFont];
        }
    }
	
	[_pseudoTerminal setFont:configFont nafont:configNAFont];
	[_pseudoTerminal resizeWindow:[CONFIG_COL intValue] height:[CONFIG_ROW intValue]];
	
}

// background image stuff
- (IBAction) useBackgroundImage: (id) sender
{
	if ([_pseudoTerminal fullScreen]) {
		[useBackgroundImage setState: backgroundImagePath != nil];
		return;
	}
	
    [CONFIG_BACKGROUND setEnabled: ([useBackgroundImage state] == NSOffState)?YES:NO];
    if([useBackgroundImage state]==NSOffState)
    {
		[backgroundImagePath release];
		backgroundImagePath = nil;
		[backgroundImageView setImage: nil];
		[[_pseudoTerminal currentSession] setBackgroundImagePath: @""];
    }
    else 
		[self chooseBackgroundImage: sender];
}

- (IBAction) chooseBackgroundImage: (id) sender
{
    NSOpenPanel *panel;
    int sts;
    NSString *directory, *filename;
	
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[AddressBookWindowController chooseBackgroundImage:%@]",
          __FILE__, __LINE__);
#endif
	
    if([useBackgroundImage state]==NSOffState)
    {
		NSBeep();
		return;
    }
	
    panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection: NO];
		
    directory = NSHomeDirectory();
    filename = [NSString stringWithString: @""];
	
    if([backgroundImagePath length] > 0)
    {
		directory = [backgroundImagePath stringByDeletingLastPathComponent];
		filename = [backgroundImagePath lastPathComponent];
    }    
	
    [backgroundImagePath release];
    backgroundImagePath = nil;
    sts = [panel runModalForDirectory: directory file:filename types: [NSImage imageFileTypes]];
    if (sts == NSOKButton) {
		if([[panel filenames] count] > 0)
		{
			backgroundImagePath = [[NSString alloc] initWithString: [[panel filenames] objectAtIndex: 0]];
		}
		
		if(backgroundImagePath != nil)
		{
			NSImage *anImage = [[NSImage alloc] initWithContentsOfFile: backgroundImagePath];
			if(anImage != nil)
			{
				[backgroundImageView setImage: anImage];
				[anImage release];
				[[_pseudoTerminal currentSession] setBackgroundImagePath: backgroundImagePath];
			}
			else
				NSLog(@"%s: image %@ is nil!", __PRETTY_FUNCTION__, backgroundImagePath);
		}
		else
			[useBackgroundImage setState: NSOffState];
    }
    else
    {
		[useBackgroundImage setState: NSOffState];
    }
	
}


// config panel sheet
- (void)loadConfigWindow: (NSNotification *) aNotification
{
	NSEnumerator *anEnumerator;
	NSNumber *anEncoding;
	
	[self window]; // force window to load
	
    _pseudoTerminal = [[iTermController sharedInstance] currentTerminal]; // don't retain
	if(_pseudoTerminal == nil)
		return;
	
    PTYSession* currentSession = [_pseudoTerminal currentSession];
	
    [CONFIG_FOREGROUND setColor:[[currentSession TEXTVIEW] defaultFGColor]];
    [CONFIG_BACKGROUND setColor:[[currentSession TEXTVIEW] defaultBGColor]];
    [CONFIG_BACKGROUND setEnabled: ([currentSession image] == nil)?YES:NO];
    [CONFIG_SELECTION setColor:[[currentSession TEXTVIEW] selectionColor]];
    [CONFIG_SELECTIONTEXT setColor:[[currentSession TEXTVIEW] selectedTextColor]];
    [CONFIG_BOLD setColor: [[currentSession TEXTVIEW] defaultBoldColor]];
	[CONFIG_CURSOR setColor: [[currentSession TEXTVIEW] defaultCursorColor]];
	[CONFIG_CURSORTEXT setColor: [[currentSession TEXTVIEW] cursorTextColor]];
	
    configFont=[_pseudoTerminal font];
    [CONFIG_EXAMPLE setStringValue:[NSString stringWithFormat:@"%@ %g", [configFont fontName], [configFont pointSize]]];
    [CONFIG_EXAMPLE setTextColor:[[currentSession TEXTVIEW] defaultFGColor]];
    [CONFIG_EXAMPLE setBackgroundColor:[[currentSession TEXTVIEW] defaultBGColor]];
    [CONFIG_EXAMPLE setFont:configFont];
    configNAFont=[_pseudoTerminal nafont];
    [CONFIG_NAEXAMPLE setStringValue:[NSString stringWithFormat:@"%@ %g", [configNAFont fontName], [configNAFont pointSize]]];
    [CONFIG_NAEXAMPLE setTextColor:[[currentSession TEXTVIEW] defaultFGColor]];
    [CONFIG_NAEXAMPLE setBackgroundColor:[[currentSession TEXTVIEW] defaultBGColor]];
    [CONFIG_NAEXAMPLE setFont:configNAFont];
    [CONFIG_COL setIntValue:[_pseudoTerminal width]];
    [CONFIG_ROW setIntValue:[_pseudoTerminal height]];
	[charHorizontalSpacing setFloatValue: [_pseudoTerminal charSpacingHorizontal]];
	[charVerticalSpacing setFloatValue: [_pseudoTerminal charSpacingVertical]];
    [CONFIG_NAME setStringValue:[_pseudoTerminal currentSessionName]];
	
    [CONFIG_ENCODING removeAllItems];
	anEnumerator = [[[iTermController sharedInstance] sortedEncodingList] objectEnumerator];
	while((anEncoding = [anEnumerator nextObject]) != NULL)
	{
        [CONFIG_ENCODING addItemWithTitle: [NSString localizedNameOfStringEncoding: [anEncoding unsignedIntValue]]];
		[[CONFIG_ENCODING lastItem] setTag: [anEncoding unsignedIntValue]];
	}
	[CONFIG_ENCODING selectItemAtIndex: [CONFIG_ENCODING indexOfItemWithTag: [[currentSession TERMINAL] encoding]]];
	
    [CONFIG_TRANSPARENCY setIntValue:((int)([currentSession transparency]*100))];
    [CONFIG_TRANS2 setIntValue:((int)([currentSession transparency]*100))];
    
    [AI_ON setState:[currentSession antiIdle]?NSOnState:NSOffState];
    [AI_CODE setIntValue:[currentSession antiCode]];
    
    [CONFIG_ANTIALIAS setState: [[currentSession TEXTVIEW] antiAlias]];
	[blurButton setState: [_pseudoTerminal blur]];
	
	[boldButton setState: ![currentSession disableBold]];
    [CONFIG_BOLD setEnabled:[boldButton state]];
	
    // background image
    backgroundImagePath = [[currentSession backgroundImagePath] copy];
    if([backgroundImagePath length] > 0)
    {
		NSImage *anImage = [[NSImage alloc] initWithContentsOfFile: backgroundImagePath];
		if(anImage != nil)
		{
			[backgroundImageView setImage: anImage];
			[anImage release];
			[useBackgroundImage setState: NSOnState];
		}
		else
		{
			[backgroundImageView setImage: nil];
			[useBackgroundImage setState: NSOffState];
			[backgroundImagePath release];
			backgroundImagePath = nil;
		}
    }
    else
    {
		[backgroundImageView setImage: nil];
		[useBackgroundImage setState: NSOffState];
		[backgroundImagePath release];
		backgroundImagePath = nil;
    }    

   	
    
    [updateProfileButton setTitle:[NSString stringWithFormat:
        NSLocalizedStringFromTableInBundle(@"Update %@", @"iTerm", [NSBundle bundleForClass: [self class]], @"Info"), 
        [[currentSession addressBookEntry] objectForKey: @"Name"]]];

	[[self window] setLevel: NSFloatingWindowLevel];
	[[self window] setDelegate: self];
    
}

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    [[self window] close];
}

@end
