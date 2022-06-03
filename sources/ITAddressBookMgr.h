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
#import "iTermOpenDirectory.h"
#import "ProfileModel.h"
#import "FutureMethods.h"

// Prefs-level keys
#define KEY_DEFAULT_GUID                @"Default Bookmark Guid"  // use this instead (not in a bookmark)
#define KEY_DEPRECATED_BOOKMARKS        @"Bookmarks"  // Deprecated
#define KEY_NEW_BOOKMARKS               @"New Bookmarks"

#pragma mark - Profile-level keys
// IMPORTANT: If you add keys, also modify doCopyFrom in PreferencePanel.m.

#define KEY_CHILDREN                    @"Children"  // Deprecated
#define KEY_NAME                        @"Name"
#define KEY_DESCRIPTION                 @"Description"  // Deprecated
#define KEY_CUSTOM_COMMAND              @"Custom Command"
#define KEY_COMMAND_LINE                @"Command"
#define KEY_INITIAL_TEXT                @"Initial Text"  // String. Evaluated as a swifty string.
#define KEY_CUSTOM_DIRECTORY            @"Custom Directory"  // values are Yes, No, Recycle, Advanced
#define KEY_WORKING_DIRECTORY           @"Working Directory"
#define KEY_BADGE_FORMAT                @"Badge Text"
#define KEY_TERMINAL_PROFILE            @"Terminal Profile"  // Deprecated
#define KEY_KEYBOARD_PROFILE            @"Keyboard Profile"  // Deprecated
#define KEY_DISPLAY_PROFILE             @"Display Profile"  // Deprecated
#define KEY_SHORTCUT                    @"Shortcut"
#define KEY_ICON                        @"Icon"  // Number with iTermProfileIcon enum
#define KEY_ICON_PATH                   @"Custom Icon Path"
#define KEY_BONJOUR_GROUP               @"Bonjour Group"  // Deprecated
#define KEY_BONJOUR_SERVICE             @"Bonjour Service"  // Deprecated
#define KEY_BONJOUR_SERVICE_ADDRESS     @"Bonjour Service Address"  // Deprecated
#define KEY_TAGS                        @"Tags"
#define KEY_GUID                        @"Guid"
#define KEY_ORIGINAL_GUID               @"Original Guid"  // GUID before divorce. Not saved to preferences plist.
#define KEY_DEFAULT_BOOKMARK            @"Default Bookmark"  // deprecated
#define KEY_ASK_ABOUT_OUTDATED_KEYMAPS  @"Ask About Outdated Keymaps"
#define KEY_TITLE_COMPONENTS            @"Title Components"
#define KEY_TITLE_FUNC                  @"Title Function"  // Value is iTermTuple.plistValue of (display name, unique identifier); e.g. ("Hello world", "com.iterm2.example.title-provider")
#define KEY_BADGE_TOP_MARGIN            @"Badge Top Margin"
#define KEY_BADGE_RIGHT_MARGIN          @"Badge Right Margin"
#define KEY_BADGE_MAX_WIDTH             @"Badge Max Width"
#define KEY_BADGE_MAX_HEIGHT            @"Badge Max Height"
#define KEY_BADGE_FONT                  @"Badge Font"
#define KEY_PREVENT_APS                 @"Prevent Automatic Profile Switching"  // Not in regular prefs, only for divorced prefs.
#define KEY_SUBTITLE                    @"Subtitle"
#define KEY_SSH_CONFIG                  @"SSH"

// Advanced working directory settings
#define KEY_AWDS_WIN_OPTION             @"AWDS Window Option"
#define KEY_AWDS_WIN_DIRECTORY          @"AWDS Window Directory"
#define KEY_AWDS_TAB_OPTION             @"AWDS Tab Option"
#define KEY_AWDS_TAB_DIRECTORY          @"AWDS Tab Directory"
#define KEY_AWDS_PANE_OPTION            @"AWDS Pane Option"
#define KEY_AWDS_PANE_DIRECTORY         @"AWDS Pane Directory"

