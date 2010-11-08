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

@implementation iTermKeyBindingMgr

+ (NSString *) formatKeyCombination:(NSString *)theKeyCombination  
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
            aString = NSLocalizedStringFromTableInBundle(@"Del",@"iTerm", 
                                                         [NSBundle bundleForClass: [self class]], 
                                                         @"Key Names");
            break;
        case 0x7f:
            aString = NSLocalizedStringFromTableInBundle(@"Delete",@"iTerm", 
                                                         [NSBundle bundleForClass: [self class]], 
                                                         @"Key Names");
            break;
        case NSEndFunctionKey:
            aString = NSLocalizedStringFromTableInBundle(@"End",@"iTerm", 
                                                         [NSBundle bundleForClass: [self class]], 
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
            aString = NSLocalizedStringFromTableInBundle(@"Help",@"iTerm", 
                                                         [NSBundle bundleForClass: [self class]], 
                                                         @"Key Names"); 
            break;
        case NSHomeFunctionKey:
            aString = NSLocalizedStringFromTableInBundle(@"Home",@"iTerm", 
                                                         [NSBundle bundleForClass: [self class]], 
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
            aString = NSLocalizedStringFromTableInBundle(@"Numlock",@"iTerm", 
                                                         [NSBundle bundleForClass: [self class]], 
                                                         @"Key Names");
            break;
        case NSPageDownFunctionKey:
            aString = NSLocalizedStringFromTableInBundle(@"Page Down",@"iTerm", 
                                                         [NSBundle bundleForClass: [self class]], 
                                                         @"Key Names");
            break;
        case NSPageUpFunctionKey:
            aString = NSLocalizedStringFromTableInBundle(@"Page Up",@"iTerm", 
                                                         [NSBundle bundleForClass: [self class]], 
                                                         @"Key Names");
            break;
        case 0x3: // 'enter' on numeric key pad
            aString = @"↩";
            break;
        case NSInsertCharFunctionKey:
            aString = NSLocalizedStringFromTableInBundle(@"iIsert",@"iTerm", 
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
                                   NSLocalizedStringFromTableInBundle(@"hex code",@"iTerm", 
                                                                      [NSBundle bundleForClass: [self class]], 
                                                                      @"Key Names"),
                                   keyCode];
                        break;
                }
            }
            break;
    }
    
    theKeyString = [[NSMutableString alloc] initWithString: @""];
    if (keyMods & NSCommandKeyMask) {
        [theKeyString appendString: @"⌘"];
    }       
    if (keyMods & NSAlternateKeyMask) {
        [theKeyString appendString: @"⌥"];
    }
    if (keyMods & NSControlKeyMask) {
        [theKeyString appendString: @"^"];
    }
    if (keyMods & NSShiftKeyMask) {
        [theKeyString appendString: @"⇧"];
    }
    if ((keyMods & NSNumericPadKeyMask) && !isArrow) {
        [theKeyString appendString: @"num-"];
    }
    [theKeyString appendString: aString];
    return [theKeyString autorelease];
}


