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

static iTermKeyBindingMgr *singleInstance = nil;

@implementation iTermKeyBindingMgr

+ (id) singleInstance;
{
	if(singleInstance == nil)
	{
		singleInstance = [[iTermKeyBindingMgr alloc] init];
	}
	
	return (singleInstance);
}

- (id) init
{
	self = [super init];
	
	if(!self)
		return (nil);
	
	profiles = [[NSMutableDictionary alloc] init];

	return (self);
}

- (void) dealloc
{
	[profiles release];
	[super dealloc];
}

- (NSDictionary *) profiles
{
	return (profiles);
}

- (void) setProfiles: (NSMutableDictionary *) aDict
{
	NSEnumerator *keyEnumerator;
	NSMutableDictionary *mappingDict, *aMutableDict;
	NSString *profileName;
	NSDictionary *sourceDict;
	BOOL foundGlobalProfile = NO;

	// recursively copy the dictionary to ensure mutability
	if(aDict != nil)
	{
		keyEnumerator = [aDict keyEnumerator];
		while((profileName = [keyEnumerator nextObject]) != nil)
		{
			sourceDict = [aDict objectForKey: profileName];
			mappingDict = [[NSMutableDictionary alloc] initWithDictionary: sourceDict];
			// make sure key mapping dict is mutable
			if([sourceDict objectForKey: @"Key Mappings"] != nil)
			{
				aMutableDict = [[NSMutableDictionary alloc] initWithDictionary: [sourceDict objectForKey: @"Key Mappings"]];
				[mappingDict setObject: aMutableDict forKey: @"Key Mappings"];
				[aMutableDict release];
			}
			[profiles setObject: mappingDict forKey: profileName];
			[mappingDict release];
			if([[sourceDict objectForKey: @"Global Profile"] isEqualToString: @"Yes"])
				foundGlobalProfile = YES;
		}
	}
	
	if(foundGlobalProfile == NO)
	{
		mappingDict = [[NSMutableDictionary alloc] init];
		[mappingDict setObject: @"Yes" forKey: @"Global Profile"];
		[profiles setObject: mappingDict forKey: NSLocalizedStringFromTableInBundle(@"Global",@"iTerm", 
																					[NSBundle bundleForClass: [self class]], 
																					@"Key Binding Profiles")];
		[mappingDict release];
	}
}

- (BOOL) isGlobalProfile: (NSString *)profileName
{
	NSDictionary *aProfile;
	
	if([profileName length] <= 0)
		return (NO);
	
	aProfile = [profiles objectForKey: profileName];
	return ([[aProfile objectForKey: @"Global Profile"] isEqualToString: @"Yes"]);
}

- (void) addProfileWithName: (NSString *) aString copyProfile: (NSString *) profileName
{
	//NSLog(@"%s: %@", __PRETTY_FUNCTION__, aString);
	if([aString length] > 0 && [profiles objectForKey: aString] == nil)
	{
		NSMutableDictionary *newProfile, *sourceProfile, *mappingDict;
				
		if([profileName length] > 0)
		{
			sourceProfile = [profiles objectForKey: profileName];
			newProfile = [[NSMutableDictionary alloc] initWithDictionary: sourceProfile];				

			// make sure key mapping dict is mutable
			if([sourceProfile objectForKey: @"Key Mappings"] != nil)
			{
				mappingDict = [[NSMutableDictionary alloc] initWithDictionary: [sourceProfile objectForKey: @"Key Mappings"]];
				[newProfile setObject: mappingDict forKey: @"Key Mappings"];
				[mappingDict release];
			}
			[newProfile removeObjectForKey: @"Global Profile"];
		}	
		else
		{
			newProfile = [[NSMutableDictionary alloc] init];				
		}
		
		[profiles setObject: newProfile forKey: aString];
		[newProfile release];		
	}
	else
		NSBeep();
}

- (void) deleteProfileWithName: (NSString *) aString
{
	if([aString length] > 0)
	{
		[self updateBookmarkProfile: aString with:@"Default"];
		[profiles removeObjectForKey: aString];
	}
}

- (int) numberOfEntriesInProfile: (NSString *) profileName
{
	NSDictionary *keyMappings;
	
	//NSLog(@"%s: %@", __PRETTY_FUNCTION__, profileName);
	
	if([profileName length] > 0)
	{
		keyMappings = [[profiles objectForKey: profileName] objectForKey: @"Key Mappings"];
		return ([keyMappings count]);
	}
	else
		return (0);
}

