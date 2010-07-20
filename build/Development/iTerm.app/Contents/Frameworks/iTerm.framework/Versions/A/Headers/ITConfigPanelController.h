/*
 **  ITConfigPanelController.h
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

#import <Cocoa/Cocoa.h>

@class PseudoTerminal;

@interface ITConfigPanelController : NSWindowController 
{
    PseudoTerminal* _pseudoTerminal;
    
    IBOutlet id CONFIG_COL;
    IBOutlet id CONFIG_ROW;
    IBOutlet NSPopUpButton *CONFIG_ENCODING;
    IBOutlet NSColorWell *CONFIG_BACKGROUND;
    IBOutlet NSColorWell *CONFIG_FOREGROUND;
    IBOutlet id CONFIG_EXAMPLE;
    IBOutlet id CONFIG_NAEXAMPLE;
    IBOutlet id CONFIG_TRANSPARENCY;
    IBOutlet id CONFIG_TRANS2;
	IBOutlet id CONFIG_BLUR;
    IBOutlet id CONFIG_NAME;
    IBOutlet id CONFIG_ANTIALIAS;
    IBOutlet NSColorWell *CONFIG_SELECTION;
    IBOutlet NSColorWell *CONFIG_BOLD;
	IBOutlet NSColorWell *CONFIG_CURSOR;
	IBOutlet NSColorWell *CONFIG_CURSORTEXT;
	IBOutlet NSColorWell *CONFIG_SELECTIONTEXT;
	
    
    // anti-idle
    IBOutlet id AI_CODE;
    IBOutlet id AI_ON;
    char ai_code;    
    
    NSFont *configFont, *configNAFont;
    BOOL changingNA;
	IBOutlet NSSlider *charHorizontalSpacing;
	IBOutlet NSSlider *charVerticalSpacing;

    // background image
    IBOutlet NSButton *useBackgroundImage;
    IBOutlet NSImageView *backgroundImageView;
    NSString *backgroundImagePath;
	
	IBOutlet NSButton *boldButton;
	IBOutlet NSButton *transparencyButton;
	IBOutlet NSButton *updateProfileButton;
	IBOutlet NSButton *blurButton;
}

+ (id) singleInstance;

+ (void)show;
+ (void)close;
+ (BOOL)onScreen;

- (void)loadConfigWindow: (NSNotification *) aNotification;


// actions
- (IBAction) setWindowSize: (id) sender;
- (IBAction) setCharacterSpacing: (id) sender;
- (IBAction) toggleAntiAlias: (id) sender;
- (IBAction) setTransparency: (id) sender;
- (IBAction) setBlur: (id) sender;
- (IBAction) setForegroundColor: (id) sender;
- (IBAction) setBackgroundColor: (id) sender;
- (IBAction) setBoldColor: (id) sender;
- (IBAction) setSelectionColor: (id) sender;
- (IBAction) setSelectedTextColor: (id) sender;
- (IBAction) setCursorColor: (id) sender;
- (IBAction) setCursorTextColor: (id) sender;
- (IBAction) setSessionName: (id) sender;
- (IBAction) setSessionEncoding: (id) sender;
- (IBAction) setAntiIdle: (id) sender;
- (IBAction) setAntiIdleCode: (id) sender;
- (IBAction) chooseBackgroundImage: (id) sender;
- (IBAction) windowConfigFont:(id)sender;
- (IBAction) windowConfigNAFont:(id)sender;
- (IBAction) useBackgroundImage: (id) sender;
- (IBAction) setBold: (id) sender;
- (IBAction) updateProfile: (id) sender;

@end
