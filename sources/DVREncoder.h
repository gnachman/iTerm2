/*
 **  DVREncoder.h
 **
 **  Copyright 20101
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Encodes screen images into a DVRBuffer. Implements
 **    a basic key-frame + differential encoding scheme.
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

@interface DVREncoder : NSObject

- (instancetype)initWithBuffer:(DVRBuffer*)buffer;

// Encoded a frame into the DVRBuffer. Call -[reserve:] first.
//   frameLines: An array of screen lines
//   length: number of bytes (not elements) in buffer.
//   info: screen state.
- (void)appendFrame:(NSArray *)frameLines length:(int)length info:(DVRFrameInfo*)info;

// Allocate some number of bytes for an upcoming appendFrame call.
// Returns true if some frames were freed to make room. The caller should
// invalidate nonexistent leading frames in all decoders.
- (BOOL)reserve:(int)length;

@end
