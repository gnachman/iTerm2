/*
 **  iTermTerminalProfileMgr.h
 **
 **  Copyright (c) 2002, 2003, 2004
 **
 **  Author: Tianming Yang
 **
 **  Project: iTerm
 **
 **  Description: header file for terminal profile manager.
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
#import <Tree.h>

@interface iTermTerminalProfileMgr : NSObject {

	NSMutableDictionary *profiles;
}

// Class methods
+ (id) singleInstance;

	// Instance methods
- (id) init;
- (void) dealloc;

- (NSDictionary *) profiles;
- (void) setProfiles: (NSMutableDictionary *) aDict;
- (void) addProfileWithName: (NSString *) newProfile copyProfile: (NSString *) sourceProfile;
- (void) deleteProfileWithName: (NSString *) profileName;
- (BOOL) isDefaultProfile: (NSString *) profileName;
- (NSString *) defaultProfileName;


- (NSString *) typeForProfile: (NSString *) profileName;
- (void) setType: (NSString *) type forProfile: (NSString *) profileName;
- (NSStringEncoding) encodingForProfile: (NSString *) profileName;
- (void) setEncoding: (NSStringEncoding) encoding forProfile: (NSString *) profileName;
- (int) scrollbackLinesForProfile: (NSString *) profileName;
- (void) setScrollbackLines: (int) lines forProfile: (NSString *) profileName;
- (BOOL) silenceBellForProfile: (NSString *) profileName;
- (void) setSilenceBell: (BOOL) silent forProfile: (NSString *) profileName;
- (BOOL) showBellForProfile: (NSString *) profileName;
- (void) setShowBell: (BOOL) showBell forProfile: (NSString *) profileName;
- (BOOL) growlForProfile: (NSString *) profileName;
- (void) setGrowl: (BOOL) showGrowl forProfile: (NSString *) profileName;
- (BOOL) blinkCursorForProfile: (NSString *) profileName;
- (void) setBlinkCursor: (BOOL) blink forProfile: (NSString *) profileName;
- (BOOL) closeOnSessionEndForProfile: (NSString *) profileName;
- (void) setCloseOnSessionEnd: (BOOL) close forProfile: (NSString *) profileName;
- (BOOL) doubleWidthForProfile: (NSString *) profileName;
- (void) setDoubleWidth: (BOOL) doubleWidth forProfile: (NSString *) profileName;
- (BOOL) sendIdleCharForProfile: (NSString *) profileName;
- (void) setSendIdleChar: (BOOL) sent forProfile: (NSString *) profileName;
- (char) idleCharForProfile: (NSString *) profileName;
- (void) setIdleChar: (char) idle forProfile: (NSString *) profileName;
- (BOOL) xtermMouseReportingForProfile: (NSString *) profileName;
- (void) setXtermMouseReporting: (BOOL) xtermMouseReporting forProfile: (NSString *) profileName;
- (BOOL) appendTitleForProfile: (NSString *) profileName;
- (void) setAppendTitle: (BOOL) appendTitle forProfile: (NSString *) profileName;
- (BOOL) noResizingForProfile: (NSString *) profileName;
- (void) setNoResizing: (BOOL) noResizing forProfile: (NSString *) profileName;

- (void) updateBookmarkNode: (TreeNode *)node forProfile: (NSString*) oldProfile with:(NSString*)newProfile;
- (void) updateBookmarkProfile: (NSString*) oldProfile with:(NSString*)newProfile;

@end

@interface iTermTerminalProfileMgr (Private)

- (float) _floatValueForKey: (NSString *) key inProfile: (NSString *) profileName;
- (void) _setFloatValue: (float) fval forKey: (NSString *) key inProfile: (NSString *) profileName;
- (int) _intValueForKey: (NSString *) key inProfile: (NSString *) profileName;
- (void) _setIntValue: (int) ival forKey: (NSString *) key inProfile: (NSString *) profileName;

@end
