/*
 **  iTermKeyBindingMgr.m
 **
 **  Copyright (c) 2002, 2003, 2004
 **
 **  Author: Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: implements the key binding manager.
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
// The remapModifiers function has code with this license:
/*
 * Copyright (c) 2009, 2010 <andrew iain mcdermott via gmail>
 *
 * Source can be cloned from:
 *
 *  git://github.com/aim-stuff/cmd-key-happy.git
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
/*
 * Note: xterm reports new escape codes for modifiers like Shift + any key,
 * like, for instance, the cursor keys as of 2006.
 *
 * Excerpt from terminfo:
 *  kLFT=\E[1;2D,
 *  kRIT=\E[1;2C,
 *  ...
 *
 * Also, the default setting of the xterm setting "modifyCursorKeys"
 * changed to "2" which will generate these new escape codes.
 * The old ones can be seen by setting it to zero, although they are
 * obsolete.
 *
 * Please check with "infocmp -L xterm" and "read", if anything behaves
 * weird in iTerm2 and the reported escape code is wrong.
 *
 * For checking the escape codes, run "read" (a shell builtin) and press
 * the key combination you want to know the code of, like, Shift + Arrow
 * Left.
 */

#import "ITAddressBookMgr.h"
#import <iTerm/iTermKeyBindingMgr.h>
#import <Carbon/Carbon.h>
#import "PreferencePanel.h"

static NSDictionary* globalKeyMap;

@implementation iTermKeyBindingMgr

