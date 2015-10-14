// -*- mode:objc -*-
/*
 **  DVRBuffer.m
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

#import "DVRBuffer.h"


@implementation DVRBuffer {
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
    
    // this must always equal index_.
    id sanityCheck;  // TODO(georgen): remove this after the source of corruption of index_ is found
}

- (instancetype)initWithBufferCapacity:(long long)maxsize
{
    self = [super init];
    if (self) {
        capacity_ = maxsize;
        store_ = malloc(maxsize);
        index_ = [[NSMutableDictionary alloc] init];
        sanityCheck = index_;
        firstKey_ = 0;
        nextKey_ = 0;
        begin_ = 0;
        end_ = 0;
    }
    return self;
}

- (void)dealloc
{
    assert(index_ == sanityCheck);
    [index_ release];
    index_ = nil;
    sanityCheck = nil;
    free(store_);
    [super dealloc];
}

- (BOOL)reserve:(long long)length
{
    assert(index_ == sanityCheck);
    BOOL hadToFree = NO;
    while (![self hasSpaceAvailable:length]) {
        assert(nextKey_ > firstKey_);
        [self deallocateBlock];
        hadToFree = YES;
    }
    if (begin_ <= end_) {
        if (capacity_ - end_ >= length) {
            scratch_ = store_ + end_;
        } else {
            scratch_ = store_;
        }
    } else {
        scratch_ = store_ + end_;
    }
    assert(index_ == sanityCheck);
    return hadToFree;
}

- (long long)allocateBlock:(long long)length
{
    assert(index_ == sanityCheck);
    assert([self hasSpaceAvailable:length]);
    DVRIndexEntry* entry = [[DVRIndexEntry alloc] init];
    entry->position = scratch_ - store_;
    end_ = entry->position + length;
    entry->frameLength = length;
    scratch_ = 0;

    long long key = nextKey_++;
    [index_ setObject:entry forKey:[NSNumber numberWithLongLong:key]];
    [entry release];
    assert(index_ == sanityCheck);

    return key;
}

- (void)deallocateBlock
{
    assert(index_ == sanityCheck);
    long long key = firstKey_++;
    DVRIndexEntry* entry = [self entryForKey:key];
    begin_ = entry->position + entry->frameLength;
    [index_ removeObjectForKey:[NSNumber numberWithLongLong:key]];
    assert(index_ == sanityCheck);
}

- (void*)blockForKey:(long long)key
{
    assert(index_ == sanityCheck);
    DVRIndexEntry* entry = [self entryForKey:key];
    assert(entry);
    assert(index_ == sanityCheck);
    return store_ + entry->position;
}

- (BOOL)hasSpaceAvailable:(long long)length
{
    assert(index_ == sanityCheck);
    if (begin_ <= end_) {
        // ---begin*******end-----
        if (capacity_ - end_ > length) {
            return YES;
        } else if (begin_ > length) {
            return YES;
        } else {
            return NO;
        }
    } else {
        // ***end----begin****
        if (begin_ - end_ > length) {
            return YES;
        } else {
            return NO;
        }
    }
}

- (long long)firstKey
{
    assert(index_ == sanityCheck);
    return firstKey_;
}

- (long long)lastKey
{
    assert(index_ == sanityCheck);
    return nextKey_ - 1;
}

- (DVRIndexEntry*)entryForKey:(long long)key
{
    assert(index_ == sanityCheck);
    assert(index_);
    return [index_ objectForKey:[NSNumber numberWithLongLong:key]];
}

- (char*)scratch
{
    assert(index_ == sanityCheck);
    return scratch_;
}

- (long long)capacity
{
    assert(index_ == sanityCheck);
    return capacity_;
}

- (BOOL)isEmpty
{
    assert(index_ == sanityCheck);
    return [index_ count] == 0;
}


@end
