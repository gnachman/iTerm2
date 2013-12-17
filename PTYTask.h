// -*- mode:objc -*-
// $Id: PTYTask.h,v 1.14 2008-10-24 05:25:58 yfabian Exp $
/*
 **  PTYTask.h
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **      Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: Implements the interface to the pty session.
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

extern NSString *kCoprocessStatusChangeNotification;

// Silence a few warnings.
@class PTYTab;
@class Coprocess;

@protocol PTYTaskDelegate <NSObject>
- (void)readTask:(NSData *)data;
- (void)brokenPipe;
@end

@interface PTYTask : NSObject
{
    pid_t pid;
    int fd;
    int status;
    id<PTYTaskDelegate> delegate;
    NSString* tty;
    NSString* path;
    BOOL hasOutput;

    NSLock* writeLock;  // protects writeBuffer
    NSMutableData* writeBuffer;

    NSString* logPath;
    NSFileHandle* logHandle;

    Coprocess *coprocess_;  // synchronized (self)
    BOOL brokenPipe_;
	NSString *command_;  // Command that was run if launchWithPath:arguments:etc was called
}

- (id)init;
- (void)dealloc;
- (BOOL)hasBrokenPipe;
- (NSString *)command;
- (void)launchWithPath:(NSString*)progpath
             arguments:(NSArray*)args
           environment:(NSDictionary*)env
                 width:(int)width
                height:(int)height
                isUTF8:(BOOL)isUTF8;

- (NSString*)currentJob:(BOOL)forceRefresh;

- (void)setDelegate:(id<PTYTaskDelegate>)object;
- (id<PTYTaskDelegate>)delegate;
- (void)readTask:(NSData*)data;
- (void)writeTask:(NSData*)data;

- (void)sendSignal:(int)signo;
- (void)setWidth:(int)width height:(int)height;
- (void)stop;

- (int)fd;
- (pid_t)pid;
- (int)status;
- (NSString*)tty;
- (NSString*)path;
- (NSString*)getWorkingDirectory;
- (NSString*)description;

- (BOOL)loggingStartWithPath:(NSString*)path;
- (void)loggingStop;
- (BOOL)logging;
- (BOOL)hasOutput;

- (BOOL)wantsRead;
- (BOOL)wantsWrite;
- (void)brokenPipe;
- (void)processRead;
- (void)processWrite;

- (void)setCoprocess:(Coprocess *)coprocess;
- (Coprocess *)coprocess;
- (BOOL)writeBufferHasRoom;
- (BOOL)hasCoprocess;
- (BOOL)hasMuteCoprocess;
- (void)stopCoprocess;

// If session logging is on, append data to it. Only needed if PTYTask is not doing the reading, as
// is the case for tmux.
- (void)logData:(NSData *)data;


@end