// Colors
// Keys starting here have light and dark variants
#define KEY_FOREGROUND_COLOR       @"Foreground Color"
#define KEY_BACKGROUND_COLOR       @"Background Color"
#define KEY_BOLD_COLOR             @"Bold Color"
#define KEY_USE_BOLD_COLOR         @"Use Bright Bold"  // Pre-3.3.7: Means "use the specified bold color, and also use the bright version of dark ansi colors". Post-3.3.7: Use the specified bold color
#define KEY_BRIGHTEN_BOLD_TEXT     @"Brighten Bold Text"  // New in 3.3.7.
#define KEY_LINK_COLOR             @"Link Color"
#define KEY_SELECTION_COLOR        @"Selection Color"
#define KEY_SELECTED_TEXT_COLOR    @"Selected Text Color"
#define KEY_CURSOR_COLOR           @"Cursor Color"
#define KEY_CURSOR_TEXT_COLOR      @"Cursor Text Color"
#define KEY_ANSI_0_COLOR           @"Ansi 0 Color"   // Black
#define KEY_ANSI_1_COLOR           @"Ansi 1 Color"   // Red
#define KEY_ANSI_2_COLOR           @"Ansi 2 Color"   // Green
#define KEY_ANSI_3_COLOR           @"Ansi 3 Color"   // Yellow
#define KEY_ANSI_4_COLOR           @"Ansi 4 Color"   // Blue
#define KEY_ANSI_5_COLOR           @"Ansi 5 Color"   // Magenta
#define KEY_ANSI_6_COLOR           @"Ansi 6 Color"   // Cyan
#define KEY_ANSI_7_COLOR           @"Ansi 7 Color"   // White
#define KEY_ANSI_8_COLOR           @"Ansi 8 Color"   // Bright black
#define KEY_ANSI_9_COLOR           @"Ansi 9 Color"   // Bright red
#define KEY_ANSI_10_COLOR          @"Ansi 10 Color"  // Bright green
#define KEY_ANSI_11_COLOR          @"Ansi 11 Color"  // Bright yellow
#define KEY_ANSI_12_COLOR          @"Ansi 12 Color"  // Bright blue
#define KEY_ANSI_13_COLOR          @"Ansi 13 Color"  // Bright magenta
#define KEY_ANSI_14_COLOR          @"Ansi 14 Color"  // Bright cyan
#define KEY_ANSI_15_COLOR          @"Ansi 15 Color"  // Bright white
#define KEYTEMPLATE_ANSI_X_COLOR   @"Ansi %d Color"
#define KEY_SMART_CURSOR_COLOR     @"Smart Cursor Color"
#define KEY_MINIMUM_CONTRAST       @"Minimum Contrast"
#define KEY_TAB_COLOR              @"Tab Color"
#define KEY_USE_TAB_COLOR          @"Use Tab Color"
#define KEY_UNDERLINE_COLOR        @"Underline Color"
#define KEY_USE_UNDERLINE_COLOR    @"Use Underline Color"
#define KEY_CURSOR_BOOST           @"Cursor Boost"
#define KEY_USE_CURSOR_GUIDE       @"Use Cursor Guide"
#define KEY_CURSOR_GUIDE_COLOR     @"Cursor Guide Color"
#define KEY_BADGE_COLOR            @"Badge Color"
// End of key swith light and dark variants
#define KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE @"Use Separate Colors for Light and Dark Mode"
#define COLORS_LIGHT_MODE_SUFFIX @" (Light)"
#define COLORS_DARK_MODE_SUFFIX @" (Dark)"

