// -*- mode:objc -*-
/*
 **  DVR.h
 **
 **  Copyright 20101
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Implements a "digital video recorder" for iTerm2.
 **    This is used by the "instant replay" feature to record and
 **    play back the screen contents.
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
#import "DVRDecoder.h"
#import "DVREncoder.h"

@interface DVR : NSObject
{
    DVRBuffer* buffer_;
    int capacity_;
    NSMutableArray* decoders_;
    DVREncoder* encoder_;
}

// Allocates a circular buffer of the given size in bytes to store screen
// contents. Somewhat more memory is used because there's some per-frame
// storage, but it should be small in comparison.
- (id)initWithBufferCapacity:(int)bytes;
- (void)dealloc;

// Save the screen state into the DVR.
//   buffer: A screen image that DVREncoder understands.
//   length: Number of bytes in buffer.
//   info: Metadata for the frame.
- (void)appendFrame:(char*)buffer length:(int)length info:(DVRFrameInfo*)info;

// allocate a new decoder. Use -[releaseDecoder:] when you're done with it.
- (DVRDecoder*)getDecoder;

// frees a decoder allocated with -[getDecoder].
- (void)releaseDecoder:(DVRDecoder*)decoder;

// Get timestamp of first/last frame. Times are in microseconds since 1970.
- (long long)lastTimeStamp;
- (long long)firstTimeStamp;

@end