+ (NSString *)formatKeyCombination:(NSString *)theKeyCombination
{
    unsigned int keyMods;
    unsigned int keyCode;
    NSString *aString;
    NSMutableString *theKeyString;
    keyCode = keyMods = 0;
    sscanf([theKeyCombination UTF8String], "%x-%x", &keyCode, &keyMods);
    BOOL isArrow = NO;
    switch (keyCode) {
        case NSDownArrowFunctionKey:
            aString = @"↓";
            isArrow = YES;
            break;
        case NSLeftArrowFunctionKey:
            aString = @"←";
            isArrow = YES;
            break;
        case NSRightArrowFunctionKey:
            aString =@"→";
            isArrow = YES;
            break;
        case NSUpArrowFunctionKey:
            aString = @"↑";
            isArrow = YES;
            break;
        case NSDeleteFunctionKey:
            aString = NSLocalizedStringFromTableInBundle(@"Del→",
                                                         @"iTerm",
                                                         [NSBundle bundleForClass:[self class]],
                                                         @"Key Names");
            break;
        case 0x7f:
            aString = NSLocalizedStringFromTableInBundle(@"←Delete",
                                                         @"iTerm",
                                                         [NSBundle bundleForClass:[self class]],
                                                         @"Key Names");
            break;
        case NSEndFunctionKey:
            aString = NSLocalizedStringFromTableInBundle(@"End",
                                                         @"iTerm",
                                                         [NSBundle bundleForClass:[self class]],
                                                         @"Key Names");
            break;
        case NSF1FunctionKey:
        case NSF2FunctionKey:
        case NSF3FunctionKey:
        case NSF4FunctionKey:
        case NSF5FunctionKey:
        case NSF6FunctionKey:
        case NSF7FunctionKey:
        case NSF8FunctionKey:
        case NSF9FunctionKey:
        case NSF10FunctionKey:
        case NSF11FunctionKey:
        case NSF12FunctionKey:
        case NSF13FunctionKey:
        case NSF14FunctionKey:
        case NSF15FunctionKey:
        case NSF16FunctionKey:
        case NSF17FunctionKey:
        case NSF18FunctionKey:
        case NSF19FunctionKey:
        case NSF20FunctionKey:
            aString = [NSString stringWithFormat: @"F%d", (keyCode - NSF1FunctionKey + 1)];
            break;
        case NSHelpFunctionKey:
            aString = NSLocalizedStringFromTableInBundle(@"Help",
                                                         @"iTerm",
                                                         [NSBundle bundleForClass:[self class]],
                                                         @"Key Names");
            break;
        case NSHomeFunctionKey:
            aString = NSLocalizedStringFromTableInBundle(@"Home",
                                                         @"iTerm",
                                                         [NSBundle bundleForClass:[self class]],
                                                         @"Key Names");
            break;
        case '0':
        case '1':
        case '2':
        case '3':
        case '4':
        case '5':
        case '6':
        case '7':
        case '8':
        case '9':
            aString = [NSString stringWithFormat: @"%d", (keyCode - '0')];
            break;
        case '=':
            aString = @"=";
            break;
        case '/':
            aString = @"/";
            break;
        case '*':
            aString = @"*";
            break;
        case '-':
            aString = @"-";
            break;
        case '+':
            aString = @"+";
            break;
        case '.':
            aString = @".";
            break;
        case NSClearLineFunctionKey:
            aString = NSLocalizedStringFromTableInBundle(@"Numlock",
                                                         @"iTerm",
                                                         [NSBundle bundleForClass: [self class]],
                                                         @"Key Names");
            break;
        case NSPageDownFunctionKey:
            aString = NSLocalizedStringFromTableInBundle(@"Page Down",
                                                         @"iTerm",
                                                         [NSBundle bundleForClass: [self class]],
                                                         @"Key Names");
            break;
        case NSPageUpFunctionKey:
            aString = NSLocalizedStringFromTableInBundle(@"Page Up",
                                                         @"iTerm",
                                                         [NSBundle bundleForClass: [self class]],
                                                         @"Key Names");
            break;
        case 0x3: // 'enter' on numeric key pad
            aString = @"↩";
            break;
        case NSInsertCharFunctionKey:
            aString = NSLocalizedStringFromTableInBundle(@"Insert",
                                                         @"iTerm",
                                                         [NSBundle bundleForClass: [self class]],
                                                         @"Key Names");
            break;

        default:
            if (keyCode >= '!' && keyCode <= '~') {
                aString = [NSString stringWithFormat:@"%c", keyCode];
            } else {
                switch (keyCode) {
                    case ' ':
                        aString = @"Space";
                        break;

                    case '\r':
                        aString = @"↩";
                        break;

                    case 27:
                        aString = @"⎋";
                        break;

                    case '\t':
                        aString = @"↦";
                        break;

                    case 0x19:
                        // back-tab
                        aString = @"↤";
                        break;

                    default:
                        aString = [NSString stringWithFormat: @"%@ 0x%x",
                                   NSLocalizedStringFromTableInBundle(@"Hex Code",
                                                                      @"iTerm",
                                                                      [NSBundle bundleForClass: [self class]],
                                                                      @"Key Names"),
                                   keyCode];
                        break;
                }
            }
            break;
    }

    theKeyString = [[NSMutableString alloc] initWithString: @""];
    if (keyMods & NSControlKeyMask) {
        [theKeyString appendString: @"^"];
    }
    if (keyMods & NSAlternateKeyMask) {
        [theKeyString appendString: @"⌥"];
    }
    if (keyMods & NSShiftKeyMask) {
        [theKeyString appendString: @"⇧"];
    }
    if (keyMods & NSCommandKeyMask) {
        [theKeyString appendString: @"⌘"];
    }
    if ((keyMods & NSNumericPadKeyMask) && !isArrow) {
        [theKeyString appendString: @"num-"];
    }
    [theKeyString appendString: aString];
    return [theKeyString autorelease];
}

+ (NSString*)_bookmarkNameForGuid:(NSString*)guid
{
    return [[[BookmarkModel sharedInstance] bookmarkWithGuid:guid] objectForKey:KEY_NAME];
}

