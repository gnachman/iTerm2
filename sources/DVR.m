#warning TODO: DVR should show historic status bar info
// -*- mode:objc -*-
/*
 **  DVR.m
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

#import "DVR.h"
#import "DVRIndexEntry.h"
#import "NSData+iTerm.h"
#include <sys/time.h>

@implementation DVR {
    DVRBuffer* buffer_;
    int capacity_;
    NSMutableArray* decoders_;
    DVREncoder* encoder_;
}

@synthesize readOnly = readOnly_;

- (instancetype)initWithBufferCapacity:(int)bytes {
    self = [super init];
    if (self) {
        buffer_ = [DVRBuffer alloc];
        [buffer_ initWithBufferCapacity:bytes];
        capacity_ = bytes;
        decoders_ = [[NSMutableArray alloc] init];
        encoder_ = [DVREncoder alloc];
        [encoder_ initWithBuffer:buffer_];
    }
    return self;
}

- (void)dealloc
{
    [decoders_ release];
    [encoder_ release];
    [buffer_ release];
    [super dealloc];
}

- (void)appendFrame:(NSArray*)frameLines length:(int)length info:(DVRFrameInfo*)info
{
    if (readOnly_) {
        return;
    }
    if (length > [buffer_ capacity] / 2) {
        // Protect the buffer from overflowing if you have a really big window.
        return;
    }
    _empty = NO;
    int prevFirst = [buffer_ firstKey];
    if ([encoder_ reserve:length]) {
        // Leading frames were freed. Invalidate them in all decoders.
        for (DVRDecoder* decoder in decoders_) {
            int newFirst = [buffer_ firstKey];
            for (int i = prevFirst; i < newFirst; ++i) {
                [decoder invalidateIndex:i];
            }
        }
    }
    [encoder_ appendFrame:frameLines length:length info:info];
}

- (DVRDecoder*)getDecoder
{
    DVRDecoder* decoder = [[DVRDecoder alloc] initWithBuffer:buffer_];
    [decoders_ addObject:decoder];
    [decoder release];
    return decoder;
}

- (void)releaseDecoder:(DVRDecoder*)decoder
{
    [decoders_ removeObject:decoder];
}

- (long long)lastTimeStamp
{
    DVRIndexEntry* entry = [buffer_ entryForKey:[buffer_ lastKey]];
    if (!entry) {
        return 0;
    }
    return entry->info.timestamp;
}

- (long long)firstTimeStamp
{
    DVRIndexEntry* entry = [buffer_ entryForKey:[buffer_ firstKey]];
    if (!entry) {
        return 0;
    }
    return entry->info.timestamp;
}

- (NSDictionary *)dictionaryValue {
    return @{ @"version": @1,
              @"capacity": @(capacity_),
              @"buffer": buffer_.dictionaryValue };
}

- (BOOL)loadDictionary:(NSDictionary *)dict {
    if (!dict) {
        return NO;
    }
    if ([dict[@"version"] integerValue] != 1) {
        return NO;
    }
    int capacity = [dict[@"capacity"] intValue];
    if (capacity == 0) {
        return NO;
    }
    NSDictionary *bufferDict = dict[@"buffer"];
    if (!bufferDict) {
        return NO;
    }

    [buffer_ release];
    buffer_ = [DVRBuffer alloc];
    [buffer_ initWithBufferCapacity:capacity];
    capacity_ = capacity;

    [decoders_ release];
    decoders_ = [[NSMutableArray alloc] init];

    [encoder_ release];
    encoder_ = [DVREncoder alloc];
    [encoder_ initWithBuffer:buffer_];

    if (![buffer_ loadFromDictionary:bufferDict]) {
        return NO;
    }
    readOnly_ = YES;
    return YES;
}

@end