// Display
#define KEY_ROWS                   @"Rows"  // not to exceed iTermMaxInitialSessionSize
#define KEY_COLUMNS                @"Columns"  // not to exceed iTermMaxInitialSessionSize
#define KEY_FULLSCREEN             @"Full Screen"  // DEPRECATED
#define KEY_WINDOW_TYPE            @"Window Type"
#define KEY_USE_CUSTOM_WINDOW_TITLE           @"Use Custom Window Title"
#define KEY_CUSTOM_WINDOW_TITLE               @"Custom Window Title"
#define KEY_USE_CUSTOM_TAB_TITLE   @"Use Custom Tab Title"
#define KEY_CUSTOM_TAB_TITLE       @"Custom Tab Title"
#define KEY_SCREEN                 @"Screen"
#define KEY_SPACE                  @"Space"  // integer, iTermProfileSpaceSetting
#define KEY_NORMAL_FONT            @"Normal Font"
#define KEY_NON_ASCII_FONT         @"Non Ascii Font"
#define KEY_HORIZONTAL_SPACING     @"Horizontal Spacing"
#define KEY_VERTICAL_SPACING       @"Vertical Spacing"
#define KEY_BLINKING_CURSOR        @"Blinking Cursor"
#define KEY_CURSOR_SHADOW          @"Cursor Shadow"
#define KEY_BLINK_ALLOWED          @"Blink Allowed"
#define KEY_CURSOR_TYPE            @"Cursor Type"
#define KEY_DISABLE_BOLD           @"Disable Bold"  // DEPRECATED
#define KEY_USE_BOLD_FONT          @"Use Bold Font"
#define KEY_THIN_STROKES           @"Thin Strokes"
#define KEY_USE_ITALIC_FONT        @"Use Italic Font"
#define KEY_TRANSPARENCY           @"Transparency"
#define KEY_INITIAL_USE_TRANSPARENCY @"Initial Use Transparency"
#define KEY_BLEND                  @"Blend"
#define KEY_BLUR                   @"Blur"
#define KEY_BLUR_RADIUS            @"Blur Radius"
#define KEY_ANTI_ALIASING          @"Anti Aliasing"  // DEPRECATED
#define KEY_ASCII_ANTI_ALIASED     @"ASCII Anti Aliased"
#define KEY_USE_NONASCII_FONT      @"Use Non-ASCII Font"
#define KEY_NONASCII_ANTI_ALIASED  @"Non-ASCII Anti Aliased"
#define KEY_BACKGROUND_IMAGE_LOCATION @"Background Image Location"
#define KEY_BACKGROUND_IMAGE_TILED_DEPRECATED @"Background Image Is Tiled"  // DEPRECATED
#define KEY_ASCII_LIGATURES        @"ASCII Ligatures"
#define KEY_NON_ASCII_LIGATURES    @"Non-ASCII Ligatures"
#define KEY_BACKGROUND_IMAGE_MODE  @"Background Image Mode"  // iTermBackgroundImageMode enum
#define KEY_POWERLINE              @"Draw Powerline Glyphs"

// Terminal
#define KEY_DISABLE_WINDOW_RESIZING           @"Disable Window Resizing"
#define KEY_PREVENT_TAB                       @"Prevent Opening in a Tab"
#define KEY_TRANSPARENCY_AFFECTS_ONLY_DEFAULT_BACKGROUND_COLOR @"Only The Default BG Color Uses Transparency"
#define KEY_OPEN_TOOLBELT                     @"Open Toolbelt"
#define KEY_HIDE_AFTER_OPENING                @"Hide After Opening"
#define KEY_SYNC_TITLE_DEPRECATED             @"Sync Title"  // DEPRECATED
#define KEY_SESSION_END_ACTION                @"Close Sessions On End"  // iTermSessionEndAction
#define KEY_TREAT_NON_ASCII_AS_DOUBLE_WIDTH   @"Non Ascii Double Width"  // DEPRECATED
#define KEY_AMBIGUOUS_DOUBLE_WIDTH            @"Ambiguous Double Width"
#define KEY_USE_HFS_PLUS_MAPPING              @"Use HFS Plus Mapping"  // DEPRECATED
#define KEY_UNICODE_NORMALIZATION             @"Unicode Normalization"
#define KEY_SILENCE_BELL                      @"Silence Bell"
#define KEY_VISUAL_BELL                       @"Visual Bell"
#define KEY_FLASHING_BELL                     @"Flashing Bell"
#define KEY_XTERM_MOUSE_REPORTING             @"Mouse Reporting"
#define KEY_XTERM_MOUSE_REPORTING_ALLOW_MOUSE_WHEEL @"Mouse Reporting allow mouse wheel"
#define KEY_XTERM_MOUSE_REPORTING_ALLOW_CLICKS_AND_DRAGS @"Mouse Reporting allow clicks and drags"
#define KEY_UNICODE_VERSION                   @"Unicode Version"
#define KEY_DISABLE_SMCUP_RMCUP               @"Disable Smcup Rmcup"
#define KEY_ALLOW_TITLE_REPORTING             @"Allow Title Reporting"
#define KEY_ALLOW_PASTE_BRACKETING            @"Allow Paste Bracketing"
#define KEY_ALLOW_TITLE_SETTING               @"Allow Title Setting"
#define KEY_DISABLE_PRINTING                  @"Disable Printing"
#define KEY_SCROLLBACK_WITH_STATUS_BAR        @"Scrollback With Status Bar"
#define KEY_SCROLLBACK_IN_ALTERNATE_SCREEN    @"Scrollback in Alternate Screen"
#define KEY_BOOKMARK_USER_NOTIFICATIONS       @"BM Growl"
#define KEY_SEND_BELL_ALERT                   @"Send Bell Alert"
#define KEY_SEND_IDLE_ALERT                   @"Send Idle Alert"
#define KEY_SEND_NEW_OUTPUT_ALERT             @"Send New Output Alert"
#define KEY_SEND_SESSION_ENDED_ALERT          @"Send Session Ended Alert"
#define KEY_SEND_TERMINAL_GENERATED_ALERT     @"Send Terminal Generated Alerts"
#define KEY_ALLOW_CHANGE_CURSOR_BLINK         @"Allow Change Cursor Blink"
#define KEY_LOAD_SHELL_INTEGRATION_AUTOMATICALLY @"Load Shell Integration Automatically"

