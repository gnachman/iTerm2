/*
 **  iTermDisplayProfileMgr.m
 **
 **  Copyright (c) 2002, 2003, 2004
 **
 **  Author: Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: implements the display profile manager.
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
#import <iTerm/iTermDisplayProfileMgr.h>

static iTermDisplayProfileMgr *singleInstance = nil;


@implementation iTermDisplayProfileMgr

+ (id) singleInstance
{
	if(singleInstance == nil)
	{
		singleInstance = [[iTermDisplayProfileMgr alloc] init];
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

- (NSMutableDictionary *) profiles
{
	return (profiles);
}

- (void) setProfiles: (NSMutableDictionary *) aDict
{
	NSEnumerator *keyEnumerator;
	NSMutableDictionary *mappingDict;
	NSString *profileName;
	NSDictionary *sourceDict;
	
	// recursively copy the dictionary to ensure mutability
	if(aDict != nil)
	{
		keyEnumerator = [aDict keyEnumerator];
		while((profileName = [keyEnumerator nextObject]) != nil)
		{
			sourceDict = [aDict objectForKey: profileName];
			mappingDict = [[NSMutableDictionary alloc] initWithDictionary: sourceDict];
			[profiles setObject: mappingDict forKey: profileName];
			[mappingDict release];
		}
	}
    else  // if we don't have any profile, create a default profile
    {
		NSMutableDictionary *aProfile;
		NSString *defaultName;
		
		defaultName = NSLocalizedStringFromTableInBundle(@"Default",@"iTerm", [NSBundle bundleForClass: [self class]],
														 @"Display Profiles");
		
		
		aProfile = [[NSMutableDictionary alloc] init];
		[profiles setObject: aProfile forKey: defaultName];
		[aProfile release];
		
		[aProfile setObject: @"Yes" forKey: @"Default Profile"];
		
		[self setColor: [NSColor textColor] forType: TYPE_FOREGROUND_COLOR forProfile: defaultName];
		[self setColor: [NSColor textBackgroundColor] forType: TYPE_BACKGROUND_COLOR forProfile: defaultName];
		[self setColor: [NSColor redColor] forType: TYPE_BOLD_COLOR forProfile: defaultName];
		[self setColor: [NSColor selectedTextBackgroundColor] forType: TYPE_SELECTION_COLOR forProfile: defaultName];
		[self setColor: [NSColor selectedTextColor] forType: TYPE_SELECTED_TEXT_COLOR forProfile: defaultName];
		[self setColor: [NSColor textColor] forType: TYPE_CURSOR_COLOR forProfile: defaultName];
		[self setColor: [NSColor textBackgroundColor] forType: TYPE_CURSOR_TEXT_COLOR forProfile: defaultName];

		[self setColor: [NSColor blackColor] forType: TYPE_ANSI_0_COLOR forProfile: defaultName];
		[self setColor: [NSColor redColor] forType: TYPE_ANSI_1_COLOR forProfile: defaultName];
		[self setColor: [NSColor greenColor] forType: TYPE_ANSI_2_COLOR forProfile: defaultName];
		[self setColor: [NSColor yellowColor] forType: TYPE_ANSI_3_COLOR forProfile: defaultName];
		[self setColor: [NSColor blueColor] forType: TYPE_ANSI_4_COLOR forProfile: defaultName];
		[self setColor: [NSColor magentaColor] forType: TYPE_ANSI_5_COLOR forProfile: defaultName];
		[self setColor: [NSColor cyanColor] forType: TYPE_ANSI_6_COLOR forProfile: defaultName];
		[self setColor: [NSColor whiteColor] forType: TYPE_ANSI_7_COLOR forProfile: defaultName];
		[self setColor: [[NSColor blackColor] highlightWithLevel: 0.5] 
			   forType: TYPE_ANSI_8_COLOR forProfile: defaultName];
		[self setColor: [[NSColor redColor] highlightWithLevel: 0.5] 
			   forType: TYPE_ANSI_9_COLOR forProfile: defaultName];
		[self setColor: [[NSColor greenColor] highlightWithLevel: 0.5] 
			   forType: TYPE_ANSI_10_COLOR forProfile: defaultName];
		[self setColor: [[NSColor yellowColor] highlightWithLevel: 0.5] 
			   forType: TYPE_ANSI_11_COLOR forProfile: defaultName];
		[self setColor: [[NSColor blueColor] highlightWithLevel: 0.5] 
			   forType: TYPE_ANSI_12_COLOR forProfile: defaultName];
		[self setColor: [[NSColor magentaColor] highlightWithLevel: 0.5]
			   forType: TYPE_ANSI_13_COLOR forProfile: defaultName];
		[self setColor: [[NSColor cyanColor] highlightWithLevel: 0.5] 
			   forType: TYPE_ANSI_14_COLOR forProfile: defaultName];
		[self setColor: [[NSColor whiteColor] highlightWithLevel: 0.5]
			   forType: TYPE_ANSI_15_COLOR forProfile: defaultName];
		
		[self setWindowColumns: 80 forProfile: defaultName];
		[self setWindowRows: 24 forProfile: defaultName];
		[self setWindowAntiAlias: YES forProfile: defaultName];
		[self setWindowBlur: NO forProfile: defaultName];
		[self setWindowHorizontalCharSpacing: 1.0 forProfile: defaultName];
		[self setWindowVerticalCharSpacing: 1.0 forProfile: defaultName];
						
	}
}

- (NSString *) defaultProfileName
{
	NSDictionary *aProfile;
	NSEnumerator *keyEnumerator;
	NSString *aKey, *aProfileName;
	
	keyEnumerator = [profiles keyEnumerator];
	aProfileName = nil;
	while ((aKey = [keyEnumerator nextObject]))
	{
		aProfile = [profiles objectForKey: aKey];
		if([self isDefaultProfile: aKey])
		{
			aProfileName = aKey;
			break;
		}
	}
	
	return (aProfileName);
}


- (void) addProfileWithName: (NSString *) newProfile copyProfile: (NSString *) sourceProfile
{
	NSMutableDictionary *aMutableDict, *aProfile;
	
	if([sourceProfile length] > 0 && [newProfile length] > 0)
	{
		aProfile = [profiles objectForKey: sourceProfile];
		aMutableDict = [[NSMutableDictionary alloc] initWithDictionary: aProfile];
		[aMutableDict removeObjectForKey: @"Default Profile"];
		[profiles setObject: aMutableDict forKey: newProfile];
		[aMutableDict release];
	}
}

- (void) deleteProfileWithName: (NSString *) profileName
{
	
	if([profileName length] <= 0)
		return;
	
	[self updateBookmarkProfile: profileName with:@"Default"];
	[profiles removeObjectForKey: profileName];
}

- (BOOL) isDefaultProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	
	if([profileName length] <= 0)
		return (NO);
	
	aProfile = [profiles objectForKey: profileName];
	
	return ([[aProfile objectForKey: @"Default Profile"] isEqualToString: @"Yes"]);
}


- (NSColor *) color: (int) type forProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	NSDictionary *colorDict;
	NSColor *aColor;
	
	if([profileName length] <= 0)
		return (nil);
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return (nil);
	
	switch (type)
	{
		case TYPE_ANSI_0_COLOR:
		case TYPE_ANSI_1_COLOR:
		case TYPE_ANSI_2_COLOR:
		case TYPE_ANSI_3_COLOR:
		case TYPE_ANSI_4_COLOR:
		case TYPE_ANSI_5_COLOR:
		case TYPE_ANSI_6_COLOR:
		case TYPE_ANSI_7_COLOR:
		case TYPE_ANSI_8_COLOR:
		case TYPE_ANSI_9_COLOR:
		case TYPE_ANSI_10_COLOR:
		case TYPE_ANSI_11_COLOR:
		case TYPE_ANSI_12_COLOR:
		case TYPE_ANSI_13_COLOR:
		case TYPE_ANSI_14_COLOR:
		case TYPE_ANSI_15_COLOR:
			colorDict = [aProfile objectForKey: [NSString stringWithFormat: @"Ansi %d Color", type]];
			break;
		case TYPE_FOREGROUND_COLOR:
			colorDict = [aProfile objectForKey: @"Foreground Color"];
			break;
		case TYPE_BACKGROUND_COLOR:
			colorDict = [aProfile objectForKey: @"Background Color"];
			break;
		case TYPE_BOLD_COLOR:
			colorDict = [aProfile objectForKey: @"Bold Color"];
			break;
		case TYPE_SELECTION_COLOR:
			colorDict = [aProfile objectForKey: @"Selection Color"];
			break;
		case TYPE_SELECTED_TEXT_COLOR:
			colorDict = [aProfile objectForKey: @"Selected Text Color"];
			break;
		case TYPE_CURSOR_COLOR:
			colorDict = [aProfile objectForKey: @"Cursor Color"];
			break;
		case TYPE_CURSOR_TEXT_COLOR:
			colorDict = [aProfile objectForKey: @"Cursor Text Color"];
			break;
		default:
			colorDict = nil;
			break;
	}
	
	if(colorDict != nil)
	{
		float red, green, blue;
		NSNumber *aNumber;
		
		red = green = blue = 0;
		
		aNumber = [colorDict objectForKey: @"Red Component"];
		if(aNumber != nil)
			red = [aNumber floatValue];
		aNumber = [colorDict objectForKey: @"Green Component"];
		if(aNumber != nil)
			green = [aNumber floatValue];
		aNumber = [colorDict objectForKey: @"Blue Component"];
		if(aNumber != nil)
			blue = [aNumber floatValue];
		
		aColor = [NSColor colorWithCalibratedRed: red green: green blue: blue alpha: 1.0];
	}
	else
		aColor = [NSColor blackColor];
	
	return (aColor);
}

- (void) setColor: (NSColor *) aColor forType: (int) type forProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	NSString *key = nil;

	if(aColor == nil)
		return;
	
	if([profileName length] <= 0)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	switch (type)
	{
		case TYPE_ANSI_0_COLOR:
		case TYPE_ANSI_1_COLOR:
		case TYPE_ANSI_2_COLOR:
		case TYPE_ANSI_3_COLOR:
		case TYPE_ANSI_4_COLOR:
		case TYPE_ANSI_5_COLOR:
		case TYPE_ANSI_6_COLOR:
		case TYPE_ANSI_7_COLOR:
		case TYPE_ANSI_8_COLOR:
		case TYPE_ANSI_9_COLOR:
		case TYPE_ANSI_10_COLOR:
		case TYPE_ANSI_11_COLOR:
		case TYPE_ANSI_12_COLOR:
		case TYPE_ANSI_13_COLOR:
		case TYPE_ANSI_14_COLOR:
		case TYPE_ANSI_15_COLOR:
			key = [NSString stringWithFormat: @"Ansi %d Color", type];
			break;
		case TYPE_FOREGROUND_COLOR:
			key =  @"Foreground Color";
			break;
		case TYPE_BACKGROUND_COLOR:
			key =  @"Background Color";
			break;
		case TYPE_BOLD_COLOR:
			key =  @"Bold Color";
			break;
		case TYPE_SELECTION_COLOR:
			key =  @"Selection Color";
			break;
		case TYPE_SELECTED_TEXT_COLOR:
			key =  @"Selected Text Color";
			break;
		case TYPE_CURSOR_COLOR:
			key =  @"Cursor Color";
			break;
		case TYPE_CURSOR_TEXT_COLOR:
			key =  @"Cursor Text Color";
			break;
		default:
			key = nil;
			break;
	}
	
	if(key != nil)
	{
		NSMutableDictionary *colorDict;
		NSColor *rgbColor;
		
		rgbColor = [aColor colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
		if(rgbColor == nil)
		{
			NSLog(@"%s: could not convert color to RGB color!", __PRETTY_FUNCTION__);
			return;
		}
		
		colorDict = [[NSMutableDictionary alloc] init];
		[colorDict setObject: [NSNumber numberWithFloat: [rgbColor redComponent]] forKey: @"Red Component"];
		[colorDict setObject: [NSNumber numberWithFloat: [rgbColor greenComponent]] forKey: @"Green Component"];
		[colorDict setObject: [NSNumber numberWithFloat: [rgbColor blueComponent]] forKey: @"Blue Component"];

		[aProfile setObject: colorDict forKey: key];
		[colorDict release];
	}
	
}

- (float) transparencyForProfile: (NSString *) profileName
{
	return ([self _floatValueForKey: @"Transparency" inProfile: profileName]);
}

- (void) setTransparency: (float) transparency forProfile: (NSString *) profileName
{
	[self _setFloatValue: transparency forKey: @"Transparency" inProfile: profileName];
}

- (NSString *) COLORFGBGForProfile: (NSString *) profileName
{
	if([profileName length] <= 0)
		return (nil);

	NSColor *fgColor;
	NSColor *bgColor;
	fgColor = [self color:TYPE_FOREGROUND_COLOR forProfile:profileName];
	bgColor = [self color:TYPE_BACKGROUND_COLOR forProfile:profileName];
	if(fgColor == nil || bgColor == nil)
		return (nil);

	int bgNum = -1;
	int fgNum = -1; 
	for(int i = TYPE_ANSI_0_COLOR; i <= TYPE_ANSI_15_COLOR; ++i) {
		if([fgColor isEqual: [self color:i forProfile:profileName]]) {
			fgNum = i;
		}
		if([bgColor isEqual: [self color:i forProfile:profileName]]) {
			bgNum = i;
		}
	}

	if(bgNum < 0 || fgNum < 0)
		return (nil);

	return ([[NSString alloc] initWithFormat:@"%d;%d", fgNum, bgNum]);
}

- (NSString *) backgroundImageForProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	
	if([profileName length] <= 0)
		return (nil);
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return (nil);
	
	return ([aProfile objectForKey: @"Background Image"]);
}

- (void) setBackgroundImage: (NSString *) imagePath forProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	
	if([profileName length] <= 0)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	if([imagePath length] > 0)
		[aProfile setObject: imagePath forKey: @"Background Image"];
	else
		[aProfile removeObjectForKey: @"Background Image"];
}

- (NSFont *) windowFontForProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	float fontSize;
	const char *utf8String;
	char utf8FontName[128];
	NSFont *aFont;
	
	if([profileName length] <= 0)
		return ([NSFont userFixedPitchFontOfSize: 0.0]);
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return ([NSFont userFixedPitchFontOfSize: 0.0]);
	
	if([aProfile objectForKey: @"Font"] == nil)
		return ([NSFont userFixedPitchFontOfSize: 0.0]);
	
	utf8String = [[aProfile objectForKey: @"Font"] UTF8String];
	sscanf(utf8String, "%s %g", utf8FontName, &fontSize);
	
	aFont = [NSFont fontWithName: [NSString stringWithFormat: @"%s", utf8FontName] size: fontSize];
	if (aFont == nil)
		return ([NSFont userFixedPitchFontOfSize: 0.0]);
	
	return (aFont);
}

- (void) setWindowFont: (NSFont *) font forProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	
	// NSLog(@"%s", __PRETTY_FUNCTION__);
	
	if([profileName length] <= 0 || font == nil)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	[aProfile setObject: [NSString stringWithFormat: @"%@ %g", [font fontName], [font pointSize]] forKey: @"Font"];
}

- (NSFont *) windowNAFontForProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	float fontSize;
	const char *utf8String;
	char utf8FontName[128];
	NSFont *aFont;
	
	if([profileName length] <= 0)
		return ([NSFont userFixedPitchFontOfSize: 0.0]);
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return ([NSFont userFixedPitchFontOfSize: 0.0]);
	
	if([aProfile objectForKey: @"NAFont"] == nil)
		return ([NSFont userFixedPitchFontOfSize: 0.0]);
	
	utf8String = [[aProfile objectForKey: @"NAFont"] UTF8String];
	sscanf(utf8String, "%s %g", utf8FontName, &fontSize);
	
	aFont = [NSFont fontWithName: [NSString stringWithFormat: @"%s", utf8FontName] size: fontSize];
	if (aFont == nil)
		return ([NSFont userFixedPitchFontOfSize: 0.0]);
	
	return (aFont);
}

- (void) setWindowNAFont: (NSFont *) font forProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	
	// NSLog(@"%s", __PRETTY_FUNCTION__);
	
	if([profileName length] <= 0 || font == nil)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	[aProfile setObject: [NSString stringWithFormat: @"%@ %g", [font fontName], [font pointSize]] forKey: @"NAFont"];
}

- (int) windowColumnsForProfile: (NSString *) profileName
{
	return ([self _intValueForKey: @"Columns" inProfile: profileName]);
}

- (void) setWindowColumns: (int) columns forProfile: (NSString *) profileName
{
	[self _setIntValue: columns forKey: @"Columns" inProfile: profileName];
}

- (int) windowRowsForProfile: (NSString *) profileName
{
	return ([self _intValueForKey: @"Rows" inProfile: profileName]);
}

- (void) setWindowRows: (int) rows forProfile: (NSString *) profileName
{
	[self _setIntValue: rows forKey: @"Rows" inProfile: profileName];
}

- (float) windowHorizontalCharSpacingForProfile: (NSString *) profileName
{
	return ([self _floatValueForKey: @"Horizontal Character Spacing" inProfile: profileName]);
}

- (void) setWindowHorizontalCharSpacing: (float) spacing forProfile: (NSString *) profileName
{
	[self _setFloatValue: spacing forKey: @"Horizontal Character Spacing" inProfile: profileName];
}

- (float) windowVerticalCharSpacingForProfile: (NSString *) profileName
{
	return ([self _floatValueForKey: @"Vertical Character Spacing" inProfile: profileName]);
}

- (void) setWindowVerticalCharSpacing: (float) spacing forProfile: (NSString *) profileName
{
	[self _setFloatValue: spacing forKey: @"Vertical Character Spacing" inProfile: profileName];
}

- (BOOL) windowAntiAliasForProfile: (NSString *) profileName
{
	return ([self _intValueForKey: @"Anti Alias" inProfile: profileName]);
}

- (void) setWindowAntiAlias: (BOOL) antiAlias forProfile: (NSString *) profileName
{
	[self _setIntValue: antiAlias forKey: @"Anti Alias" inProfile: profileName];
}

- (BOOL) windowBlurForProfile: (NSString *) profileName
{
	return ([self _intValueForKey: @"Blur" inProfile: profileName]);
}

- (void) setWindowBlur: (BOOL) blur forProfile: (NSString *) profileName
{
	[self _setIntValue: blur forKey: @"Blur" inProfile: profileName];
}

- (BOOL) disableBoldForProfile: (NSString *) profileName
{
	return ([self _intValueForKey: @"Disable Bold" inProfile: profileName]);
}

- (void) setDisableBold: (BOOL) bFlag forProfile: (NSString *) profileName
{
	[self _setIntValue: bFlag forKey: @"Disable Bold" inProfile: profileName];
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
			if ([[aDict objectForKey:KEY_DISPLAY_PROFILE] isEqualToString: oldProfile]) {
				NSMutableDictionary *newBookmark= [[NSMutableDictionary alloc] initWithDictionary: aDict];
				[newBookmark setObject: newProfile forKey: KEY_DISPLAY_PROFILE];
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


@implementation iTermDisplayProfileMgr (Private)

- (float) _floatValueForKey: (NSString *) key inProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	NSNumber *aNumber;
	
	if([profileName length] <= 0 || [key length] <= 0)
		return (0.0);
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return (0.0);
	
	aNumber  = [aProfile objectForKey: key];
	if(aNumber == nil)
		return (0.0);
	
	return ([aNumber floatValue]);
}

- (void) _setFloatValue: (float) fval forKey: (NSString *) key inProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	NSNumber *aNumber;
	
	if([profileName length] <= 0 || [key length] <= 0)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	aNumber = [NSNumber numberWithFloat: fval];
	
	[aProfile setObject: aNumber forKey: key];	
}

- (int) _intValueForKey: (NSString *) key inProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	NSNumber *aNumber;
	
	if([profileName length] <= 0 || [key length] <= 0)
		return (0);
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return (0);
	
	aNumber  = [aProfile objectForKey: key];
	if(aNumber == nil)
		return (0);
	
	return ([aNumber intValue]);	
}

- (void) _setIntValue: (int) ival forKey: (NSString *) key inProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	NSNumber *aNumber;
	
	if([profileName length] <= 0 || [key length] <= 0)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	aNumber = [NSNumber numberWithInt: ival];
	
	[aProfile setObject: aNumber forKey: key];	
}


@end
