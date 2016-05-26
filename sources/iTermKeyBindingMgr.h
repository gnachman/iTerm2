/*
 **  iTermKeyBindingMgr.h
 **
 **  Copyright (c) 2002, 2003, 2004
 **
 **  Author: Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: Header file for key binding manager.
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
#import "ProfileModel.h"

// Key Definitions
#define KEY_CURSOR_DOWN                 0
#define KEY_CURSOR_LEFT                 1
#define KEY_CURSOR_RIGHT                2
#define KEY_CURSOR_UP                   3
#define KEY_DEL                         4
#define KEY_DELETE                      5
#define KEY_END                         6
#define KEY_F1                          7
#define KEY_F2                          8
#define KEY_F3                          9
#define KEY_F4                          10
#define KEY_F5                          11
#define KEY_F6                          12
#define KEY_F7                          13
#define KEY_F8                          14
#define KEY_F9                          15
#define KEY_F10                         16
#define KEY_F11                         17
#define KEY_F12                         18
#define KEY_F13                         19
#define KEY_F14                         20
#define KEY_F15                         21
#define KEY_F16                         22
#define KEY_F17                         23
#define KEY_F18                         24
#define KEY_F19                         25
#define KEY_F20                         26
#define KEY_HELP                        27
#define KEY_HEX_CODE                    28
#define KEY_HOME                        29
#define KEY_NUMERIC_0                   30
#define KEY_NUMERIC_1                   31
#define KEY_NUMERIC_2                   32
#define KEY_NUMERIC_3                   33
#define KEY_NUMERIC_4                   34
#define KEY_NUMERIC_5                   35
#define KEY_NUMERIC_6                   36
#define KEY_NUMERIC_7                   37
#define KEY_NUMERIC_8                   38
#define KEY_NUMERIC_9                   39
#define KEY_NUMERIC_ENTER               40
#define KEY_NUMERIC_EQUAL               41
#define KEY_NUMERIC_DIVIDE              42
#define KEY_NUMERIC_MULTIPLY            43
#define KEY_NUMERIC_MINUS               44
#define KEY_NUMERIC_PLUS                45
#define KEY_NUMERIC_PERIOD              46
#define KEY_NUMLOCK                     47
#define KEY_PAGE_DOWN                   48
#define KEY_PAGE_UP                     49
#define KEY_INS                         50


// Actions for key bindings
#define KEY_ACTION_NEXT_SESSION         0
#define KEY_ACTION_NEXT_WINDOW          1
#define KEY_ACTION_PREVIOUS_SESSION     2
#define KEY_ACTION_PREVIOUS_WINDOW      3
#define KEY_ACTION_SCROLL_END           4
#define KEY_ACTION_SCROLL_HOME          5
#define KEY_ACTION_SCROLL_LINE_DOWN     6
#define KEY_ACTION_SCROLL_LINE_UP       7
#define KEY_ACTION_SCROLL_PAGE_DOWN     8
#define KEY_ACTION_SCROLL_PAGE_UP       9
#define KEY_ACTION_ESCAPE_SEQUENCE      10
#define KEY_ACTION_HEX_CODE             11
#define KEY_ACTION_TEXT                 12
#define KEY_ACTION_IGNORE               13
#define KEY_ACTION_IR_FORWARD           14  // Deprecated
#define KEY_ACTION_IR_BACKWARD          15
#define KEY_ACTION_SEND_C_H_BACKSPACE   16
#define KEY_ACTION_SEND_C_QM_BACKSPACE  17
#define KEY_ACTION_SELECT_PANE_LEFT     18
#define KEY_ACTION_SELECT_PANE_RIGHT    19
#define KEY_ACTION_SELECT_PANE_ABOVE    20
#define KEY_ACTION_SELECT_PANE_BELOW    21
#define KEY_ACTION_DO_NOT_REMAP_MODIFIERS 22
#define KEY_ACTION_TOGGLE_FULLSCREEN    23
#define KEY_ACTION_REMAP_LOCALLY        24
#define KEY_ACTION_SELECT_MENU_ITEM     25
#define KEY_ACTION_NEW_WINDOW_WITH_PROFILE 26
#define KEY_ACTION_NEW_TAB_WITH_PROFILE 27
#define KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE 28
#define KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE 29
#define KEY_ACTION_NEXT_PANE 30
#define KEY_ACTION_PREVIOUS_PANE 31
#define KEY_ACTION_NEXT_MRU_TAB 32
#define KEY_ACTION_MOVE_TAB_LEFT 33
#define KEY_ACTION_MOVE_TAB_RIGHT 34
#define KEY_ACTION_RUN_COPROCESS 35
#define KEY_ACTION_FIND_REGEX 36
#define KEY_ACTION_SET_PROFILE 37
#define KEY_ACTION_VIM_TEXT 38
#define KEY_ACTION_PREVIOUS_MRU_TAB 39
#define KEY_ACTION_LOAD_COLOR_PRESET 40
#define KEY_ACTION_PASTE_SPECIAL 41
#define KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION 42
#define KEY_ACTION_TOGGLE_HOTKEY_WINDOW_PINNING 43
#define KEY_ACTION_UNDO 44
#define KEY_ACTION_MOVE_END_OF_SELECTION_LEFT 45
#define KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT 46
#define KEY_ACTION_MOVE_START_OF_SELECTION_LEFT 47
#define KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT 48
#define KEY_ACTION_DECREASE_HEIGHT 49
#define KEY_ACTION_INCREASE_HEIGHT 50
#define KEY_ACTION_DECREASE_WIDTH 51
#define KEY_ACTION_INCREASE_WIDTH 52


@interface iTermKeyBindingMgr : NSObject {
}

// Given a key combination of the form 0xKeycode-0xModifiers, return a human-
// readable representation (e.g., ^X)
+ (NSString *)formatKeyCombination:(NSString *)theKeyCombination;

// Given a dictionary with keys Action->int, Text->string, return a human-readable
// description (e.g., "Send text: foo"). The action comes from the KEY_ACTION_xxx
// constants.
+ (NSString *)formatAction:(NSDictionary *)keyInfo;

// Given a keycode and modifier mask, return the action and fill in the optional text
// string. if keyMappings is provided, that is searched first, and if nothing is
// found (or keyMappings is nil) then the global mappings are searched.
+ (int)actionForKeyCode:(unichar)keyCode
              modifiers:(unsigned int)keyMods
                   text:(NSString **)text
            keyMappings:(NSDictionary *)keyMappings;

// Remove an item from the bookmark's keymappings by index.
+ (void)removeMappingAtIndex:(int)rowIndex inBookmark:(NSMutableDictionary*)bookmark;

// Return a dictionary that is a copy of dict, but without the keymapping at the
// requested index.
+ (NSMutableDictionary*)removeMappingAtIndex:(int)rowIndex inDictionary:(NSDictionary*)dict;

// load an xml plist with the given filename, and return it in dictionary
// format.
+ (NSDictionary*)readPresetKeyMappingsFromPlist:(NSString *)thePlist;

+ (NSArray *)globalPresetNames;

// Return an array containing the names of all the presets available in
// the PresetKeyMapping.plist file
+ (NSArray*)presetKeyMappingsNames;

// Load a set of preset keymappings from PresetKeyMappings.plist into the
// specified bookmarks, removing all of its previous mappings.
+ (void)setKeyMappingsToPreset:(NSString*)presetName inBookmark:(NSMutableDictionary*)bookmark;

// Load a set of preset keymappings from GlobalKeyMap.plist into the global
// keymappings, removing all previous mappings.
+ (void)setGlobalKeyMappingsToPreset:(NSString*)presetName;

+ (NSArray *)sortedGlobalKeyCombinations;
+ (NSArray *)sortedKeyCombinationsForProfile:(Profile *)profile;

// This function has two modes:
// If newMapping is false, replace a mapping at the specified index. The index
// must be in bounds.
// If newMapping is true, either replace the existing mapping for the given keyString
// (0xKeycode-0xModifier) or add a new one if there is no existing mapping.
//
// actionIndex takes a constant from the KEY_ACTION_xxx values.
//
// valueToSend must not be null, but if the actionIndex doesn't take an argument,
// you should pass @"".
//
// bookmark will be modified in place.
+ (void)setMappingAtIndex:(int)rowIndex
                   forKey:(NSString*)keyString
                   action:(int)actionIndex
                    value:(NSString*)valueToSend
                createNew:(BOOL)newMapping
               inBookmark:(NSMutableDictionary*)bookmark;

// Replace an existing key mapping in a key mapping dictionary.
+ (void)setMappingAtIndex:(int)rowIndex
                   forKey:(NSString*)keyString
                   action:(int)actionIndex
                    value:(NSString*)valueToSend
                createNew:(BOOL)newMapping
             inDictionary:(NSMutableDictionary*)km;

// Return a shortcut (0xKeycode-0xModifier) by index from a bookmark.
+ (NSString*)shortcutAtIndex:(int)rowIndex forBookmark:(Profile*)bookmark;

// Return a shortcut (0xKeycode-0xModifier) from the global keymappings.
+ (NSString*)globalShortcutAtIndex:(int)rowIndex;

// Return a keymapping dict (having keys Action, Text) at a given index from a
// bookmark.
+ (NSDictionary*)mappingAtIndex:(int)rowIndex forBookmark:(Profile*)bookmark;

// Return a keymapping dict (having keys Action, Text) at a given index from the
// global key mappings.
+ (NSDictionary*)globalMappingAtIndex:(int)rowIndex;

+ (NSDictionary *)keyMappingsForProfile:(Profile *)profile;

// Return the number of key mappings in a bookmark.
+ (int)numberOfMappingsForBookmark:(Profile*)bmDict;

// Remove a keymapping with a given keycode and modifier mask from a bookmark.
+ (void)removeMappingWithCode:(unichar)keyCode
                    modifiers:(unsigned int)mods
                   inBookmark:(NSMutableDictionary*)bookmark;

// Return the action (a value from the constant KEY_ACTION_xxx) for a given keycode
// and modifiers, searching only the specified keymappings dictionary.
+ (int)localActionForKeyCode:(unichar)keyCode
                   modifiers:(unsigned int)keyMods
                        text:(NSString **)text
                 keyMappings:(NSDictionary *)keyMappings;

// Modify a keypress event, swapping modifiers as defined in the global settings.
+ (CGEventRef)remapModifiersInCGEvent:(CGEventRef)cgEvent;

// Like remapModifiersInCGEvent:prefPanel: but for an NSEvent.
+ (NSEvent*)remapModifiers:(NSEvent*)event;

// Returns the global keymap ("0xKeycode-0xModifiers"->{Action=int, [Text=str])
+ (NSDictionary*)globalKeyMap;

// Replace the global keymap with a new dictionary.
+ (void)setGlobalKeyMap:(NSDictionary*)src;

// True if a keystring 0xKeycode-0xModifiers has any global mapping.
+ (BOOL)haveGlobalKeyMappingForKeyString:(NSString*)keyString;

// True if a bookmark has a mapping for a 0xKeycode-0xModifiers keystring.
+ (BOOL)haveKeyMappingForKeyString:(NSString*)keyString inBookmark:(Profile*)bookmark;

// Remove any keymappings that reference a guid from either a bookmark or the global
// keymappings (if bookmark is nil). If a bookmark is specified but no change is made then
// it returns nil. If a bookmark is specified and changed, an autorelease copy of the modified
// bookmark is returned.
+ (Profile*)removeMappingsReferencingGuid:(NSString*)guid fromBookmark:(Profile*)bookmark;

@end