#define KEY_SET_LOCALE_VARS                   @"Set Local Environment Vars"
#define KEY_CHARACTER_ENCODING                @"Character Encoding"
#define KEY_SCROLLBACK_LINES                  @"Scrollback Lines"
#define KEY_UNLIMITED_SCROLLBACK              @"Unlimited Scrollback"
#define KEY_TERMINAL_TYPE                     @"Terminal Type"
#define KEY_ANSWERBACK_STRING                 @"Answerback String"
#define KEY_USE_CANONICAL_PARSER              @"Use Canonical Parser"  // Deprecated
#define KEY_PLACE_PROMPT_AT_FIRST_COLUMN      @"Place Prompt at First Column"
#define KEY_SHOW_MARK_INDICATORS              @"Show Mark Indicators"

// Session
#define KEY_AUTOLOG                           @"Automatically Log"
#define KEY_UNDO_TIMEOUT                      @"Session Close Undo Timeout"
#define KEY_LOGDIR                            @"Log Directory"
#define KEY_LOG_FILENAME_FORMAT               @"Log Filename Format"
#define KEY_SEND_CODE_WHEN_IDLE               @"Send Code When Idle"
#define KEY_IDLE_CODE                         @"Idle Code"
#define KEY_IDLE_PERIOD                       @"Idle Period"
#define KEY_PROMPT_CLOSE_DEPRECATED           @"Prompt Before Closing"  // Deprecated due to bad migration in 8/28 build
#define KEY_PROMPT_CLOSE                      @"Prompt Before Closing 2"
#define KEY_JOBS                              @"Jobs to Ignore"
#define KEY_REDUCE_FLICKER                    @"Reduce Flicker"
#define KEY_SHOW_STATUS_BAR                   @"Show Status Bar"
#define KEY_STATUS_BAR_LAYOUT                 @"Status Bar Layout"
#define KEY_LOGGING_STYLE                     @"Plain Text Logging"  // Formerly a boolean (false=raw, true=text) now an integer (iTermLoggingStyle)
#define KEY_OPEN_PASSWORD_MANAGER_AUTOMATICALLY @"Open Password Manager Automatically"
#define KEY_SHOW_TIMESTAMPS                   @"Show Timestamps"  // NSNumber iTermTimestampsMode

