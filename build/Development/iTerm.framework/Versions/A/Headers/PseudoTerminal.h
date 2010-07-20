// -*- mode:objc -*-
// $Id: PseudoTerminal.h,v 1.62 2009-02-06 15:07:24 delx Exp $
/*
 **  PseudoTerminal.h
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **	     Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: Session and window controller for iTerm.
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
#import <iTerm/PTYTabView.h>
#import <iTerm/PTYWindow.h>

@class PTYSession, iTermController, PTToolbarController, PSMTabBarControl;

@interface PseudoTerminal : NSWindowController <PTYTabViewDelegateProtocol, PTYWindowDelegateProtocol>
{
	
	NSOutlineView *bookmarksView;
	
	// Parameter Panel
	IBOutlet NSTextField *parameterName;
	IBOutlet NSPanel     *parameterPanel;
	IBOutlet NSTextField *parameterValue;
	IBOutlet NSTextField *parameterPrompt;
	
    /// tab view
    PTYTabView *TABVIEW;
	PSMTabBarControl *tabBarControl;
    PTToolbarController* _toolbarController;
	IBOutlet id commandField;

    
    /////////////////////////////////////////////////////////////////////////
    int WIDTH, HEIGHT;
	int charWidth;
	int charHeight;
	float charHorizontalSpacingMultiplier, charVerticalSpacingMultiplier;
    NSFont *FONT, *NAFONT;
	BOOL antiAlias;
	BOOL useTransparency;
	BOOL blur;
	
	BOOL _fullScreen;
    
    BOOL windowInited;
	BOOL sendInputToAllSessions;
	BOOL fontSizeFollowWindowResize;
	BOOL suppressContextualMenu;
	BOOL tempTitle;
	
	// For send input to all sessions highlighting
	NSColor *normalBackgroundColor;
	
	// flags
	BOOL _resizeInProgressFlag;
	
	// for full screen windows
	NSRect oldFrame;
	int oldWidth, oldHeight;
	float oldCharHorizontalSpacingMultiplier, oldCharVerticalSpacingMultiplier;
	NSFont *oldFont, *oldNAFont;
}


- (id)init;
- (id) initWithWindowNibName: (NSString *) windowNibName;
- (PTYTabView*) initViewWithFrame: (NSRect) frame;
- (void)dealloc;

- (void)initWindowWithAddressbook:(NSDictionary *)entry;
- (void)initWindowWithSettingsFrom:(PseudoTerminal *)aPseudoTerminal;
- (void)setupSession: (PTYSession *) aSession title: (NSString *)title;
- (void) insertSession: (PTYSession *) aSession atIndex: (int) index;
- (void) closeSession: (PTYSession*) aSession;
- (IBAction) closeCurrentSession: (id) sender;
- (IBAction) previousSession:(id)sender;
- (IBAction) nextSession:(id)sender;
- (PTYSession *) currentSession;
- (int) currentSessionIndex;
- (NSString *) currentSessionName;
- (void) setCurrentSessionName: (NSString *) theSessionName;

- (void) updateCurrentSessionProfiles;

- (void)startProgram:(NSString *)program;
- (void)startProgram:(NSString *)program
           arguments:(NSArray *)prog_argv;
- (void)startProgram:(NSString *)program
                  arguments:(NSArray *)prog_argv
                environment:(NSDictionary *)prog_env;
- (void)setWindowSize;
- (void)setWindowTitle;
- (void)setWindowTitle: (NSString *)title;
- (void)setFont:(NSFont *)font nafont:(NSFont *)nafont;
- (void) setCharacterSpacingHorizontal: (float) horizontal vertical: (float) vertical;
- (void) changeFontSize: (BOOL) increase;
- (float) largerSizeForSize: (float) aSize;
- (float) smallerSizeForSize: (float) aSize;
- (NSFont *) font;
- (NSFont *) nafont;
- (NSFont *) oldFont;
- (NSFont *) oldNAFont;
- (BOOL) antiAlias;
- (void) setAntiAlias: (BOOL) bAntiAlias;
- (int)width;
- (int)height;
- (NSRect)oldFrame;
- (int)oldWidth;
- (int)oldHeight;
- (void)setWidth:(int)width height:(int)height;
- (void)setCharSizeUsingFont: (NSFont *)font;
- (int)charWidth;
- (int)charHeight;
- (float) charSpacingVertical;
- (float) charSpacingHorizontal;
- (float) oldCharSpacingVertical;
- (float) oldCharSpacingHorizontal;
- (BOOL) useTransparency;
- (void) setUseTransparency: (BOOL) flag;
- (BOOL) blur;
- (void) setBlur: (BOOL) flag;
- (void) enableBlur;
- (void) disableBlur;
- (BOOL) tempTitle;
- (void) resetTempTitle;

// controls which sessions see key events
- (BOOL) sendInputToAllSessions;
- (void) setSendInputToAllSessions: (BOOL) flag;
- (IBAction) toggleInputToAllSessions: (id) sender;
- (void) sendInputToAllSessions: (NSData *) data;

// controls resize behavior
- (BOOL) fontSizeFollowWindowResize;
- (void) setFontSizeFollowWindowResize: (BOOL) flag;
- (IBAction) toggleFontSizeFollowWindowResize: (id) sender;

// full screen support
- (IBAction) toggleFullScreen:(id)sender;
- (BOOL) fullScreen;

// iTermController
- (void)clearBuffer:(id)sender;
- (void)clearScrollbackBuffer:(id)sender;
- (IBAction)logStart:(id)sender;
- (IBAction)logStop:(id)sender;
- (BOOL)validateMenuItem:(NSMenuItem *)item;

// NSWindow
- (void)windowDidDeminiaturize:(NSNotification *)aNotification;
- (BOOL)windowShouldClose:(NSNotification *)aNotification;
- (void)windowWillClose:(NSNotification *)aNotification;
- (void)windowWillMiniaturize:(NSNotification *)aNotification;
- (void)windowDidBecomeKey:(NSNotification *)aNotification;
- (void)windowDidResignMain:(NSNotification *)aNotification;
- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)proposedFrameSize;
- (void)windowDidResize:(NSNotification *)aNotification;
- (void) resizeWindow:(int)w height:(int)h;
- (void) resizeWindowToPixelsWidth:(int)w height:(int)h;
- (NSRect)windowWillUseStandardFrame:(NSWindow *)sender defaultFrame:(NSRect)defaultFrame;
- (void)windowWillShowInitial;

// Contextual menu
- (void) menuForEvent:(NSEvent *)theEvent menu: (NSMenu *) theMenu;
- (BOOL) suppressContextualMenu;
- (void) setSuppressContextualMenu: (BOOL) aBool;
- (NSMenu *)tabView:(NSTabView *)aTabView menuForTabViewItem:(NSTabViewItem *)tabViewItem;


// Close Window
- (BOOL)showCloseWindow;

// NSTabView
- (PTYTabView *) tabView;
- (void) closeTabContextualMenuAction: (id) sender;
- (void) moveTabToNewWindowContextualMenuAction: (id) sender;
- (PSMTabBarControl*) tabBarControl;
- (void) setLabelColor: (NSColor *) color forTabViewItem: tabViewItem;

// Bookmarks
- (IBAction) toggleBookmarksView: (id) sender;
-  (id) commandField;

// Utility methods
+ (void) breakDown:(NSString *)cmdl cmdPath: (NSString **) cmd cmdArgs: (NSArray **) path;

@end

@interface PseudoTerminal (KeyValueCoding)

// accessors for attributes:
-(int)columns;
-(void)setColumns: (int)columns;
-(int)rows;
-(void)setRows: (int)rows;

// accessors for to-many relationships:
// (See NSScriptKeyValueCoding.h)
-(id)valueInSessionsAtIndex:(unsigned)index;
-(id)valueWithName: (NSString *)uniqueName inPropertyWithKey: (NSString*)propertyKey;
-(id)valueWithID: (NSString *)uniqueID inPropertyWithKey: (NSString*)propertyKey;
-(void)addNewSession:(NSDictionary *)addressbookEntry;
-(void)addNewSession:(NSDictionary *)addressbookEntry withURL: (NSString *)url;
-(void)addNewSession:(NSDictionary *) addressbookEntry withCommand: (NSString *)command;
-(void)appendSession:(PTYSession *)object;
-(void)removeFromSessionsAtIndex:(unsigned)index;
-(NSArray*)sessions;
-(void)setSessions: (NSArray*)sessions;
-(void)replaceInSessions:(PTYSession *)object atIndex:(unsigned)index;
-(void)addInSessions:(PTYSession *)object;
-(void)insertInSessions:(PTYSession *)object;
-(void)insertInSessions:(PTYSession *)object atIndex:(unsigned)index;

- (BOOL)windowInited;
- (void) setWindowInited: (BOOL) flag;

// a class method to provide the keys for KVC:
+(NSArray*)kvcKeys;

@end

@interface PseudoTerminal (Private)

- (void) _commonInit;
- (NSFont *) _getMaxFont:(NSFont* ) font 
				  height:(float) height
				   lines:(float) lines;
- (void) hideMenuBar;

@end

@interface PseudoTerminal (ScriptingSupport)

// Object specifier
- (NSScriptObjectSpecifier *)objectSpecifier;

-(void)handleSelectScriptCommand: (NSScriptCommand *)command;

-(void)handleLaunchScriptCommand: (NSScriptCommand *)command;

@end