- (NSString *) keyCombinationAtIndex: (int) index inProfile: (NSString *) profile
{
	NSMutableDictionary *keyMappings;
	NSArray *allKeys;
	NSString *theKeyCombination, *aString;
	NSMutableString *theKeyString;
	unsigned int keyCode, keyModifiers;
	
	//NSLog(@"%s: %@", __PRETTY_FUNCTION__, profile);
	
	keyMappings = [[profiles objectForKey: profile] objectForKey: @"Key Mappings"];
	allKeys = [[keyMappings allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
	
	if(index >= 0 && index < [allKeys count])
	{
		theKeyCombination = [allKeys objectAtIndex: index];
	}
	else
		return (nil);
	
	keyCode = keyModifiers = 0;
	sscanf([theKeyCombination UTF8String], "%x-%x", &keyCode, &keyModifiers);
	
	switch (keyCode)
	{
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
			aString = [NSString stringWithFormat: @"%@ 0x%x", 
				NSLocalizedStringFromTableInBundle(@"hex code",@"iTerm", 
														 [NSBundle bundleForClass: [self class]], 
														 @"Key Names"),
				keyCode];
			break;
	}
	
	theKeyString = [[NSMutableString alloc] initWithString: @""];
	if(keyModifiers & NSCommandKeyMask)
	{
		[theKeyString appendString: @"cmd-"];
	}		
	if(keyModifiers & NSAlternateKeyMask)
	{
		[theKeyString appendString: @"opt-"];
	}
	if(keyModifiers & NSControlKeyMask)
	{
		[theKeyString appendString: @"ctrl-"];
	}
	if(keyModifiers & NSShiftKeyMask)
	{
		[theKeyString appendString: @"shift-"];
	}
	if(keyModifiers & NSNumericPadKeyMask)
	{
		[theKeyString appendString: @"num-"];
	}		
	[theKeyString appendString: aString];
	
	return ([theKeyString autorelease]);
	
	
}

- (NSString *) actionForKeyCombinationAtIndex: (int) index inProfile: (NSString *) profile
{
	NSMutableDictionary *keyMappings;
	NSArray *allKeys;
	int action;
	NSString *actionString;
	NSString *auxText;
	BOOL priority;
	
	//NSLog(@"%s: %@", __PRETTY_FUNCTION__, profile);
	
	keyMappings = [[profiles objectForKey: profile] objectForKey: @"Key Mappings"];
	allKeys = [[keyMappings allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
	
	if(index >= 0 && index < [allKeys count])
	{
		action = [[[keyMappings objectForKey: [allKeys objectAtIndex: index]] objectForKey: @"Action"] intValue];
		auxText = [[keyMappings objectForKey: [allKeys objectAtIndex: index]] objectForKey: @"Text"];
		priority = [[keyMappings objectForKey: [allKeys objectAtIndex: index]] objectForKey: @"Priority"] ? [[[keyMappings objectForKey: [allKeys objectAtIndex: index]] objectForKey: @"Priority"] boolValue] : NO;
	}
	else
		return (nil);
	
	switch (action)
	{
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


- (void) addEntryForKeyCode: (unsigned int) hexCode 
				  modifiers: (unsigned int) modifiers
					 action: (unsigned int) action
			   highPriority: (BOOL) highPriority
					   text: (NSString *) text
					profile: (NSString *) profile
{
	//NSLog(@"%s", __PRETTY_FUNCTION__);
	
	NSMutableDictionary *keyMappings, *keyBinding;
	NSString *keyString;
	
	if([profile length] <= 0)
		return;
	
	keyMappings = [[profiles objectForKey: profile] objectForKey: @"Key Mappings"];
	if(keyMappings == nil)
	{
		keyMappings = [[NSMutableDictionary alloc] init];
		[[profiles objectForKey: profile] setObject: keyMappings forKey: @"Key Mappings"];
		[keyMappings release];
	}
	
	keyString = [NSString stringWithFormat: @"0x%x-0x%x", hexCode, modifiers];
	keyBinding = [[NSMutableDictionary alloc] init];
	[keyBinding setObject: [NSNumber numberWithInt: action] forKey: @"Action"];
	if([text length] > 0)
		[keyBinding setObject:[[text copy] autorelease] forKey: @"Text"];
	[keyBinding setObject: [NSNumber numberWithBool:highPriority] forKey: @"Priority"];
	[keyMappings setObject: keyBinding forKey: keyString];
	[keyBinding release];
	
}

- (void) addEntryForKey: (unsigned int) key 
			  modifiers: (unsigned int) modifiers
				 action: (unsigned int) action
		   highPriority: (BOOL) highPriority
				   text: (NSString *) text
				profile: (NSString *) profile
{
	//NSLog(@"%s", __PRETTY_FUNCTION__);
	
	unsigned int keyModifiers;
	unichar keyUnicode;
	
	keyModifiers = modifiers;
	
	// this is how we distinguish between regular numbers and those on the numeric keypad
	if(key >= KEY_NUMERIC_0 && key <= KEY_NUMERIC_PERIOD)
		keyModifiers |= NSNumericPadKeyMask;
	
	// on some keyboards, arrow keys have NSNumericPadKeyMask bit set; manually set it for keyboards that don't
	if(key >= KEY_CURSOR_DOWN && key <= KEY_CURSOR_UP)
		keyModifiers |= NSNumericPadKeyMask;
	
	switch (key)
	{
		case KEY_CURSOR_DOWN:
			keyUnicode = NSDownArrowFunctionKey;
			break;
		case KEY_CURSOR_LEFT:
			keyUnicode = NSLeftArrowFunctionKey;
			break;
		case KEY_CURSOR_RIGHT:
			keyUnicode = NSRightArrowFunctionKey;
			break;
		case KEY_CURSOR_UP:
			keyUnicode = NSUpArrowFunctionKey;
			break;
		case KEY_DEL:
			keyUnicode = NSDeleteFunctionKey;
			break;
		case KEY_DELETE:
			keyUnicode = 0x7f;
			break;
		case KEY_END:
			keyUnicode = NSEndFunctionKey;
			break;
		case KEY_F1:
		case KEY_F2:
		case KEY_F3:
		case KEY_F4:
		case KEY_F5:
		case KEY_F6:
		case KEY_F7:
		case KEY_F8:
		case KEY_F9:
		case KEY_F10:
		case KEY_F11:
		case KEY_F12:
		case KEY_F13:
		case KEY_F14:
		case KEY_F15:
		case KEY_F16:
		case KEY_F17:
		case KEY_F18:
		case KEY_F19:
		case KEY_F20:
			keyUnicode = NSF1FunctionKey + (key - KEY_F1);
			break;
		case KEY_HELP:
			keyUnicode = NSHelpFunctionKey;
			break;			
		case KEY_HOME:
			keyUnicode = NSHomeFunctionKey;
			break;
		case KEY_NUMERIC_0:
		case KEY_NUMERIC_1:
		case KEY_NUMERIC_2:
		case KEY_NUMERIC_3:
		case KEY_NUMERIC_4:
		case KEY_NUMERIC_5:
		case KEY_NUMERIC_6:
		case KEY_NUMERIC_7:
		case KEY_NUMERIC_8:
		case KEY_NUMERIC_9:
			keyUnicode = '0' + (key - KEY_NUMERIC_0);
			break;
		case KEY_NUMERIC_ENTER:
			keyUnicode = 0x3; // 'enter' on numeric keypad
			break;
		case KEY_NUMERIC_EQUAL:
			keyUnicode = '=';
			break;
		case KEY_NUMERIC_DIVIDE:
			keyUnicode = '/';
			break;
		case KEY_NUMERIC_MULTIPLY:
			keyUnicode = '*';
			break;
		case KEY_NUMERIC_MINUS:
			keyUnicode = '-';
			break;
		case KEY_NUMERIC_PLUS:
			keyUnicode = '+';
			break;
		case KEY_NUMERIC_PERIOD:
			keyUnicode = '.';
			break;
		case KEY_NUMLOCK:
			keyUnicode = NSClearLineFunctionKey;
			break;
		case KEY_PAGE_DOWN:
			keyUnicode = NSPageDownFunctionKey;
			break;
		case KEY_PAGE_UP:
			keyUnicode = NSPageUpFunctionKey;
			break;
		case KEY_INS:
			keyUnicode = NSInsertCharFunctionKey;
			break;
		default:
			NSLog(@"%s: unknown key %d", __PRETTY_FUNCTION__, key);
			return;
	}
	
	[self addEntryForKeyCode: keyUnicode modifiers: keyModifiers action: action highPriority: highPriority text: text profile: profile];
		
}

- (void) deleteEntryAtIndex: (int) index inProfile: (NSString *) profile
{
	NSMutableDictionary *keyMappings;
	NSArray *allKeys;
	NSString *keyString;
	
	keyMappings = [[profiles objectForKey: profile] objectForKey: @"Key Mappings"];
	allKeys = [[keyMappings allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];

	if(index >= 0 && index < [allKeys count])
	{
		keyString = [allKeys objectAtIndex: index];
		[keyMappings removeObjectForKey: keyString];
	}
}

- (int) optionKeyForProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	
	if([profileName length] > 0)
		aProfile = [profiles objectForKey: profileName];
	else
		aProfile = [self globalProfile];
	return ([[aProfile objectForKey: @"Option Key"] intValue]);
}

- (void) setOptionKey: (int) option forProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	
	//NSLog(@"%s: profile = %@; option = %d", __PRETTY_FUNCTION__, profileName, option);
	aProfile = [profiles objectForKey: profileName];
	[aProfile setObject: [NSNumber numberWithInt: option] forKey: @"Option Key"];
}

- (NSDictionary *) globalProfile
{
	NSString *globalProfile;
	
	globalProfile = NSLocalizedStringFromTableInBundle(@"Global",@"iTerm", [NSBundle bundleForClass: [self class]], @"Key Binding Profiles");

	return ([profiles objectForKey: globalProfile]);
}

- (NSString *) globalProfileName
{
	NSDictionary *aProfile;
	NSEnumerator *keyEnumerator;
	NSString *aKey, *aProfileName;
	
	keyEnumerator = [profiles keyEnumerator];
	aProfileName = nil;
	while ((aKey = [keyEnumerator nextObject]))
	{
		aProfile = [profiles objectForKey: aKey];
		if([self isGlobalProfile: aKey])
		{
			aProfileName = aKey;
			break;
		}
	}
	
	return (aProfileName);
}

- (NSString *) defaultProfileName
{
	return [self globalProfileName];
}

- (int) actionForKeyCode: (unichar)keyCode modifiers: (unsigned int) keyModifiers highPriority: (BOOL *) highPriority text: (NSString **) text profile: (NSString *)profile
{
	int retCode = -1;
	NSString *globalProfile;
			
	// search the specified profile first
	if([profile length] > 0)
		retCode = [self _actionForKeyCode: keyCode modifiers: keyModifiers highPriority: highPriority text: text profile: profile];
	
	// If we found something in the common profile, return that
	if(retCode >= 0)
		return (retCode);
	
	globalProfile = NSLocalizedStringFromTableInBundle(@"Global",@"iTerm", [NSBundle bundleForClass: [self class]], @"Key Binding Profiles");
	
	// search the common profile if a match was not found
	if([globalProfile length] > 0)
		retCode = [self _actionForKeyCode: keyCode modifiers: keyModifiers highPriority: highPriority text: text profile: globalProfile];	
	
	
	return (retCode);
}

- (void) updateBookmarkNode: (TreeNode *)node forProfile: (NSString*) oldProfile with:(NSString*)newProfile
{
	int i;
	TreeNode *child;
	NSDictionary *aDict;
	int n = [node numberOfChildren];
	
	for (i=0;i<n;i++) {
		child = [node childAtIndex:i];
		if ([child isLeaf]) {
			aDict = [child nodeData];
			if ([[aDict objectForKey:KEY_KEYBOARD_PROFILE] isEqualToString: oldProfile]) {
				NSMutableDictionary *newBookmark= [[NSMutableDictionary alloc] initWithDictionary: aDict];
				[newBookmark setObject: newProfile forKey: KEY_KEYBOARD_PROFILE];
				[child setNodeData: newBookmark];
				[newBookmark release];
			}
		}
		else {
			[self updateBookmarkNode: child forProfile: oldProfile with:newProfile];
		}
	}
}

- (void) updateBookmarkProfile: (NSString*) oldProfile with:(NSString*)newProfile
{
	[self updateBookmarkNode: [[ITAddressBookMgr sharedInstance] rootNode] forProfile: oldProfile with:newProfile];
	
	// Post a notification for all listeners that bookmarks have changed
	[[NSNotificationCenter defaultCenter] postNotificationName: @"iTermReloadAddressBook" object: nil userInfo: nil];    		
}

@end

@implementation iTermKeyBindingMgr (Private)
- (int) _actionForKeyCode: (unichar)keyCode modifiers: (unsigned int) keyModifiers highPriority: (BOOL *) highPriority text: (NSString **) text profile: (NSString *)profile
{
	NSDictionary *keyMappings;
	NSString *keyString;
	NSDictionary *theKeyMapping;
	int retCode = -1;
	unsigned int theModifiers;
	
	if(profile == nil)
	{
		if(text)
			*text = nil;
		return (-1);
	}
	
	keyMappings = [[profiles objectForKey: profile] objectForKey: @"Key Mappings"];
	
	if(keyMappings == nil)
	{
		if(text)
			*text = nil;
		return (-1);
	}
	
	// turn off all the other modifier bits we don't care about
	theModifiers = keyModifiers & (NSAlternateKeyMask | NSControlKeyMask | NSShiftKeyMask | NSCommandKeyMask | NSNumericPadKeyMask);
	
	// on some keyboards, arrow keys have NSNumericPadKeyMask bit set; manually set it for keyboards that don't
	if(keyCode >= NSUpArrowFunctionKey && keyCode <= NSRightArrowFunctionKey)
		theModifiers |= NSNumericPadKeyMask;
	
	keyString = [NSString stringWithFormat: @"0x%x-0x%x", keyCode, theModifiers];
	theKeyMapping = [keyMappings objectForKey: keyString];
	if(theKeyMapping == nil)
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
@end