// Keyboard
#define KEY_KEYBOARD_MAP                      @"Keyboard Map"
#define KEY_TOUCHBAR_MAP                      @"Touch Bar Map"
#define KEY_OPTION_KEY_SENDS                  @"Option Key Sends"
#define KEY_RIGHT_OPTION_KEY_SENDS            @"Right Option Key Sends"
#define KEY_LEFT_OPTION_KEY_CHANGEABLE        @"Left Option Key Changeable"
#define KEY_RIGHT_OPTION_KEY_CHANGEABLE       @"Right Option Key Changeable"
#define KEY_APPLICATION_KEYPAD_ALLOWED        @"Application Keypad Allowed"
#define KEY_MOVEMENT_KEYS_SCROLL_OUTSIDE_INTERACTIVE_APPS @"Movement Keys Scroll Outside Interactive Apps"
#define KEY_ALLOW_MODIFY_OTHER_KEYS           @"Allow modifyOtherKeys"
#define KEY_HAS_HOTKEY                        @"Has Hotkey"  // This determines whether the "has a hotkey" box is checked. See also KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS.
#define KEY_HOTKEY_KEY_CODE                   @"HotKey Key Code"
#define KEY_HOTKEY_CHARACTERS                 @"HotKey Characters"
#define KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS @"HotKey Characters Ignoring Modifiers"  // If this is non-empty then a hotkey is assigned, but see also KEY_HAS_HOTKEY.
#define KEY_HOTKEY_MODIFIER_FLAGS             @"HotKey Modifier Flags"
#define KEY_HOTKEY_AUTOHIDE                   @"HotKey Window AutoHides"
#define KEY_HOTKEY_REOPEN_ON_ACTIVATION       @"HotKey Window Reopens On Activation"
#define KEY_HOTKEY_ANIMATE                    @"HotKey Window Animates"
#define KEY_HOTKEY_FLOAT                      @"HotKey Window Floats"
#define KEY_HOTKEY_DOCK_CLICK_ACTION          @"HotKey Window Dock Click Action"
#define KEY_HOTKEY_ACTIVATE_WITH_MODIFIER     @"HotKey Activated By Modifier"
#define KEY_HOTKEY_MODIFIER_ACTIVATION        @"HotKey Modifier Activation"
#define KEY_HOTKEY_ALTERNATE_SHORTCUTS        @"HotKey Alternate Shortcuts"
#define KEY_USE_LIBTICKIT_PROTOCOL            @"Use libtickit protocol"

// Advanced
#define KEY_TRIGGERS                         @"Triggers"  // NSArray of NSDictionary
#define KEY_ENABLE_TRIGGERS_IN_INTERACTIVE_APPS @"Enable Triggers in Interactive Apps"  // Bool
#define KEY_TRIGGERS_USE_INTERPOLATED_STRINGS @"Triggers Use Interpolated Strings"
#define KEY_SMART_SELECTION_RULES            @"Smart Selection Rules"
#define KEY_SMART_SELECTION_ACTIONS_USE_INTERPOLATED_STRINGS @"Smart Selection Actions Use Interpolated Strings"  // Bool
#define KEY_SEMANTIC_HISTORY                 @"Semantic History"
#define KEY_BOUND_HOSTS                      @"Bound Hosts"

// Dynamic Profiles (not in prefs ui)
#define KEY_DYNAMIC_PROFILE_PARENT_NAME      @"Dynamic Profile Parent Name"
#define KEY_DYNAMIC_PROFILE_PARENT_GUID      @"Dynamic Profile Parent GUID"
#define KEY_DYNAMIC_PROFILE_FILENAME         @"Dynamic Profile Filename"

// Session-only key
#define KEY_SESSION_HOTKEY                   @"Session Hotkey"

// This is not a real setting. It's just a way for the session to communicate
// the tmux pane title to the edit session dialog so it can prepopulate the
// field correctly.
#define KEY_TMUX_PANE_TITLE                  @"tmux Pane Title"

// This is not a real setting. It's a way to communicate that a newly created
// window should not use auto-saved frames (see -loadAutoSave). Takes a boolean.
#define KEY_DISABLE_AUTO_FRAME               @"Disable Auto Frame"

@class iTermVariableScope;

// Posted when a session's unicode version changes.
extern NSString *const iTermUnicodeVersionDidChangeNotification;

// Minimum time between sending anti-idle codes. "1" otherwise results in a flood.
extern const NSTimeInterval kMinimumAntiIdlePeriod;

// Values for KEY_CUSTOM_COMMAND
extern NSString *const kProfilePreferenceCommandTypeCustomValue;
extern NSString *const kProfilePreferenceCommandTypeLoginShellValue;
extern NSString *const kProfilePreferenceCommandTypeCustomShellValue;
extern NSString *const kProfilePreferenceCommandTypeSSHValue;