+ (NSString *)formatAction:(NSDictionary *)keyInfo
{
    NSString *actionString;
    int action;
    NSString *auxText;

    action = [[keyInfo objectForKey: @"Action"] intValue];
    auxText = [keyInfo objectForKey: @"Text"];

    switch (action) {
        case KEY_ACTION_NEXT_SESSION:
            actionString = NSLocalizedStringFromTableInBundle(@"Next Tab",
                                                              @"iTerm",
                                                              [NSBundle bundleForClass: [self class]],
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_NEXT_WINDOW:
            actionString = NSLocalizedStringFromTableInBundle(@"Next Window",
                                                              @"iTerm",
                                                              [NSBundle bundleForClass: [self class]],
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_PREVIOUS_SESSION:
            actionString = NSLocalizedStringFromTableInBundle(@"Previous Tab",
                                                              @"iTerm",
                                                              [NSBundle bundleForClass: [self class]],
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_PREVIOUS_WINDOW:
            actionString = NSLocalizedStringFromTableInBundle(@"Previous Window",
                                                              @"iTerm",
                                                              [NSBundle bundleForClass: [self class]],
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_SCROLL_END:
            actionString = NSLocalizedStringFromTableInBundle(@"Scroll To End",
                                                              @"iTerm",
                                                              [NSBundle bundleForClass: [self class]],
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_SCROLL_HOME:
            actionString = NSLocalizedStringFromTableInBundle(@"Scroll To Top",
                                                              @"iTerm",
                                                              [NSBundle bundleForClass: [self class]],
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_SCROLL_LINE_DOWN:
            actionString = NSLocalizedStringFromTableInBundle(@"Scroll One Line Down",
                                                              @"iTerm",
                                                              [NSBundle bundleForClass: [self class]],
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_SCROLL_LINE_UP:
            actionString = NSLocalizedStringFromTableInBundle(@"Scroll One Line Up",
                                                              @"iTerm",
                                                              [NSBundle bundleForClass: [self class]],
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_SCROLL_PAGE_DOWN:
            actionString = NSLocalizedStringFromTableInBundle(@"Scroll One Page Down",
                                                              @"iTerm",
                                                              [NSBundle bundleForClass: [self class]],
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_SCROLL_PAGE_UP:
            actionString = NSLocalizedStringFromTableInBundle(@"Scroll One Page Up",
                                                              @"iTerm",
                                                              [NSBundle bundleForClass: [self class]],
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_ESCAPE_SEQUENCE:
            actionString = [NSString stringWithFormat:@"%@ %@",
                NSLocalizedStringFromTableInBundle(@"Send ^[",
                                                   @"iTerm",
                                                   [NSBundle bundleForClass: [self class]],
                                                   @"Key Binding Actions"),
                auxText];
            break;
        case KEY_ACTION_HEX_CODE:
            actionString = [NSString stringWithFormat: @"%@ %@",
                NSLocalizedStringFromTableInBundle(@"Send Hex Codes:",
                                                   @"iTerm",
                                                   [NSBundle bundleForClass: [self class]],
                                                   @"Key Binding Actions"),
                auxText];
            break;
        case KEY_ACTION_TEXT:
            actionString = [NSString stringWithFormat:@"%@ \"%@\"",
                NSLocalizedStringFromTableInBundle(@"Send:",
                                                   @"iTerm",
                                                   [NSBundle bundleForClass: [self class]],
                                                   @"Key Binding Actions"),
                auxText];
            break;
        case KEY_ACTION_SELECT_MENU_ITEM:
            actionString = [NSString stringWithFormat:@"%@ \"%@\"",
                            NSLocalizedStringFromTableInBundle(@"Select Menu Item",
                                                               @"iTerm",
                                                               [NSBundle bundleForClass: [self class]],
                                                               @"Key Binding Actions"),
                            auxText];
            break;
        case KEY_ACTION_NEW_WINDOW_WITH_PROFILE:
            actionString = [NSString stringWithFormat:@"New Window with \"%@\" Profile", [self _bookmarkNameForGuid:auxText]];
            break;
        case KEY_ACTION_NEW_TAB_WITH_PROFILE:
            actionString = [NSString stringWithFormat:@"New Tab with \"%@\" Profile", [self _bookmarkNameForGuid:auxText]];
            break;
        case KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE:
            actionString = [NSString stringWithFormat:@"Split Horizontally with \"%@\" Profile", [self _bookmarkNameForGuid:auxText]];
            break;
        case KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE:
            actionString = [NSString stringWithFormat:@"Split Vertically with \"%@\" Profile", [self _bookmarkNameForGuid:auxText]];
            break;

        case KEY_ACTION_SEND_C_H_BACKSPACE:
            actionString = @"Send ^H Backspace";
            break;
        case KEY_ACTION_SEND_C_QM_BACKSPACE:
            actionString = @"Send ^? Backspace";
            break;
        case KEY_ACTION_IGNORE:
            actionString = NSLocalizedStringFromTableInBundle(@"Ignore",
                                                              @"iTerm",
                                                              [NSBundle bundleForClass:[self class]],
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_IR_FORWARD:
            actionString = @"Forward in Time";
            break;
        case KEY_ACTION_IR_BACKWARD:
            actionString = @"Backward in Time";
            break;
        case KEY_ACTION_SELECT_PANE_LEFT:
            actionString = @"Select Split Pane on Left";
            break;
        case KEY_ACTION_SELECT_PANE_RIGHT:
            actionString = @"Select Split Pane on Right";
            break;
        case KEY_ACTION_SELECT_PANE_ABOVE:
            actionString = @"Select Split Pane Above";
            break;
        case KEY_ACTION_SELECT_PANE_BELOW:
            actionString = @"Select Split Pane Below";
            break;
        case KEY_ACTION_DO_NOT_REMAP_MODIFIERS:
            actionString = @"Do Not Remap Modifiers";
            break;
        case KEY_ACTION_REMAP_LOCALLY:
            actionString = @"Remap Modifiers in iTerm2 Only";
            break;
        case KEY_ACTION_TOGGLE_FULLSCREEN:
            actionString = @"Toggle Fullscreen";
            break;
        default:
            actionString = [NSString stringWithFormat: @"%@ %d",
                NSLocalizedStringFromTableInBundle(@"Unknown Action ID",
                                                   @"iTerm",
                                                   [NSBundle bundleForClass:[self class]],
                                                   @"Key Binding Actions"),
                action];
            break;
    }

    return actionString;
}

+ (BOOL)haveGlobalKeyMappingForKeyString:(NSString*)keyString
{
    return [[self globalKeyMap] objectForKey:keyString] != nil;
}

+ (BOOL)haveKeyMappingForKeyString:(NSString*)keyString inBookmark:(Bookmark*)bookmark
{
    NSDictionary *dict = [bookmark objectForKey:KEY_KEYBOARD_MAP];
    return [dict objectForKey:keyString] != nil;
}

+ (int)localActionForKeyCode:(unichar)keyCode
                   modifiers:(unsigned int) keyMods
                        text:(NSString **) text
                 keyMappings:(NSDictionary *)keyMappings
{
    NSString *keyString;
    NSDictionary *theKeyMapping;
    int retCode = -1;
    unsigned int theModifiers;

    // turn off all the other modifier bits we don't care about
    theModifiers = keyMods & (NSAlternateKeyMask | NSControlKeyMask | NSShiftKeyMask | NSCommandKeyMask | NSNumericPadKeyMask);

    // on some keyboards, arrow keys have NSNumericPadKeyMask bit set; manually set it for keyboards that don't
    if (keyCode >= NSUpArrowFunctionKey && keyCode <= NSRightArrowFunctionKey) {
        theModifiers |= NSNumericPadKeyMask;
    }

    keyString = [NSString stringWithFormat: @"0x%x-0x%x", keyCode, theModifiers];
    theKeyMapping = [keyMappings objectForKey: keyString];
    if (theKeyMapping == nil) {
        if (text) {
            *text = nil;
        }
        return -1;
    }

    // parse the mapping
    retCode = [[theKeyMapping objectForKey: @"Action"] intValue];
    if(text != nil)
        *text = [theKeyMapping objectForKey: @"Text"];

    return (retCode);
}

+ (void)_loadGlobalKeyMap
{
    globalKeyMap = [[NSUserDefaults standardUserDefaults] objectForKey:@"GlobalKeyMap"];
    if (!globalKeyMap) {
        NSString* plistFile = [[NSBundle bundleForClass: [self class]] pathForResource:@"DefaultGlobalKeyMap" ofType:@"plist"];
        globalKeyMap = [NSDictionary dictionaryWithContentsOfFile:plistFile];
    }
    [globalKeyMap retain];
}

+ (NSDictionary*)globalKeyMap
{
    if (!globalKeyMap) {
        [iTermKeyBindingMgr _loadGlobalKeyMap];
    }
    return globalKeyMap;
}

+ (void)setGlobalKeyMap:(NSDictionary*)src
{
    [globalKeyMap release];
    globalKeyMap = [src copy];
    [[NSUserDefaults standardUserDefaults] setObject:globalKeyMap forKey:@"GlobalKeyMap"];
}

+ (int)actionForKeyCode:(unichar)keyCode
              modifiers:(unsigned int) keyMods
                   text:(NSString **) text
            keyMappings:(NSDictionary *)keyMappings
{
    int keyBindingAction = -1;
    if (keyMappings) {
        keyBindingAction = [iTermKeyBindingMgr localActionForKeyCode:keyCode
                                                           modifiers:keyMods
                                                                text:text
                                                         keyMappings:keyMappings];
    }
    if (keyMappings != [self globalKeyMap] && keyBindingAction < 0) {
        keyBindingAction = [iTermKeyBindingMgr localActionForKeyCode:keyCode
                                                           modifiers:keyMods
                                                                text:text
                                                         keyMappings:[self globalKeyMap]];
    }
    return keyBindingAction;
}

+ (NSMutableDictionary*)removeMappingAtIndex:(int)rowIndex inDictionary:(NSDictionary*)dict
{
    NSMutableDictionary* km = [NSMutableDictionary dictionaryWithDictionary:dict];
    NSArray* allKeys = [[km allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    if (rowIndex >= 0 && rowIndex < [allKeys count]) {
        [km removeObjectForKey:[allKeys objectAtIndex:rowIndex]];
    }
    return km;
}

+ (void)removeMappingAtIndex:(int)rowIndex inBookmark:(NSMutableDictionary*)bookmark
{
    [bookmark setObject:[iTermKeyBindingMgr removeMappingAtIndex:rowIndex
                                                    inDictionary:[bookmark objectForKey:KEY_KEYBOARD_MAP]]
                 forKey:KEY_KEYBOARD_MAP];
}

+ (void)setGlobalKeyMappingsToPreset:(NSString*)presetName
{
    assert([presetName isEqualToString:@"Factory Defaults"]);
    if (globalKeyMap) {
        [globalKeyMap release];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"GlobalKeyMap"];
    }
    [self _loadGlobalKeyMap];
}

+ (NSDictionary*)readPresetKeyMappingsFromPlist:(NSString *)thePlist {
    NSString* plistFile = [[NSBundle bundleForClass:[self class]]
                            pathForResource:thePlist ofType:@"plist"];
    NSDictionary* dict = [NSDictionary dictionaryWithContentsOfFile:plistFile];
    return dict;
}

+ (void)setKeyMappingsToPreset:(NSString*)presetName inBookmark:(NSMutableDictionary*)bookmark
{
    NSMutableDictionary* km = [NSMutableDictionary dictionaryWithDictionary:[bookmark objectForKey:KEY_KEYBOARD_MAP]];

    [km removeAllObjects];
    NSDictionary* presetsDict 
        = [self readPresetKeyMappingsFromPlist:@"PresetKeyMappings"];

    NSDictionary* settings = [presetsDict objectForKey:presetName];
    [km setDictionary:settings];

    [bookmark setObject:km forKey:KEY_KEYBOARD_MAP];
}

+ (NSArray *)presetKeyMappingsNames
{
    NSDictionary* presetsDict 
        = [self readPresetKeyMappingsFromPlist:@"PresetKeyMappings"];
    NSArray* names = [presetsDict allKeys];
    return names;
}

+ (void)setMappingAtIndex:(int)rowIndex
                   forKey:(NSString*)keyString
                   action:(int)actionIndex
                    value:(NSString*)valueToSend
                createNew:(BOOL)newMapping
             inDictionary:(NSMutableDictionary*)km
{
    NSString* origKeyCombo = nil;
    NSArray* allKeys =
        [[km allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    if (!newMapping) {
        if (rowIndex >= 0 && rowIndex < [allKeys count]) {
            origKeyCombo = [allKeys objectAtIndex:rowIndex];
        } else {
            return;
        }
    } else if ([km objectForKey:keyString]) {
        // new mapping but same key combo as an existing one - overwrite it
        origKeyCombo = keyString;
    } else {
        // creating a new mapping and it doesn't collide with an existing one
        origKeyCombo = nil;
    }

    NSMutableDictionary* keyBinding =
        [[[NSMutableDictionary alloc] init] autorelease];
    [keyBinding setObject:[NSNumber numberWithInt:actionIndex]
                   forKey:@"Action"];
    [keyBinding setObject:[[valueToSend copy] autorelease] forKey:@"Text"];
    if (origKeyCombo) {
        [km removeObjectForKey:origKeyCombo];
    }
    [km setObject:keyBinding forKey:keyString];
}

+ (void)setMappingAtIndex:(int)rowIndex
                   forKey:(NSString*)keyString
                   action:(int)actionIndex
                    value:(NSString*)valueToSend
                createNew:(BOOL)newMapping
               inBookmark:(NSMutableDictionary*)bookmark
{

    NSMutableDictionary* km =
        [NSMutableDictionary dictionaryWithDictionary:[bookmark objectForKey:KEY_KEYBOARD_MAP]];
    [iTermKeyBindingMgr setMappingAtIndex:rowIndex forKey:keyString action:actionIndex value:valueToSend createNew:newMapping inDictionary:km];
    [bookmark setObject:km forKey:KEY_KEYBOARD_MAP];
}

+ (NSString*)shortcutAtIndex:(int)rowIndex forBookmark:(Bookmark*)bookmark
{
    NSDictionary* km = [bookmark objectForKey:KEY_KEYBOARD_MAP];
    NSArray* allKeys = [[km allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    if (rowIndex >= 0 && rowIndex < [allKeys count]) {
        return [allKeys objectAtIndex:rowIndex];
    } else {
        return nil;
    }
}

+ (NSString*)globalShortcutAtIndex:(int)rowIndex
{
    NSDictionary* km = [self globalKeyMap];
    NSArray* allKeys = [[km allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    if (rowIndex >= 0 && rowIndex < [allKeys count]) {
        return [allKeys objectAtIndex:rowIndex];
    } else {
        return nil;
    }
}

+ (NSDictionary*)mappingAtIndex:(int)rowIndex forBookmark:(Bookmark*)bookmark
{
    NSDictionary* km = [bookmark objectForKey:KEY_KEYBOARD_MAP];
    NSArray* allKeys = [[km allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    if (rowIndex >= 0 && rowIndex < [allKeys count]) {
        return [km objectForKey:[allKeys objectAtIndex:rowIndex]];
    } else {
        return nil;
    }
}

+ (NSDictionary*)globalMappingAtIndex:(int)rowIndex
{
    NSDictionary* km = [self globalKeyMap];
    NSArray* allKeys = [[km allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    if (rowIndex >= 0 && rowIndex < [allKeys count]) {
        return [km objectForKey:[allKeys objectAtIndex:rowIndex]];
    } else {
        return nil;
    }
}

+ (int)numberOfMappingsForBookmark:(Bookmark*)bmDict
{
    NSDictionary* keyMapDict = [bmDict objectForKey:KEY_KEYBOARD_MAP];
    return [keyMapDict count];
}

+ (void)removeMappingWithCode:(unichar)keyCode
                    modifiers:(unsigned int)mods
                   inBookmark:(NSMutableDictionary*)bookmark
{
    NSMutableDictionary* km = [NSMutableDictionary dictionaryWithDictionary:[bookmark objectForKey:KEY_KEYBOARD_MAP]];
    NSString* keyString = [NSString stringWithFormat:@"0x%x-0x%x", keyCode, mods];
    [km removeObjectForKey:keyString];
    [bookmark setObject:km forKey:KEY_KEYBOARD_MAP];
}

+ (NSInteger)_cgMaskForMod:(int)mod
{
    switch (mod) {
        case MOD_TAG_CONTROL:
            return kCGEventFlagMaskControl;

        case MOD_TAG_LEFT_OPTION:
        case MOD_TAG_RIGHT_OPTION:
        case MOD_TAG_OPTION:
            return kCGEventFlagMaskAlternate;

        case MOD_TAG_ANY_COMMAND:
        case MOD_TAG_LEFT_COMMAND:
        case MOD_TAG_RIGHT_COMMAND:
            return kCGEventFlagMaskCommand;

        case MOD_TAG_CMD_OPT:
            return kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate;

        default:
            return 0;
    }
}

+ (NSInteger)_nxMaskForLeftMod:(int)mod
{
    switch (mod) {
        case MOD_TAG_CONTROL:
            return NX_DEVICELCTLKEYMASK;

        case MOD_TAG_LEFT_OPTION:
            return NX_DEVICELALTKEYMASK;

        case MOD_TAG_RIGHT_OPTION:
            return NX_DEVICERALTKEYMASK;

        case MOD_TAG_OPTION:
            return NX_DEVICELALTKEYMASK;

        case MOD_TAG_RIGHT_COMMAND:
            return NX_DEVICERCMDKEYMASK;

        case MOD_TAG_LEFT_COMMAND:
        case MOD_TAG_ANY_COMMAND:
            return NX_DEVICELCMDKEYMASK;

        case MOD_TAG_CMD_OPT:
            return NX_DEVICELCMDKEYMASK | NX_DEVICELALTKEYMASK;

        default:
            return 0;
    }
}

+ (NSInteger)_nxMaskForRightMod:(int)mod
{
    switch (mod) {
        case MOD_TAG_CONTROL:
            return NX_DEVICERCTLKEYMASK;

        case MOD_TAG_LEFT_OPTION:
            return NX_DEVICELALTKEYMASK;

        case MOD_TAG_RIGHT_OPTION:
            return NX_DEVICERALTKEYMASK;

        case MOD_TAG_OPTION:
            return NX_DEVICERALTKEYMASK;

        case MOD_TAG_LEFT_COMMAND:
            return NX_DEVICELCMDKEYMASK;

        case MOD_TAG_RIGHT_COMMAND:
        case MOD_TAG_ANY_COMMAND:
            return NX_DEVICERCMDKEYMASK;

        case MOD_TAG_CMD_OPT:
            return NX_DEVICERCMDKEYMASK | NX_DEVICERALTKEYMASK;

        default:
            return 0;
    }
}

+ (NSInteger)_cgMaskForLeftCommandKey:(PreferencePanel*)pp
{
    return [self _cgMaskForMod:[pp leftCommand]];
}

+ (NSInteger)_cgMaskForRightCommandKey:(PreferencePanel*)pp
{
    return [self _cgMaskForMod:[pp rightCommand]];
}

+ (NSInteger)_nxMaskForLeftCommandKey:(PreferencePanel*)pp
{
    return [self _nxMaskForLeftMod:[pp leftCommand]];
}

+ (NSInteger)_nxMaskForRightCommandKey:(PreferencePanel*)pp
{
    return [self _nxMaskForRightMod:[pp rightCommand]];
}

+ (NSInteger)_cgMaskForLeftAlternateKey:(PreferencePanel*)pp
{
    return [self _cgMaskForMod:[pp leftOption]];
}

+ (NSInteger)_cgMaskForRightAlternateKey:(PreferencePanel*)pp
{
    return [self _cgMaskForMod:[pp rightOption]];
}

+ (NSInteger)_nxMaskForLeftAlternateKey:(PreferencePanel*)pp
{
    return [self _nxMaskForLeftMod:[pp leftOption]];
}

+ (NSInteger)_nxMaskForRightAlternateKey:(PreferencePanel*)pp
{
    return [self _nxMaskForRightMod:[pp rightOption]];
}

+ (NSInteger)_cgMaskForLeftControlKey:(PreferencePanel*)pp
{
    return [self _cgMaskForMod:[pp control]];
}

+ (NSInteger)_cgMaskForRightControlKey:(PreferencePanel*)pp
{
    return [self _cgMaskForMod:[pp control]];
}

+ (NSInteger)_nxMaskForLeftControlKey:(PreferencePanel*)pp
{
    return [self _nxMaskForLeftMod:[pp control]];
}

+ (NSInteger)_nxMaskForRightControlKey:(PreferencePanel*)pp
{
    return [self _nxMaskForRightMod:[pp control]];
}

+ (CGEventRef)remapModifiersInCGEvent:(CGEventRef)cgEvent prefPanel:(PreferencePanel*)pp
{
    // This function copied from cmd-key happy. See copyright notice at top.
    CGEventFlags flags = CGEventGetFlags(cgEvent);
    const CGEventFlags origFlags = flags;
    CGEventFlags andMask = -1;
    CGEventFlags orMask = 0;
    if (origFlags & kCGEventFlagMaskCommand) {
        andMask &= ~kCGEventFlagMaskCommand;
        if (flags & NX_DEVICELCMDKEYMASK) {
            andMask &= ~NX_DEVICELCMDKEYMASK;
            orMask |= [self _cgMaskForLeftCommandKey:pp];
            orMask |= [self _nxMaskForLeftCommandKey:pp];
        }
        if (flags & NX_DEVICERCMDKEYMASK) {
            andMask &= ~NX_DEVICERCMDKEYMASK;
            orMask |= [self _cgMaskForRightCommandKey:pp];
            orMask |= [self _nxMaskForRightCommandKey:pp];
        }
    }
    if (origFlags & kCGEventFlagMaskAlternate) {
        andMask &= ~kCGEventFlagMaskAlternate;
        if (flags & NX_DEVICELALTKEYMASK) {
            andMask &= ~NX_DEVICELALTKEYMASK;
            orMask |= [self _cgMaskForLeftAlternateKey:pp];
            orMask |= [self _nxMaskForLeftAlternateKey:pp];
        }
        if (flags & NX_DEVICERALTKEYMASK) {
            andMask &= ~NX_DEVICERALTKEYMASK;
            orMask |= [self _cgMaskForRightAlternateKey:pp];
            orMask |= [self _nxMaskForRightAlternateKey:pp];
        }
    }
    if (origFlags & kCGEventFlagMaskControl) {
        andMask &= ~kCGEventFlagMaskControl;
        if (flags & NX_DEVICELCTLKEYMASK) {
            andMask &= ~NX_DEVICELCTLKEYMASK;
            orMask |= [self _cgMaskForLeftControlKey:pp];
            orMask |= [self _nxMaskForLeftControlKey:pp];
        }
        if (flags & NX_DEVICERCTLKEYMASK) {
            andMask &= ~NX_DEVICERCTLKEYMASK;
            orMask |= [self _cgMaskForRightControlKey:pp];
            orMask |= [self _nxMaskForRightControlKey:pp];
        }
    }

    CGEventSetFlags(cgEvent, (flags & andMask) | orMask);
    return cgEvent;
}

+ (NSEvent*)remapModifiers:(NSEvent*)event prefPanel:(PreferencePanel*)pp
{
    return [NSEvent eventWithCGEvent:[iTermKeyBindingMgr remapModifiersInCGEvent:[event CGEvent]
                                                                       prefPanel:pp]];
}

+ (Bookmark*)removeMappingsReferencingGuid:(NSString*)guid fromBookmark:(Bookmark*)bookmark
{
    if (bookmark) {
        NSMutableDictionary* mutableBookmark = [NSMutableDictionary dictionaryWithDictionary:bookmark];
        BOOL anyChange = NO;
        BOOL change;
        do {
            change = NO;
            for (int i = 0; i < [iTermKeyBindingMgr numberOfMappingsForBookmark:mutableBookmark]; i++) {
                NSDictionary* keyMap = [iTermKeyBindingMgr mappingAtIndex:i forBookmark:mutableBookmark];
                int action = [[keyMap objectForKey:@"Action"] intValue];
                if (action == KEY_ACTION_NEW_TAB_WITH_PROFILE ||
                    action == KEY_ACTION_NEW_WINDOW_WITH_PROFILE ||
                    action == KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE ||
                    action == KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE) {
                    NSString* referencedGuid = [keyMap objectForKey:@"Text"];
                    if ([referencedGuid isEqualToString:guid]) {
                        [iTermKeyBindingMgr removeMappingAtIndex:i inBookmark:mutableBookmark];
                        change = YES;
                        anyChange = YES;
                        break;
                    }
                }
            }
        } while (change);
        if (!anyChange) {
            return nil;
        } else {
            return mutableBookmark;
        }
    } else {
        BOOL change;
        do {
            NSMutableDictionary* mutableGlobalKeyMap = [NSMutableDictionary dictionaryWithDictionary:[iTermKeyBindingMgr globalKeyMap]];
            change = NO;
            for (int i = 0; i < [mutableGlobalKeyMap count]; i++) {
                NSDictionary* keyMap = [iTermKeyBindingMgr globalMappingAtIndex:i];
                int action = [[keyMap objectForKey:@"Action"] intValue];
                if (action == KEY_ACTION_NEW_TAB_WITH_PROFILE ||
                    action == KEY_ACTION_NEW_WINDOW_WITH_PROFILE ||
                    action == KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE ||
                    action == KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE) {
                    NSString* referencedGuid = [keyMap objectForKey:@"Text"];
                    if ([referencedGuid isEqualToString:guid]) {
                        mutableGlobalKeyMap = [iTermKeyBindingMgr removeMappingAtIndex:i
                                                                          inDictionary:mutableGlobalKeyMap];
                        [iTermKeyBindingMgr setGlobalKeyMap:mutableGlobalKeyMap];
                        change = YES;
                        break;
                    }
                }
            }
        } while (change);
        return nil;
    }
}


@end