+ (NSString *)formatAction:(NSDictionary *)keyInfo
{
    NSString *actionString;
    int action;
    NSString *auxText;
    BOOL priority;

    action = [[keyInfo objectForKey: @"Action"] intValue];
    auxText = [keyInfo objectForKey: @"Text"];
    priority = [keyInfo objectForKey: @"Priority"] ? 
        [[keyInfo objectForKey: @"Priority"] boolValue] : NO;
    
    switch (action) {
        case KEY_ACTION_NEXT_SESSION:
            actionString = NSLocalizedStringFromTableInBundle(@"next tab",@"iTerm", 
                                                              [NSBundle bundleForClass: [self class]], 
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_NEXT_WINDOW:
            actionString = NSLocalizedStringFromTableInBundle(@"next window",@"iTerm", 
                                                              [NSBundle bundleForClass: [self class]], 
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_PREVIOUS_SESSION:
            actionString = NSLocalizedStringFromTableInBundle(@"previous tab",@"iTerm", 
                                                              [NSBundle bundleForClass: [self class]], 
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_PREVIOUS_WINDOW:
            actionString = NSLocalizedStringFromTableInBundle(@"previous window",@"iTerm", 
                                                              [NSBundle bundleForClass: [self class]], 
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_SCROLL_END:
            actionString = NSLocalizedStringFromTableInBundle(@"scroll end",@"iTerm", 
                                                              [NSBundle bundleForClass: [self class]], 
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_SCROLL_HOME:
            actionString = NSLocalizedStringFromTableInBundle(@"scroll home",@"iTerm", 
                                                              [NSBundle bundleForClass: [self class]], 
                                                              @"Key Binding Actions");
            break;          
        case KEY_ACTION_SCROLL_LINE_DOWN:
            actionString = NSLocalizedStringFromTableInBundle(@"scroll line down",@"iTerm", 
                                                              [NSBundle bundleForClass: [self class]], 
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_SCROLL_LINE_UP:
            actionString = NSLocalizedStringFromTableInBundle(@"scroll line up",@"iTerm", 
                                                              [NSBundle bundleForClass: [self class]], 
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_SCROLL_PAGE_DOWN:
            actionString = NSLocalizedStringFromTableInBundle(@"scroll page down",@"iTerm", 
                                                              [NSBundle bundleForClass: [self class]], 
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_SCROLL_PAGE_UP:
            actionString = NSLocalizedStringFromTableInBundle(@"scroll page up",@"iTerm", 
                                                              [NSBundle bundleForClass: [self class]], 
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_ESCAPE_SEQUENCE:
            actionString = [NSString stringWithFormat:@"%@ %@", 
                NSLocalizedStringFromTableInBundle(@"send ^[",@"iTerm", 
                                                              [NSBundle bundleForClass: [self class]], 
                                                              @"Key Binding Actions"),
                auxText];
            break;
        case KEY_ACTION_HEX_CODE:
            actionString = [NSString stringWithFormat: @"%@ %@", 
                NSLocalizedStringFromTableInBundle(@"send hex code",@"iTerm", 
                                                              [NSBundle bundleForClass: [self class]], 
                                                              @"Key Binding Actions"),
                auxText];
            break;          
        case KEY_ACTION_TEXT:
            actionString = [NSString stringWithFormat:@"%@ \"%@\"", 
                NSLocalizedStringFromTableInBundle(@"send",@"iTerm", 
                                                   [NSBundle bundleForClass: [self class]], 
                                                   @"Key Binding Actions"),
                auxText];
            break;
        case KEY_ACTION_IGNORE:
            actionString = NSLocalizedStringFromTableInBundle(@"ignore",@"iTerm", 
                                                              [NSBundle bundleForClass: [self class]], 
                                                              @"Key Binding Actions");
            break;
        case KEY_ACTION_IR_FORWARD:
            actionString = @"forward in time";
            break;
        case KEY_ACTION_IR_BACKWARD:
            actionString = @"backward in time";
            break;
        default:
            actionString = [NSString stringWithFormat: @"%@ %d", 
                NSLocalizedStringFromTableInBundle(@"unknown action ID",@"iTerm", 
                                                              [NSBundle bundleForClass: [self class]], 
                                                              @"Key Binding Actions"),
                action];
            break;
    }
    
    return (priority?[actionString stringByAppendingString:@" (!)"] : actionString);
}

+ (int) _actionForKeyCode:(unichar)keyCode 
                modifiers:(unsigned int) keyMods 
             highPriority:(BOOL *) highPriority 
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
    if (theKeyMapping == nil)
    {
        if(text)
            *text = nil;
        return (-1);
    }
    
    // parse the mapping
    retCode = [[theKeyMapping objectForKey: @"Action"] intValue];
    if(text != nil)
        *text = [theKeyMapping objectForKey: @"Text"];
    *highPriority = [theKeyMapping objectForKey: @"Priority"] ? [[theKeyMapping objectForKey: @"Priority"] boolValue] : NO;
    
    return (retCode);
}

+ (int) actionForKeyCode:(unichar)keyCode 
               modifiers:(unsigned int) keyMods 
            highPriority:(BOOL *) highPriority 
                    text:(NSString **) text 
             keyMappings:(NSDictionary *)keyMappings
{
    int keyBindingAction = [iTermKeyBindingMgr _actionForKeyCode:keyCode 
                                                       modifiers:keyMods 
                                                    highPriority:highPriority 
                                                            text:text 
                                                     keyMappings:keyMappings];
    if (keyBindingAction < 0) {
        static NSDictionary* globalKeyMap;
        if (!globalKeyMap) {
            NSString* plistFile = [[NSBundle bundleForClass: [self class]] pathForResource:@"DefaultGlobalKeyMap" ofType:@"plist"];   
            globalKeyMap = [NSDictionary dictionaryWithContentsOfFile:plistFile];
            [globalKeyMap retain];
        }
        if (globalKeyMap) {
            keyBindingAction = [iTermKeyBindingMgr _actionForKeyCode:keyCode 
                                                           modifiers:keyMods 
                                                        highPriority:highPriority 
                                                                text:text 
                                                         keyMappings:globalKeyMap];
        }
    }
    return keyBindingAction;
}

+ (void)removeMappingAtIndex:(int)rowIndex inBookmark:(NSMutableDictionary*)bookmark
{
    NSMutableDictionary* km = [NSMutableDictionary dictionaryWithDictionary:[bookmark objectForKey:KEY_KEYBOARD_MAP]];
    NSArray* allKeys = [[km allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    if (rowIndex >= 0 && rowIndex < [allKeys count]) {
        [km removeObjectForKey:[allKeys objectAtIndex:rowIndex]];
        [bookmark setObject:km forKey:KEY_KEYBOARD_MAP];
    } else {
        return;
    }
    
}

+ (void)setKeyMappingsToPreset:(NSString*)presetName inBookmark:(NSMutableDictionary*)bookmark
{
    NSMutableDictionary* km = [NSMutableDictionary dictionaryWithDictionary:[bookmark objectForKey:KEY_KEYBOARD_MAP]];
    
    [km removeAllObjects];
    
    NSString* plistFile = [[NSBundle bundleForClass: [self class]] pathForResource:@"PresetKeyMappings" ofType:@"plist"];   
    NSDictionary* presetsDict = [NSDictionary dictionaryWithContentsOfFile: plistFile];
    NSDictionary* settings = [presetsDict objectForKey:presetName];
    [km setDictionary:settings];
    
    [bookmark setObject:km forKey:KEY_KEYBOARD_MAP];
}


+ (void)setMappingAtIndex:(int)rowIndex 
                   forKey:(NSString*)keyString 
                   action:(int)actionIndex 
                    value:(NSString*)valueToSend 
                createNew:(BOOL)newMapping 
               inBookmark:(NSMutableDictionary*)bookmark
{
    NSString* origKeyCombo = nil;

    NSMutableDictionary* km = 
        [NSMutableDictionary dictionaryWithDictionary:[bookmark objectForKey:KEY_KEYBOARD_MAP]];
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

+ (int)numberOfMappingsForBookmark:(Bookmark*)bmDict
{
    NSDictionary* keyMapDict = [bmDict objectForKey:KEY_KEYBOARD_MAP];
    return [keyMapDict count];
}

@end

