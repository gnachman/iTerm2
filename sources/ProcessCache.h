// -*- mode:objc -*-
/*
 **  ProcessCache.m
 **
 **  Copyright (c) 2011
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Keeps an ancestorPid->foregroundJobName map and refreshes it
 **               in a separate thread.
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

extern NSString *PID_INFO_IS_FOREGROUND;
extern NSString *PID_INFO_NAME;

@interface ProcessCache : NSObject

+ (ProcessCache*)sharedInstance;
+ (NSArray *)allPids;

- (NSSet *)childrenOfPid:(pid_t)thePid levelsToSkip:(int)skip;
- (NSString*)getNameOfPid:(pid_t)thePid isForeground:(BOOL*)isForeground;
- (NSDictionary *)dictionaryOfTaskInfoForPid:(pid_t)thePid;

// Get the name of the foreground job owned by pid.
- (NSString*)jobNameWithPid:(int)pid;
- (void)notifyNewOutput;

@end
