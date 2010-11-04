// -*- mode:objc -*-
/*
 **  DVRDecoder.m
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

#import "DVRDecoder.h"
#import "DVRIndexEntry.h"
#import "LineBuffer.h"

@implementation DVRDecoder

- (id)initWithBuffer:(DVRBuffer*)buffer
{
    if ([super init] == nil) {
        return nil;
    }
    buffer_ = buffer;
    frame_ = 0;
    length_ = 0;
    key_ = -1;
    return self;
}

- (void)dealloc
{
    if (frame_) {
        free(frame_);
    }
    [super dealloc];
}

- (BOOL)seek:(long long)timestamp
{
    // TODO(georgen): Do a binary search
    long long lastKey = [buffer_ lastKey];
    for (long long key = [buffer_ firstKey]; key <= lastKey; ++key) {
        DVRIndexEntry* entry = [buffer_ entryForKey:key];
        if (entry->info.timestamp >= timestamp) {
            [self _seekToEntryWithKey:key];
            return YES;
        }
    }
    return NO;
}

- (char*)decodedFrame
{
    return frame_;
}

- (int)length
{
    return length_;
}

- (BOOL)next
{
    long long newKey;
    if (key_ == -1) {
        newKey = [buffer_ firstKey];
    } else {
        newKey = key_ + 1;
        if (newKey < [buffer_ firstKey]) {
            newKey = [buffer_ firstKey];
        } else if (newKey > [buffer_ lastKey]) {
            return NO;
        }
    }
    [self _seekToEntryWithKey:newKey];
    return YES;
}

- (BOOL)prev
{
    if (key_ <= [buffer_ firstKey]) {
        return NO;
    }
    [self _seekToEntryWithKey:key_ - 1];
    return YES;
}

- (long long)timestamp
{
    return info_.timestamp;
}

- (void)invalidateIndex:(long long)i
{
    if (i == key_) {
        key_ = - 1;
    }
}

- (DVRFrameInfo)info
{
    return info_;
}

@end

@implementation DVRDecoder (Private)

- (void)debug:(NSString*)prefix buffer:(char*)buffer length:(int)length
{
    char d[30000];
    int i;
    for (i = 0; i * sizeof(screen_char_t) < length; i++) {
        screen_char_t s = ((screen_char_t*)buffer)[i];
        if (s.ch) {
            d[i] = s.ch;
        } else {
            d[i] = ' ';
        }
    }
    d[i] = 0;
    NSLog(@"%@: \"%s\"", prefix, d);
}


- (void)_seekToEntryWithKey:(long long)key
{
#ifdef DVRDEBUG
    NSLog(@"Begin seek to %lld", key);
#endif

    // Make sure key is valid.
    if (key < [buffer_ firstKey] || key > [buffer_ lastKey]) {
#ifdef DVRDEBUG
        NSLog(@"Frame %lld doesn't exist so skipping to %lld", key, [buffer_ firstKey]);
#endif
        key = [buffer_ firstKey];
    }
    // Find the key frame before 'key'.
    long long j = key;
    while ([buffer_ entryForKey:j]->info.frameType != DVRFrameTypeKeyFrame) {
        assert(j != [buffer_ firstKey]);
        --j;
    }

    [self _loadKeyFrameWithKey:j];

#ifdef DVRDEBUG
    [self debug:@"Key frame:" buffer:frame_ length:length_];
#endif

    // Apply all the diff frames up to key.
    while (j != key) {
        ++j;
        [self _loadDiffFrameWithKey:j];
#ifdef DVRDEBUG
        [self debug:[NSString stringWithFormat:@"After applying diff of %d:", j] buffer:frame_ length:length_];
#endif
    }
    key_ = j;
#ifdef DVRDEBUG
    NSLog(@"end seek to %d", i);
#endif
}

- (void)_loadKeyFrameWithKey:(long long)key
{
    DVRIndexEntry* entry = [buffer_ entryForKey:key];
    if (length_ != entry->frameLength && frame_) {
        free(frame_);
        frame_ = 0;
    }
    length_ = entry->frameLength;
    if (!frame_) {
        frame_ = malloc(length_);
    }
    char* data = [buffer_ blockForKey:key];
    info_ = entry->info;
    memcpy(frame_,  data, length_);
}

- (void)_loadDiffFrameWithKey:(long long)key
{
#ifdef DVRDEBUG
    NSLog(@"Load diff frame at index %d", theIndex);
#endif
    DVRIndexEntry* entry = [buffer_ entryForKey:key];
    info_ = entry->info;
    char* diff = [buffer_ blockForKey:key];
    int o = 0;
    for (int i = 0; i < entry->frameLength; ) {
        int n;
        switch (diff[i++]) {
            case kSameSequence:
                memcpy(&n, diff + i, sizeof(n));
                i += sizeof(n);
#ifdef DVRDEBUG
                [self debug:@"same seq" buffer:frame_ + o length:n];
#endif
                o += n;
                break;

            case kDiffSequence:
                memcpy(&n, diff + i, sizeof(n));
                i += sizeof(n);
                memcpy(frame_ + o, diff + i, n);
#ifdef DVRDEBUG
                [self debug:@"diff seq" buffer:frame_ + o length:n];
#endif
                o += n;
                i += n;
                break;

            default:
                NSLog(@"Unexpected block type %d", (int)diff[i]);
                assert(0);
        }
    }
}

@end

