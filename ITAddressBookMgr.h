/*
 **  ITAddressBookMgr.h
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: keeps track of the address book data.
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
// Notes:
// Empty or bogus font? Use [NSFont userFixedPitchFontOfSize: 0.0]


#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import "ProfileModel.h"
#import "FutureMethods.h"

// Prefs-level keys
#define KEY_DEFAULT_GUID                @"Default Bookmark Guid"  // use this instead (not in a bookmark)
#define KEY_DEPRECATED_BOOKMARKS               @"Bookmarks"
#define KEY_NEW_BOOKMARKS               @"New Bookmarks"

// Bookmark-level keys
#define KEY_CHILDREN                    @"Children"
#define KEY_NAME                        @"Name"
#define KEY_DESCRIPTION                 @"Description"
#define KEY_CUSTOM_COMMAND              @"Custom Command"
#define KEY_COMMAND                     @"Command"
#define KEY_INITIAL_TEXT                @"Initial Text"
#define KEY_CUSTOM_DIRECTORY            @"Custom Directory"  // values are Yes, No, Recycle
#define KEY_WORKING_DIRECTORY           @"Working Directory"
#define KEY_TERMINAL_PROFILE            @"Terminal Profile"
#define KEY_KEYBOARD_PROFILE            @"Keyboard Profile"
#define KEY_DISPLAY_PROFILE             @"Display Profile"
#define KEY_SHORTCUT                    @"Shortcut"
#define KEY_BONJOUR_GROUP               @"Bonjour Group"
#define KEY_BONJOUR_SERVICE             @"Bonjour Service"
#define KEY_BONJOUR_SERVICE_ADDRESS     @"Bonjour Service Address"
#define KEY_TAGS                        @"Tags"
#define KEY_GUID                        @"Guid"
#define KEY_ORIGINAL_GUID               @"Original Guid"  // GUID before divorce. Not saved to preferences plist.
#define KEY_DEFAULT_BOOKMARK            @"Default Bookmark"  // deprecated
#define KEY_ASK_ABOUT_OUTDATED_KEYMAPS  @"Ask About Outdated Keymaps"

// Advanced working directory settings
#define KEY_AWDS_WIN_OPTION             @"AWDS Window Option"
#define KEY_AWDS_WIN_DIRECTORY          @"AWDS Window Directory"
#define KEY_AWDS_TAB_OPTION             @"AWDS Tab Option"
#define KEY_AWDS_TAB_DIRECTORY          @"AWDS Tab Directory"
#define KEY_AWDS_PANE_OPTION            @"AWDS Pane Option"
#define KEY_AWDS_PANE_DIRECTORY         @"AWDS Pane Directory"

// Per-bookmark keys ----------------------------------------------------------
// IMPORATANT: If you add keys, also modify doCopyFrom in PreferencePanel.m.

// Colors
#define KEY_FOREGROUND_COLOR       @"Foreground Color"
#define KEY_BACKGROUND_COLOR       @"Background Color"
#define KEY_BOLD_COLOR             @"Bold Color"
#define KEY_SELECTION_COLOR        @"Selection Color"
#define KEY_SELECTED_TEXT_COLOR    @"Selected Text Color"
#define KEY_CURSOR_COLOR           @"Cursor Color"
#define KEY_CURSOR_TEXT_COLOR      @"Cursor Text Color"
#define KEY_ANSI_0_COLOR           @"Ansi 0 Color"
#define KEY_ANSI_1_COLOR           @"Ansi 1 Color"
#define KEY_ANSI_2_COLOR           @"Ansi 2 Color"
#define KEY_ANSI_3_COLOR           @"Ansi 3 Color"
#define KEY_ANSI_4_COLOR           @"Ansi 4 Color"
#define KEY_ANSI_5_COLOR           @"Ansi 5 Color"
#define KEY_ANSI_6_COLOR           @"Ansi 6 Color"
#define KEY_ANSI_7_COLOR           @"Ansi 7 Color"
#define KEY_ANSI_8_COLOR           @"Ansi 8 Color"
#define KEY_ANSI_9_COLOR           @"Ansi 9 Color"
#define KEY_ANSI_10_COLOR          @"Ansi 10 Color"
#define KEY_ANSI_11_COLOR          @"Ansi 11 Color"
#define KEY_ANSI_12_COLOR          @"Ansi 12 Color"
#define KEY_ANSI_13_COLOR          @"Ansi 13 Color"
#define KEY_ANSI_14_COLOR          @"Ansi 14 Color"
#define KEY_ANSI_15_COLOR          @"Ansi 15 Color"
#define KEYTEMPLATE_ANSI_X_COLOR          @"Ansi %d Color"
#define KEY_SMART_CURSOR_COLOR     @"Smart Cursor Color"
#define KEY_MINIMUM_CONTRAST      @"Minimum Contrast"

// Display
#define KEY_ROWS                   @"Rows"
#define KEY_COLUMNS                @"Columns"
#define KEY_FULLSCREEN             @"Full Screen"  // DEPRECATED
#define KEY_WINDOW_TYPE            @"Window Type"
#define KEY_SCREEN                 @"Screen"
#define KEY_SPACE                  @"Space"
#define KEY_NORMAL_FONT            @"Normal Font"
#define KEY_NON_ASCII_FONT         @"Non Ascii Font"
#define KEY_HORIZONTAL_SPACING     @"Horizontal Spacing"
#define KEY_VERTICAL_SPACING       @"Vertical Spacing"
#define KEY_BLINKING_CURSOR        @"Blinking Cursor"
#define KEY_BLINK_ALLOWED          @"Blink Allowed"
#define KEY_CURSOR_TYPE            @"Cursor Type"
#define KEY_DISABLE_BOLD           @"Disable Bold"  // DEPRECATED
#define KEY_USE_BOLD_FONT          @"Use Bold Font"
#define KEY_USE_BRIGHT_BOLD        @"Use Bright Bold"
#define KEY_USE_ITALIC_FONT        @"Use Italic Font"
#define KEY_TRANSPARENCY           @"Transparency"
#define KEY_BLEND                  @"Blend"
#define KEY_BLUR                   @"Blur"
#define KEY_BLUR_RADIUS            @"Blur Radius"
#define KEY_ANTI_ALIASING          @"Anti Aliasing"  // DEPRECATED
#define KEY_ASCII_ANTI_ALIASED     @"ASCII Anti Aliased"
#define KEY_NONASCII_ANTI_ALIASED  @"Non-ASCII Anti Aliased"
#define KEY_BACKGROUND_IMAGE_LOCATION @"Background Image Location"
#define KEY_BACKGROUND_IMAGE_TILED @"Background Image Is Tiled"

// Terminal
#define KEY_DISABLE_WINDOW_RESIZING           @"Disable Window Resizing"
#define KEY_HIDE_AFTER_OPENING                @"Hide After Opening"
#define KEY_SYNC_TITLE                        @"Sync Title"
#define KEY_CLOSE_SESSIONS_ON_END             @"Close Sessions On End"
#define KEY_TREAT_NON_ASCII_AS_DOUBLE_WIDTH   @"Non Ascii Double Width"  // DEPRECATED
#define KEY_AMBIGUOUS_DOUBLE_WIDTH            @"Ambiguous Double Width"
#define KEY_SILENCE_BELL                      @"Silence Bell"
#define KEY_VISUAL_BELL                       @"Visual Bell"
#define KEY_FLASHING_BELL                     @"Flashing Bell"
#define KEY_XTERM_MOUSE_REPORTING             @"Mouse Reporting"
#define KEY_DISABLE_SMCUP_RMCUP               @"Disable Smcup Rmcup"
#define KEY_ALLOW_TITLE_REPORTING             @"Allow Title Reporting"
#define KEY_DISABLE_PRINTING                  @"Disable Printing"
#define KEY_SCROLLBACK_WITH_STATUS_BAR        @"Scrollback With Status Bar"
#define KEY_SCROLLBACK_IN_ALTERNATE_SCREEN    @"Scrollback in Alternate Screen"
#define KEY_BOOKMARK_GROWL_NOTIFICATIONS      @"BM Growl"
#define KEY_SET_LOCALE_VARS                   @"Set Local Environment Vars"
#define KEY_CHARACTER_ENCODING                @"Character Encoding"
#define KEY_SCROLLBACK_LINES                  @"Scrollback Lines"
#define KEY_UNLIMITED_SCROLLBACK              @"Unlimited Scrollback"
#define KEY_TERMINAL_TYPE                     @"Terminal Type"
#define KEY_USE_CANONICAL_PARSER              @"Use Canonical Parser"

// Session
#define KEY_AUTOLOG                           @"Automatically Log"
#define KEY_LOGDIR                            @"Log Directory"
#define KEY_SEND_CODE_WHEN_IDLE               @"Send Code When Idle"
#define KEY_IDLE_CODE                         @"Idle Code"
#define KEY_PROMPT_CLOSE_DEPRECATED           @"Prompt Before Closing"  // Deprecated due to bad migration in 8/28 build
#define KEY_PROMPT_CLOSE                      @"Prompt Before Closing 2"
#define KEY_JOBS                              @"Jobs to Ignore"

// Keyboard
#define KEY_KEYBOARD_MAP                      @"Keyboard Map"
#define KEY_OPTION_KEY_SENDS                  @"Option Key Sends"
#define KEY_RIGHT_OPTION_KEY_SENDS            @"Right Option Key Sends"

// Advanced
#define KEY_TRIGGERS                         @"Triggers"  // NSArray of NSDictionary
#define KEY_SMART_SELECTION_RULES            @"Smart Selection Rules"
#define KEY_TROUTER                          @"Semantic History"

#define WINDOW_TYPE_NORMAL 0
#define WINDOW_TYPE_FULL_SCREEN 1  // Creates a normal window but all callers to initWithSmartLayout will toggle fullscreen mode if this is the windowType.
#define WINDOW_TYPE_TOP 2
#define WINDOW_TYPE_FORCE_FULL_SCREEN 3  // Used internally, never reported by windowType API. Causes initWithSmartLayout to create a window with fullscreen chrome. It will set its windowType to FULL_SCREEN
#define WINDOW_TYPE_LION_FULL_SCREEN 4  // Lion-native fullscreen
#define WINDOW_TYPE_BOTTOM 5
#define WINDOW_TYPE_LEFT 6

typedef enum {
  iTermWindowObject,
  iTermTabObject,
  iTermPaneObject,
} iTermObjectType;

@interface ITAddressBookMgr : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
{
    NSNetServiceBrowser *sshBonjourBrowser;
    NSNetServiceBrowser *ftpBonjourBrowser;
    NSNetServiceBrowser *telnetBonjourBrowser;
    NSMutableArray *bonjourServices;
}


@end

@interface ITAddressBookMgr (Private)

+ (id)sharedInstance;
+ (NSArray*)encodeColor:(NSColor*)origColor;
+ (NSColor*)decodeColor:(NSDictionary*)plist;
+ (void)setDefaultsInBookmark:(NSMutableDictionary*)aDict;

- (id)init;
- (void)dealloc;
- (void) locateBonjourServices;
- (void)stopLocatingBonjourServices;
- (void)copyProfileToBookmark:(NSMutableDictionary *)dict;
- (void)recursiveMigrateBookmarks:(NSDictionary*)node path:(NSArray*)array;
+ (NSFont *)fontWithDesc:(NSString *)fontDesc;
+ (NSString*)descFromFont:(NSFont*)font;
- (void)setBookmarks:(NSArray*)newBookmarksArray defaultGuid:(NSString*)guid;
- (ProfileModel*)model;
- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing;
- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)aNetService moreComing:(BOOL)moreComing;
- (void)netServiceDidResolveAddress:(NSNetService *)sender;
- (void)netService:(NSNetService *)aNetService didNotResolve:(NSDictionary *)errorDict;
- (void)netServiceWillResolve:(NSNetService *)aNetService;
- (void)netServiceDidStop:(NSNetService *)aNetService;
- (NSString*) getBonjourServiceType:(NSString*)aType;
+ (NSString*)loginShellCommandForBookmark:(Profile*)bookmark
							 asLoginShell:(BOOL*)asLoginShell
							forObjectType:(iTermObjectType)objectType;
+ (NSString*)bookmarkCommand:(Profile*)bookmark
			  isLoginSession:(BOOL*)isLoginSession
			   forObjectType:(iTermObjectType)objectType;
+ (NSString*)bookmarkWorkingDirectory:(Profile*)bookmark
                        forObjectType:(iTermObjectType)objectType;

@end
