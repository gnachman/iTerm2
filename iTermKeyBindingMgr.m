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

#import "ITAddressBookMgr.h"
#import <iTerm/iTermKeyBindingMgr.h>

@implementation iTermKeyBindingMgr

+ (NSString *) formatKeyCombination:(NSString *)theKeyCombination  
{
    unsigned int keyMods;
    unsigned int keyCode;
    NSString *aString;
    NSMutableString *theKeyString;
    keyCode = keyMods = 0;
	sscanf([theKeyCombination UTF8String], "%x-%x", &keyCode, &keyMods);
	
	switch (keyCode) {
		case NSDownArrowFunctionKey:
			aString = NSLocalizedStringFromTableInBundle(@"cursor down",@"iTerm", 
														 [NSBundle bundleForClass: [self class]], 
														 @"Key Names");
			break;
		case NSLeftArrowFunctionKey:
			aString = NSLocalizedStringFromTableInBundle(@"cursor left",@"iTerm", 
														 [NSBundle bundleForClass: [self class]], 
														 @"Key Names");
			break;
		case NSRightArrowFunctionKey:
			aString = NSLocalizedStringFromTableInBundle(@"cursor right",@"iTerm", 
														 [NSBundle bundleForClass: [self class]], 
														 @"Key Names");
			break;
		case NSUpArrowFunctionKey:
			aString = NSLocalizedStringFromTableInBundle(@"cursor up",@"iTerm", 
														 [NSBundle bundleForClass: [self class]], 
														 @"Key Names");
			break;
		case NSDeleteFunctionKey:
			aString = NSLocalizedStringFromTableInBundle(@"del",@"iTerm", 
														 [NSBundle bundleForClass: [self class]], 
														 @"Key Names");
			break;
		case 0x7f:
			aString = NSLocalizedStringFromTableInBundle(@"delete",@"iTerm", 
														 [NSBundle bundleForClass: [self class]], 
														 @"Key Names");
			break;
		case NSEndFunctionKey:
			aString = NSLocalizedStringFromTableInBundle(@"end",@"iTerm", 
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
			aString = NSLocalizedStringFromTableInBundle(@"help",@"iTerm", 
														 [NSBundle bundleForClass: [self class]], 
														 @"Key Names");	
			break;
		case NSHomeFunctionKey:
			aString = NSLocalizedStringFromTableInBundle(@"home",@"iTerm", 
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
			aString = NSLocalizedStringFromTableInBundle(@"numlock",@"iTerm", 
														 [NSBundle bundleForClass: [self class]], 
														 @"Key Names");
			break;
		case NSPageDownFunctionKey:
			aString = NSLocalizedStringFromTableInBundle(@"page down",@"iTerm", 
														 [NSBundle bundleForClass: [self class]], 
														 @"Key Names");
			break;
		case NSPageUpFunctionKey:
			aString = NSLocalizedStringFromTableInBundle(@"page up",@"iTerm", 
														 [NSBundle bundleForClass: [self class]], 
														 @"Key Names");
			break;
		case 0x3: // 'enter' on numeric key pad
			aString = NSLocalizedStringFromTableInBundle(@"enter",@"iTerm", 
														 [NSBundle bundleForClass: [self class]], 
														 @"Key Names");
			break;
		case NSInsertCharFunctionKey:
			aString = NSLocalizedStringFromTableInBundle(@"insert",@"iTerm", 
														 [NSBundle bundleForClass: [self class]], 
														 @"Key Names");
			break;
			
		default:
            if (keyCode >= '!' && keyCode <= '~') {
                aString = [NSString stringWithFormat:@"%c", keyCode];
            } else {
                aString = [NSString stringWithFormat: @"%@ 0x%x", 
                           NSLocalizedStringFromTableInBundle(@"hex code",@"iTerm", 
                                                              [NSBundle bundleForClass: [self class]], 
                                                              @"Key Names"),
                           keyCode];
            }
			break;
	}
	
	theKeyString = [[NSMutableString alloc] initWithString: @""];
	if (keyMods & NSCommandKeyMask) {
		[theKeyString appendString: @"cmd-"];
	}		
	if (keyMods & NSAlternateKeyMask) {
		[theKeyString appendString: @"opt-"];
	}
	if (keyMods & NSControlKeyMask) {
		[theKeyString appendString: @"ctrl-"];
	}
	if (keyMods & NSShiftKeyMask) {
		[theKeyString appendString: @"shift-"];
	}
	if (keyMods & NSNumericPadKeyMask) {
		[theKeyString appendString: @"num-"];
	}		
	[theKeyString appendString: aString];
    return theKeyString;
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

+ (int) actionForKeyCode: (unichar)keyCode 
               modifiers: (unsigned int) keyMods 
            highPriority: (BOOL *) highPriority 
                    text: (NSString **) text 
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

