/*
 **  iTermProfileWindowController.h
 **
 **  Copyright (c) 2002, 2003, 2004
 **
 **  Author: Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: Header file for profile window controller.
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

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#define KEYBOARD_PROFILE_TAB		0
#define TERMINAL_PROFILE_TAB		1
#define DISPLAY_PROFILE_TAB			2

@interface iTermProfileWindowController : NSWindowController 
{
    NSUserDefaults *_prefs;

	IBOutlet NSTabView *profileTabView;
	IBOutlet NSOutlineView *profileOutline;

	// Add Profile panel
	IBOutlet NSPanel *addProfile;
	IBOutlet NSPopUpButton *addProfileCategory;
	IBOutlet NSTextField *profileName;
    
    IBOutlet NSButton *deleteButton;
    IBOutlet NSButton *duplicateButton;
    
	// Keybinding profile UI
	IBOutlet NSPanel *addKBEntry;
	IBOutlet NSPopUpButton *kbEntryKey;
	IBOutlet NSButton *kbEntryKeyModifierOption;
	IBOutlet NSButton *kbEntryKeyModifierControl;
	IBOutlet NSButton *kbEntryKeyModifierShift;
	IBOutlet NSButton *kbEntryKeyModifierCommand;
	IBOutlet NSPopUpButton *kbEntryAction;
	IBOutlet NSTextField *kbEntryText;
	IBOutlet NSTextField *kbEntryKeyCode;
	IBOutlet NSTextField *kbEntryHint;
	IBOutlet NSTableView *kbEntryTableView;
	IBOutlet NSButton *kbEntryDeleteButton;
	IBOutlet NSMatrix *kbOptionKey;
	IBOutlet NSButton *kbEntryHighPriority;
	
	// Display profile UI
	IBOutlet NSColorWell *displayFGColor;
	IBOutlet NSColorWell *displayBGColor;
	IBOutlet NSColorWell *displayBoldColor;
	IBOutlet NSColorWell *displaySelectionColor;
	IBOutlet NSColorWell *displaySelectedTextColor;
	IBOutlet NSColorWell *displayCursorColor;
	IBOutlet NSColorWell *displayCursorTextColor;
	IBOutlet NSColorWell *displayAnsi0Color;
	IBOutlet NSColorWell *displayAnsi1Color;
	IBOutlet NSColorWell *displayAnsi2Color;
	IBOutlet NSColorWell *displayAnsi3Color;
	IBOutlet NSColorWell *displayAnsi4Color;
	IBOutlet NSColorWell *displayAnsi5Color;
	IBOutlet NSColorWell *displayAnsi6Color;
	IBOutlet NSColorWell *displayAnsi7Color;
	IBOutlet NSColorWell *displayAnsi8Color;
	IBOutlet NSColorWell *displayAnsi9Color;
	IBOutlet NSColorWell *displayAnsi10Color;
	IBOutlet NSColorWell *displayAnsi11Color;
	IBOutlet NSColorWell *displayAnsi12Color;
	IBOutlet NSColorWell *displayAnsi13Color;
	IBOutlet NSColorWell *displayAnsi14Color;
	IBOutlet NSColorWell *displayAnsi15Color;
	IBOutlet NSTextField *displayTransparency;
	IBOutlet NSButton *displayUseBackgroundImage;
    IBOutlet NSImageView *displayBackgroundImage;
	IBOutlet NSTextField *displayColTextField;
	IBOutlet NSTextField *displayRowTextField;
	IBOutlet NSTextField *displayFontTextField;
	IBOutlet NSTextField *displayNAFontTextField;
	IBOutlet NSView *displayFontAccessoryView;
	IBOutlet NSSlider *displayFontSpacingWidth;
	IBOutlet NSSlider *displayFontSpacingHeight;
	IBOutlet NSButton *displayAntiAlias;
	IBOutlet NSButton *displayBlur;
	IBOutlet NSButton *displayDisableBold;
	
	BOOL changingNAFont;
	
	// Terminal Profile UI
	IBOutlet NSComboBox *terminalType;
	IBOutlet NSPopUpButton *terminalEncoding;
	IBOutlet NSTextField *terminalScrollback;
	IBOutlet NSButton *terminalSilenceBell;
	IBOutlet NSButton *terminalShowBell;
	IBOutlet NSButton *terminalEnableGrowl;
	IBOutlet NSButton *terminalBlink;
	IBOutlet NSButton *terminalCloseOnSessionEnd;
	IBOutlet NSButton *terminalDoubleWidth;
	IBOutlet NSButton *terminalSendIdleChar;
	IBOutlet NSTextField *terminalIdleChar;
	IBOutlet NSButton *terminalAppendTitle;
	IBOutlet NSButton *terminalNoResizing;
	IBOutlet NSButton *xtermMouseReporting;

    NSString *selectedProfile;
}

+ (iTermProfileWindowController*)sharedInstance;
- (IBAction) showProfilesWindow: (id) sender;

// profile editing
- (IBAction) profileAdd: (id) sender;
- (IBAction) profileDelete: (id) sender;
- (IBAction) profileAddConfirm: (id) sender;
- (IBAction) profileAddCancel: (id) sender;
- (IBAction) profileDuplicate: (id) sender;

// Keybinding profile UI
- (void) kbOptionKeyChanged: (id) sender;
- (void) kbProfileChangedTo: (NSString *) profile;
- (IBAction) kbEntryAdd: (id) sender;
- (IBAction) kbEntryEdit: (id) sender;
- (IBAction) kbEntryAddConfirm: (id) sender;
- (IBAction) kbEntryAddCancel: (id) sender;
- (IBAction) kbEntryDelete: (id) sender;
- (IBAction) kbEntrySelectorChanged: (id) sender;

// Display profile UI
- (void) displayProfileChangedTo: (NSString *) profile;
- (IBAction) displaySetAntiAlias: (id) sender;
- (IBAction) displaySetBlur: (id) sender;
- (IBAction) displaySetDisableBold: (id) sender;
- (IBAction) displayChangeColor: (id) sender;
- (IBAction) displayBackgroundImage: (id) sender;
- (IBAction) displaySelectFont: (id) sender;
- (IBAction) displaySelectNAFont: (id) sender;
- (IBAction) displaySetFontSpacing: (id) sender;
// NSTextField delegate
- (void)controlTextDidChange:(NSNotification *)aNotification;

// Terminal profile UI
- (void) terminalProfileChangedTo: (NSString *) profile;
- (IBAction) terminalSetType: (id) sender;
- (IBAction) terminalSetEncoding: (id) sender;
- (IBAction) terminalSetSilenceBell: (id) sender;
- (IBAction) terminalSetShowBell: (id) sender;
- (IBAction) terminalSetEnableGrowl: (id) sender;
- (IBAction) terminalSetBlink: (id) sender;
- (IBAction) terminalSetCloseOnSessionEnd: (id) sender;
- (IBAction) terminalSetDoubleWidth: (id) sender;
- (IBAction) terminalSetSendIdleChar: (id) sender;
- (IBAction) terminalSetXtermMouseReporting: (id) sender;
- (IBAction) terminalSetAppendTitle: (id) sender;
- (IBAction) terminalSetNoResizing: (id) sender;

- (void)selectProfile:(NSString *)profile withInCategory: (int) category;

@end

@interface iTermProfileWindowController (Private)

- (void)_addProfileSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void)_deleteProfileSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;

- (void)_addKBEntrySheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;

- (void) _updateFontsDisplay;

- (void) _chooseBackgroundImageForProfile: (NSString *) theProfile;

@end

