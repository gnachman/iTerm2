// -*- mode:objc -*-
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
#import <DVRBuffer.h>

@interface DVREncoder : NSObject
{
    // Underlying buffer to write to. Not owned by us.
    DVRBuffer* buffer_;

    // The last encoded frame.
    NSMutableData* lastFrame_;

    // Info from the last frame.
    DVRFrameInfo lastInfo_;

    // Number of frames. Used to ensure key frames are encoded every so often.
    int count_;

    // Used to ensure that reserve is called before appendFrame.
    BOOL haveReservation_;

    // Used to ensure a key frame is encoded before the circular buffer wraps.
    long long bytesSinceLastKeyFrame_;

    // Number of bytes reserved.
    int reservation_;
}

- (id)initWithBuffer:(DVRBuffer*)buffer;
- (void)dealloc;

// Encoded a frame into the DVRBuffer. Call -[reserve:] first.
//   buffer: points to an array of screen_char_t described by info.
//   length: number of bytes (not elements) in buffer.
//   info: screen state.
- (void)appendFrame:(char*)buffer length:(int)length info:(DVRFrameInfo*)info;

// Allocate some number of bytes for an upcoming appendFrame call.
// Returns true if some frames were freed to make room. The caller should
// invalidate nonexistent leading frames in all decoders.
- (BOOL)reserve:(int)length;

@end

@interface DVREncoder (Private)
// Save a key frame into DVRBuffer.
- (void)_appendKeyFrame:(char*)buffer length:(int)length info:(DVRFrameInfo*)info;

// Save a diff frame into DVRBuffer.
- (void)_appendDiffFrame:(char*)buffer length:(int)length info:(DVRFrameInfo*)info;

// Save a frame into DVRBuffer.
- (void)_appendFrameImpl:(char*)buffer length:(int)length type:(DVRFrameType)type info:(DVRFrameInfo*)info;

// Calculate the diff between buffer,length and the previous frame. Saves results into
// scratch. Won't use more than maxSize bytes in scratch. Returns number of bytes used or
// -1 if the diff was larger than maxSize.
- (int)_computeDiff:(char*)buffer length:(int)length dest:(char*)scratch maxSize:(int)maxSize;

@end