// I chose 1250 because on a 6k display each cell would be less than 5 points wide,
// which won't be legible. It needs an upper bound because of issue 8592.
extern const NSInteger iTermMaxInitialSessionSize;

// Special values for KEY_SPACE.
typedef NS_ENUM(NSInteger, iTermProfileSpaceSetting) {
    iTermProfileJoinsAllSpaces = -1,
    iTermProfileOpenInCurrentSpace = 0
};

typedef NS_ENUM(NSUInteger, iTermSessionEndAction) {
    iTermSessionEndActionDefault = 0,
    iTermSessionEndActionClose = 1,
    iTermSessionEndActionRestart = 2
};

typedef NS_ENUM(int, iTermOptionKeyBehavior) {
    OPT_NORMAL = 0,
    OPT_META = 1,
    OPT_ESC = 2
};

// The numerical values for each enum matter because they are used in
// the UI as "tag" values for each select list item. They are also
// stored in saved arrangements.
typedef enum {
    WINDOW_TYPE_NORMAL = 0,  // May be converted to compact depending on theme
    WINDOW_TYPE_TRADITIONAL_FULL_SCREEN = 1,  // Pre-Lion fullscreen
    // note: 2 is out of order below

    // Type 3 is deprecated and used to be used internally to create a
    // fullscreen window during toggling.

    WINDOW_TYPE_LION_FULL_SCREEN = 4,  // Lion-native fullscreen

    // These are glued to an edge of the screen and span the full width/height
    WINDOW_TYPE_TOP = 2,  // note: number is out of order
    WINDOW_TYPE_BOTTOM = 5,
    WINDOW_TYPE_LEFT = 6,
    WINDOW_TYPE_RIGHT = 7,

    // These are glued to an edge of the screen but may vary in width/height
    WINDOW_TYPE_BOTTOM_PARTIAL = 8,
    WINDOW_TYPE_TOP_PARTIAL = 9,
    WINDOW_TYPE_LEFT_PARTIAL = 10,
    WINDOW_TYPE_RIGHT_PARTIAL = 11,

    WINDOW_TYPE_NO_TITLE_BAR = 12,
    WINDOW_TYPE_COMPACT = 13,  // May be converted to normal depending on theme
    WINDOW_TYPE_ACCESSORY = 14,

    WINDOW_TYPE_MAXIMIZED = 15,
    WINDOW_TYPE_COMPACT_MAXIMIZED = 16
} iTermWindowType;

iTermWindowType iTermWindowDefaultType(void);
iTermWindowType iTermThemedWindowType(iTermWindowType windowType);

typedef NS_ENUM(NSInteger, iTermObjectType) {
  iTermWindowObject,
  iTermTabObject,
  iTermPaneObject,
};

// Type for KEY_THIN_STROKES
typedef NS_ENUM(NSInteger, iTermThinStrokesSetting) {
    iTermThinStrokesSettingNever = 0,
    iTermThinStrokesSettingRetinaDarkBackgroundsOnly = 1,
    iTermThinStrokesSettingDarkBackgroundsOnly = 2,
    iTermThinStrokesSettingAlways = 3,
    iTermThinStrokesSettingRetinaOnly = 4,
};

typedef NS_ENUM(NSUInteger, iTermHotKeyDockPreference) {
    iTermHotKeyDockPreferenceDoNotShow,
    iTermHotKeyDockPreferenceAlwaysShow,
    iTermHotKeyDockPreferenceShowIfNoOtherWindowsOpen,
};

// Do not renumber. These are tag numbers and also saved in prefs.
typedef NS_ENUM(NSUInteger, iTermHotKeyModifierActivation) {
    iTermHotKeyModifierActivationControl = 0,
    iTermHotKeyModifierActivationShift = 1,
    iTermHotKeyModifierActivationOption = 2,
    iTermHotKeyModifierActivationCommand = 3,
};

// Do not renumber. These are tag numbers and also saved in prefs.
typedef NS_ENUM(NSUInteger, iTermUnicodeNormalization) {
    iTermUnicodeNormalizationNone = 0,
    iTermUnicodeNormalizationNFC = 1,
    iTermUnicodeNormalizationNFD = 2,
    iTermUnicodeNormalizationHFSPlus = 3,
};

