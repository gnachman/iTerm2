// -*- mode:objc -*-
/*
 **  DVRBuffer.h
 **
 **  Copyright 20101
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Implements a circular in-memory buffer for storing
 **    screen images plus some metadata associated with each frame.
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
#import "DVR/DVRIndexEntry.h"

// Sequences in a diff frame begin with one byte indicating the type of content
// that follows. The values come from this enum:
enum {
    kSameSequence,
    kDiffSequence
};

// Types of frames that DVREncoder and DVRDecoder use.
struct timeval;
typedef enum {
    DVRFrameTypeKeyFrame,
    DVRFrameTypeDiffFrame
} DVRFrameType;

@interface DVRBuffer : NSObject
{
@private
    // Points to start of large circular buffer.
    char* store_;

    // Points into store_ after -[reserve:] is called.
    char* scratch_;

    // Total size of storage in bytes.
    long long capacity_;

    // Maps a frame key number to DVRIndexEntry*.
    NSMutableDictionary* index_;

    // First key in index.
    long long firstKey_;

    // Next key number to add to index.
    long long nextKey_;

    // begin may be before or after end. If "-" is an allocated byte and "." is
    // a free byte then you can have one of two cases:
    //
    // begin------end.....
    // ----end....begin---

    // Beginning of circular buffer's used region.
    long long begin_;

    // Non-inclusive end of circular buffer's used regino.
    long long end_;
}

- (id)initWithBufferCapacity:(long long)capacity;
- (void)dealloc;

// Reserve a chunk of memory. Returns true if blocks had to be freed to make room.
// You can get a pointer to the reserved memory with -[scratch].
- (BOOL)reserve:(long long)length;
- (char*)scratch;

// Allocate a block. Returns the assigned key. You must have called -[reserve] first.
// length may less than reserved amount.
- (long long)allocateBlock:(long long)length;

// Free the first block.
- (void)deallocateBlock;

// Return a pointer to the memory for some key or null if it doesn't exist.
- (void*)blockForKey:(long long)key;

// Returns true if there's enough free space without deallocating a block.
- (BOOL)hasSpaceAvailable:(long long)length;

// Returns first/last used keys.
- (long long)firstKey;
- (long long)lastKey;

// Look up an index entry by key.
- (DVRIndexEntry*)entryForKey:(long long)key;

// Total size of storage.
- (long long)capacity;

// Are there no frames?
- (BOOL)isEmpty;
@end

