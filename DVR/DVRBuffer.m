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


@implementation DVRBuffer

- (id)initWithBufferCapacity:(long long)maxsize
{
    if ([super init] == nil) {
        return nil;
    }
    capacity_ = maxsize;
    store_ = malloc(maxsize);
    index_ = [[NSMutableDictionary alloc] init];
    firstKey_ = 0;
    nextKey_ = 0;
    begin_ = 0;
    end_ = 0;

    return self;
}

- (void)dealloc
{
    [index_ release];
    index_ = nil;
    free(store_);
    [super dealloc];
}

- (BOOL)reserve:(long long)length
{
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
    return hadToFree;
}

- (long long)allocateBlock:(long long)length
{
    assert([self hasSpaceAvailable:length]);
    DVRIndexEntry* entry = [[DVRIndexEntry alloc] init];
    entry->position = scratch_ - store_;
    end_ = entry->position + length;
    entry->frameLength = length;
    scratch_ = 0;

    long long key = nextKey_++;
    [index_ setObject:entry forKey:[NSNumber numberWithLongLong:key]];
    [entry release];

    return key;
}

- (void)deallocateBlock
{
    long long key = firstKey_++;
    DVRIndexEntry* entry = [self entryForKey:key];
    begin_ = entry->position + entry->frameLength;
    [index_ removeObjectForKey:[NSNumber numberWithLongLong:key]];
}

- (void*)blockForKey:(long long)key
{
    DVRIndexEntry* entry = [self entryForKey:key];
    assert(entry);
    return store_ + entry->position;
}

- (BOOL)hasSpaceAvailable:(long long)length
{
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
    return firstKey_;
}

- (long long)lastKey
{
    return nextKey_ - 1;
}

- (DVRIndexEntry*)entryForKey:(long long)key
{
    assert(index_);
    return [index_ objectForKey:[NSNumber numberWithLongLong:key]];
}

- (char*)scratch
{
    return scratch_;
}

- (long long)capacity
{
    return capacity_;
}

- (BOOL)isEmpty
{
    return [index_ count] == 0;
}


@end
