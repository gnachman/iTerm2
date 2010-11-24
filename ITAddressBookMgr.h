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
#import <iTerm/BookmarkModel.h>

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
#define KEY_CUSTOM_DIRECTORY            @"Custom Directory"  // values are Yes, No, Recycle
#define KEY_WORKING_DIRECTORY           @"Working Directory"
#define KEY_TERMINAL_PROFILE            @"Terminal Profile"
#define KEY_KEYBOARD_PROFILE            @"Keyboard Profile"
#define KEY_DISPLAY_PROFILE             @"Display Profile"
#define KEY_SHORTCUT                    @"Shortcut"
#define KEY_BONJOUR_GROUP           @"Bonjour Group"
#define KEY_BONJOUR_SERVICE         @"Bonjour Service"
#define KEY_BONJOUR_SERVICE_ADDRESS  @"Bonjour Service Address"
#define KEY_TAGS                              @"Tags"
#define KEY_GUID                              @"Guid"
#define KEY_DEFAULT_BOOKMARK            @"Default Bookmark"  // deprecated

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

// Display
#define KEY_ROWS                   @"Rows"
#define KEY_COLUMNS                @"Columns"
#define KEY_NORMAL_FONT            @"Normal Font"
#define KEY_NON_ASCII_FONT         @"Non Ascii Font"
#define KEY_HORIZONTAL_SPACING     @"Horizontal Spacing"
#define KEY_VERTICAL_SPACING       @"Vertical Spacing"
#define KEY_BLINKING_CURSOR        @"Blinking Cursor"
#define KEY_DISABLE_BOLD           @"Disable Bold"  // DEPRECATED
#define KEY_USE_BOLD_FONT          @"Use Bold Font"
#define KEY_USE_BRIGHT_BOLD        @"Use Bright Bold"
#define KEY_TRANSPARENCY           @"Transparency"
#define KEY_BLUR                   @"Blur"
#define KEY_ANTI_ALIASING          @"Anti Aliasing"
#define KEY_BACKGROUND_IMAGE_LOCATION @"Background Image Location"

// Terminal
#define KEY_DISABLE_WINDOW_RESIZING           @"Disable Window Resizing"
#define KEY_SYNC_TITLE                        @"Sync Title"
#define KEY_CLOSE_SESSIONS_ON_END             @"Close Sessions On End"
#define KEY_TREAT_NON_ASCII_AS_DOUBLE_WIDTH   @"Non Ascii Double Width"  // DEPRECATED
#define KEY_AMBIGUOUS_DOUBLE_WIDTH            @"Ambiguous Double Width"
#define KEY_SILENCE_BELL                      @"Silence Bell"
#define KEY_VISUAL_BELL                       @"Visual Bell"
#define KEY_FLASHING_BELL                     @"Flashing Bell"
#define KEY_XTERM_MOUSE_REPORTING             @"Mouse Reporting"
#define KEY_BOOKMARK_GROWL_NOTIFICATIONS      @"BM Growl"
#define KEY_CHARACTER_ENCODING                @"Character Encoding"
#define KEY_SCROLLBACK_LINES                  @"Scrollback Lines"
#define KEY_TERMINAL_TYPE                     @"Terminal Type"
#define KEY_SEND_CODE_WHEN_IDLE               @"Send Code When Idle"
#define KEY_IDLE_CODE                         @"Idle Code"

// Keyboard
#define KEY_KEYBOARD_MAP                      @"Keyboard Map"
#define KEY_OPTION_KEY_SENDS                  @"Option Key Sends"
#define KEY_RIGHT_OPTION_KEY_SENDS            @"Right Option Key Sends"


@interface ITAddressBookMgr : NSObject
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
- (BookmarkModel*)model;
- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing;
- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)aNetService moreComing:(BOOL)moreComing;
- (void)netServiceDidResolveAddress:(NSNetService *)sender;
- (void)netService:(NSNetService *)aNetService didNotResolve:(NSDictionary *)errorDict;
- (void)netServiceWillResolve:(NSNetService *)aNetService;
- (void)netServiceDidStop:(NSNetService *)aNetService;
- (NSString*) getBonjourServiceType:(NSString*)aType;
+ (NSString*)loginShellCommandForBookmark:(Bookmark*)bookmark;
+ (NSString*)bookmarkCommand:(Bookmark*)bookmark;
+ (NSString*)bookmarkWorkingDirectory:(Bookmark*)bookmark;

@end
