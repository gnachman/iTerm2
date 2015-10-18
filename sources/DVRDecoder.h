/*
 **  DVRDecoder.h
 **
 **  Copyright 20101
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Decodes the key+diff frame scheme implemented in
 **    DVREncoder. Used by the instant replay feature to load screen
 **    images out of a circular DVRBuffer owned by a DVR.
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
#import "DVRBuffer.h"

@interface DVRDecoder : NSObject

@property(nonatomic, readonly) long long timestamp;

- (instancetype)initWithBuffer:(DVRBuffer*)buffer;

// Jump to a given timestamp, or the next available frame. Returns true on success.
// Returns false if timestamp is later than the last timestamp or there are no frames.
- (BOOL)seek:(long long)timestamp;

// Accessors for the most recent frame.
- (char*)decodedFrame;
- (int)length;
- (DVRFrameInfo)info;

// Advance to next frame.
- (BOOL)next;

// Advance to previous frame.
- (BOOL)prev;

// Called when frame index key i is freed.
- (void)invalidateIndex:(long long)i;

@end

