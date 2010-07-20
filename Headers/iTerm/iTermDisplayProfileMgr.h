/*
 **  iTermDisplayProfileMgr.h
 **
 **  Copyright (c) 2002, 2003, 2004
 **
 **  Author: Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: Header file for display profile manager.
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

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <Tree.h>

#define TYPE_ANSI_0_COLOR				0
#define TYPE_ANSI_1_COLOR				1
#define TYPE_ANSI_2_COLOR				2
#define TYPE_ANSI_3_COLOR				3
#define TYPE_ANSI_4_COLOR				4
#define TYPE_ANSI_5_COLOR				5
#define TYPE_ANSI_6_COLOR				6
#define TYPE_ANSI_7_COLOR				7
#define TYPE_ANSI_8_COLOR				8
#define TYPE_ANSI_9_COLOR				9
#define TYPE_ANSI_10_COLOR				10
#define TYPE_ANSI_11_COLOR				11
#define TYPE_ANSI_12_COLOR				12
#define TYPE_ANSI_13_COLOR				13
#define TYPE_ANSI_14_COLOR				14
#define TYPE_ANSI_15_COLOR				15
#define TYPE_FOREGROUND_COLOR			16
#define TYPE_BACKGROUND_COLOR			17
#define TYPE_BOLD_COLOR					18
#define TYPE_SELECTION_COLOR			19
#define TYPE_SELECTED_TEXT_COLOR		20
#define TYPE_CURSOR_COLOR				21
#define TYPE_CURSOR_TEXT_COLOR			22

@interface iTermDisplayProfileMgr : NSObject 
{
	NSMutableDictionary *profiles;
}

// Class methods
+ (id) singleInstance;

// Instance methods
- (id) init;
- (void) dealloc;

- (NSMutableDictionary *) profiles;
- (void) setProfiles: (NSMutableDictionary *) aDict;
- (void) addProfileWithName: (NSString *) newProfile copyProfile: (NSString *) sourceProfile;
- (void) deleteProfileWithName: (NSString *) profileName;
- (BOOL) isDefaultProfile: (NSString *) profileName;
- (NSString *) defaultProfileName;


- (NSColor *) color: (int) type forProfile: (NSString *) profileName;
- (void) setColor: (NSColor *) aColor forType: (int) type forProfile: (NSString *) profileName;

- (float) transparencyForProfile: (NSString *) profileName;
- (void) setTransparency: (float) transparency forProfile: (NSString *) profileName;

- (NSString *) COLORFGBGForProfile: (NSString *) profileName;

- (NSString *) backgroundImageForProfile: (NSString *) profileName;
- (void) setBackgroundImage: (NSString *) imagePath forProfile: (NSString *) profileName;

- (BOOL) disableBoldForProfile: (NSString *) profileName;
- (void) setDisableBold: (BOOL) bFlag forProfile: (NSString *) profileName;

- (int) windowColumnsForProfile: (NSString *) profileName;
- (void) setWindowColumns: (int) columns forProfile: (NSString *) profileName;
- (int) windowRowsForProfile: (NSString *) profileName;
- (void) setWindowRows: (int) rows forProfile: (NSString *) profileName;
- (NSFont *) windowFontForProfile: (NSString *) profileName;
- (void) setWindowFont: (NSFont *) font forProfile: (NSString *) profileName;
- (NSFont *) windowNAFontForProfile: (NSString *) profileName;
- (void) setWindowNAFont: (NSFont *) font forProfile: (NSString *) profileName;
- (float) windowHorizontalCharSpacingForProfile: (NSString *) profileName;
- (void) setWindowHorizontalCharSpacing: (float) spacing forProfile: (NSString *) profileName;
- (float) windowVerticalCharSpacingForProfile: (NSString *) profileName;
- (void) setWindowVerticalCharSpacing: (float) spacing forProfile: (NSString *) profileName;
- (BOOL) windowAntiAliasForProfile: (NSString *) profileName;
- (void) setWindowAntiAlias: (BOOL) antiAlias forProfile: (NSString *) profileName;
- (BOOL) windowBlurForProfile: (NSString *) profileName;
- (void) setWindowBlur: (BOOL) blur forProfile: (NSString *) profileName;

- (void) updateBookmarkNode: (TreeNode *)node forProfile: (NSString*) oldProfile with:(NSString*)newProfile;
- (void) updateBookmarkProfile: (NSString*) oldProfile with:(NSString*)newProfile;

@end

@interface iTermDisplayProfileMgr (Private)

- (float) _floatValueForKey: (NSString *) key inProfile: (NSString *) profileName;
- (void) _setFloatValue: (float) fval forKey: (NSString *) key inProfile: (NSString *) profileName;
- (int) _intValueForKey: (NSString *) key inProfile: (NSString *) profileName;
- (void) _setIntValue: (int) ival forKey: (NSString *) key inProfile: (NSString *) profileName;

@end

