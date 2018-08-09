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
#import "NSDictionary+iTerm.h"

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
}

- (instancetype)initWithBufferCapacity:(long long)maxsize
{
    self = [super init];
    if (self) {
        capacity_ = maxsize;
        store_ = malloc(maxsize);
        index_ = [[NSMutableDictionary alloc] init];
        firstKey_ = 0;
        nextKey_ = 0;
        begin_ = 0;
        end_ = 0;
    }
    return self;
}

- (void)dealloc
{
    [index_ release];
    index_ = nil;
    free(store_);
    [super dealloc];
}

- (NSDictionary *)exportedIndex {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (NSNumber *key in index_) {
        DVRIndexEntry *entry = index_[key];
        dict[key] = entry.dictionaryValue;
    }
    return dict;
}

- (NSDictionary *)dictionaryValue {
    NSDictionary *dict =
        @{ @"store": [NSData dataWithBytes:store_ length:capacity_],
           @"scratchOffset": scratch_ ? @(scratch_ - store_) : [NSNull null],
           @"index": [self exportedIndex],
           @"firstKey": @(firstKey_),
           @"nextKey": @(nextKey_),
           @"begin": @(begin_),
           @"end": @(end_) };
    return [dict dictionaryByRemovingNullValues];
}

- (BOOL)loadFromDictionary:(NSDictionary *)dict {
    NSData *store = dict[@"store"];
    if (store.length != capacity_) {
        return NO;
    }
    memmove(store_, store.bytes, store.length);

    id scratch = dict[@"scratchOffset"];
    if ([scratch isKindOfClass:[NSNull class]]) {
        scratch_ = nil;
    } else {
        scratch_ = store_ + [scratch integerValue];
    }

    NSDictionary *indexDict = dict[@"index"];
    for (NSNumber *key in indexDict) {
        NSDictionary *value = indexDict[key];
        DVRIndexEntry *entry = [DVRIndexEntry entryFromDictionaryValue:value];
        if (!entry) {
            return NO;
        }
        index_[key] = entry;
    }

    firstKey_ = [dict[@"firstKey"] longLongValue];
    nextKey_ = [dict[@"nextKey"] longLongValue];
    begin_ = [dict[@"begin"] longLongValue];
    end_ = [dict[@"end"] longLongValue];
    return YES;
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
