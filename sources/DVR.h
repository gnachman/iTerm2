// -*- mode:objc -*-
/*
 **  DVR.h
 **
 **  Copyright 2010
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

// Get timestamp of first/last frame. Times are in microseconds since 1970.
@property(nonatomic, readonly) long long lastTimeStamp;
@property(nonatomic, readonly) long long firstTimeStamp;
@property(nonatomic, readonly) BOOL readOnly;
@property(nonatomic, readonly) BOOL empty;
@property(nonatomic, readonly) NSDictionary *dictionaryValue;

// Allocates a circular buffer of the given size in bytes to store screen
// contents. Somewhat more memory is used because there's some per-frame
// storage, but it should be small in comparison.
- (instancetype)initWithBufferCapacity:(int)bytes;
- (BOOL)loadDictionary:(NSDictionary *)dict;

// Save the screen state into the DVR.
//   frameLines: An array of screen lines that DVREncoder understands.
//   length: Number of bytes in buffer.
//   info: Metadata for the frame.
- (void)appendFrame:(NSArray*)frameLines length:(int)length info:(DVRFrameInfo*)info;

// allocate a new decoder. Use -[releaseDecoder:] when you're done with it.
- (DVRDecoder*)getDecoder;

// frees a decoder allocated with -[getDecoder].
- (void)releaseDecoder:(DVRDecoder*)decoder;

@end
