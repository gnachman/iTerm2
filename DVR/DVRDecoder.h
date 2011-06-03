// -*- mode:objc -*-
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
#import "DVR/DVRBuffer.h"

@interface DVRDecoder : NSObject
{
    // Circular buffer not owned by us.
    DVRBuffer* buffer_;

    // Most recent frame's metadata.
    DVRFrameInfo info_;

    // Most recent frame.
    char* frame_;

    // Length of frame.
    int length_;

    // Most recent frame's key (not timestamp).
    long long key_;
}

- (id)initWithBuffer:(DVRBuffer*)buffer;
- (void)dealloc;

// Jump to a given timestamp, or the next available frame. Returns true on success.
// Returns false if timestamp is later than the last timestamp or there are no frames.
- (BOOL)seek:(long long)timestamp;

// Accessors for the most recent frame.
- (char*)decodedFrame;
- (int)length;
- (long long)timestamp;
- (DVRFrameInfo)info;

// Advance to next frame.
- (BOOL)next;

// Advance to previous frame.
- (BOOL)prev;

// Called when frame index key i is freed.
- (void)invalidateIndex:(long long)i;

@end

@interface DVRDecoder (Private)

// Seek directly to a particular key.
- (void)_seekToEntryWithKey:(long long)key;

// Load a key or diff frame from a particular key.
- (void)_loadKeyFrameWithKey:(long long)key;
- (void)_loadDiffFrameWithKey:(long long)key;

@end