typedef NS_ENUM(NSUInteger, iTermBackgroundImageMode) {
    iTermBackgroundImageModeStretch = 0,
    iTermBackgroundImageModeTile = 1,
    iTermBackgroundImageModeScaleAspectFill = 2,
    iTermBackgroundImageModeScaleAspectFit = 3
};

typedef NS_OPTIONS(NSUInteger, iTermTitleComponents) {
    iTermTitleComponentsSessionName = 1 << 0,
    iTermTitleComponentsJob = 1 << 1,
    iTermTitleComponentsWorkingDirectory = 1 << 2,
    iTermTitleComponentsTTY = 1 << 3,
    iTermTitleComponentsCustom = 1 << 4,  // Mutually exclusive with all other options.
    iTermTitleComponentsProfileName = 1 << 5,
    iTermTitleComponentsProfileAndSessionName = 1 << 6,
    iTermTitleComponentsUser = 1 << 7,
    iTermTitleComponentsHost = 1 << 8,
    iTermTitleComponentsCommandLine = 1 << 9,
    iTermTitleComponentsSize = 1 << 10,
};

typedef NS_ENUM(NSUInteger, iTermProfileIcon) {
    iTermProfileIconNone = 0,
    iTermProfileIconAutomatic = 1,
    iTermProfileIconCustom = 2
};

typedef NS_ENUM(NSUInteger, iTermTimestampsMode) {
    iTermTimestampsModeOff,
    iTermTimestampsModeOn,
    iTermTimestampsModeHover
};

typedef NS_ENUM(NSUInteger, iTermLoggingStyle) {
    iTermLoggingStyleRaw,
    iTermLoggingStylePlainText,
    iTermLoggingStyleHTML,
    iTermLoggingStyleAsciicast
};

static inline iTermLoggingStyle iTermLoggingStyleFromUserDefaultsValue(NSUInteger value) {
    switch (value) {
        case iTermLoggingStyleHTML:
        case iTermLoggingStyleRaw:
        case iTermLoggingStylePlainText:
        case iTermLoggingStyleAsciicast:
            return (iTermLoggingStyle)value;
    }
    return iTermLoggingStyleRaw;
}

@interface ITAddressBookMgr : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate>

+ (id)sharedInstance;
+ (NSDictionary*)encodeColor:(NSColor*)origColor;
+ (NSColor*)decodeColor:(NSDictionary*)plist;
+ (void)setDefaultsInBookmark:(NSMutableDictionary*)aDict;
+ (NSString *)shellLauncherCommandWithCustomShell:(NSString *)customShell;
// Login command that leaves you in your home directory.
+ (NSString *)standardLoginCommand;
+ (NSFont *)fontWithDesc:(NSString *)fontDesc;

// This is deprecated in favor of -[NSString fontValue] and -[NSFont stringValue].
+ (NSString *)descFromFont:(NSFont*)font __attribute__((deprecated));
+ (void)computeCommandForProfile:(Profile *)profile
                      objectType:(iTermObjectType)objectType
                           scope:(iTermVariableScope *)scope
                      completion:(void (^)(NSString *command, BOOL isSSH))completion;

// Like computeCommandForProfile:objectType:scope:completion: but does not evaluate it.
+ (NSString *)bookmarkCommandSwiftyString:(Profile *)bookmark
                            forObjectType:(iTermObjectType)objectType;

+ (NSString *)customShellForProfile:(Profile *)profile;

// Indicates if it is safe to remove the profile from the model.
+ (BOOL)canRemoveProfile:(Profile *)profile fromModel:(ProfileModel *)model;

// Removes the profile from the model, removes key mappings that reference this profile, and posts a
// kProfileWasDeletedNotification notification, then flushes the model to backing store.
+ (BOOL)removeProfile:(Profile *)profile fromModel:(ProfileModel *)model;
+ (void)performBlockWithCoalescedNotifications:(void (^)(void))block;
+ (BOOL)shortcutIdentifier:(NSString *)identifier title:(NSString *)title matchesItem:(NSMenuItem *)item;
@end
