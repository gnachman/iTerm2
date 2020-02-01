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

#import "DebugLogging.h"
#import "DVRIndexEntry.h"
#import "iTermMalloc.h"
#import "LineBuffer.h"

//#if DEBUG
//#define DVRDEBUG 1
//#endif

@implementation DVRDecoder {
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

- (instancetype)initWithBuffer:(DVRBuffer *)buffer {
    self = [super init];
    if (self) {
        buffer_ = buffer;
        frame_ = 0;
        length_ = 0;
        key_ = -1;
    }
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

#pragma mark - Private

- (NSString *)stringForFrame
{
    NSMutableString *s = [NSMutableString string];
    screen_char_t *lines = (screen_char_t *)frame_;
    int i = 0;
    for (int y = 0; y < info_.height; y++) {
        for (int x = 0; x < info_.width; x++) {
            screen_char_t c = lines[i++];
            [s appendFormat:@"%c", c.code];
        }
        [s appendString:@"\n"];
        i++;
    }
    return s;
}

- (void)debug:(NSString*)prefix buffer:(char*)buffer length:(int)length
{
    NSMutableData *temp = [NSMutableData dataWithLength:length];
    char *d = (char *)temp.mutableBytes;
    int i;
    for (i = 0; i * sizeof(screen_char_t) < length; i++) {
        screen_char_t s = ((screen_char_t*)buffer)[i];
        if (s.code && s.complexChar) {
            d[i] = s.code;
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
        if (![self _loadDiffFrameWithKey:j]) {
            return;
        }
#ifdef DVRDEBUG
        [self debug:[NSString stringWithFormat:@"After applying diff of %lld:", j] buffer:frame_ length:length_];
#endif
    }
    key_ = j;
#ifdef DVRDEBUG
    NSLog(@"end seek to %lld", key);
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
#ifdef DVRDEBUG
    NSLog(@"Frame length is %d", length_);
#endif
    if (!frame_) {
        frame_ = iTermMalloc(length_);
    }
    char* data = [buffer_ blockForKey:key];
    info_ = entry->info;
    DLog(@"Frame with key %lld has size %dx%d", key, info_.width, info_.height);
    memcpy(frame_,  data, length_);
}

// Add two positive ints. Returns NO if it can't be done. Returns YES and places the result in
// *sum if possible.
static BOOL NS_WARN_UNUSED_RESULT SafeIncr(int summand, int addend, int *sum) {
    if (summand < 0 || addend < 0) {
        DLog(@"Have negative value: summand=%@ addend=%@", @(summand), @(addend));
        return NO;
    }
    assert(sizeof(long long) > sizeof(int));
    const long long temp1 = summand;
    const long long temp2 = addend;
    const long long temp3 = temp1 + temp2;
    if (temp3 > INT_MAX) {
        DLog(@"Prevented overflow: summand=%@ addend=%@", @(summand), @(addend));
        return NO;
    }
    *sum = temp3;
    return YES;
}

// Returns NO if the input was broken.
- (BOOL)_loadDiffFrameWithKey:(long long)key
{
#ifdef DVRDEBUG
    NSLog(@"Load diff frame with key %lld", key);
#endif
    DVRIndexEntry* entry = [buffer_ entryForKey:key];
    info_ = entry->info;
    char* diff = [buffer_ blockForKey:key];
    int o = 0;
    for (int i = 0; i < entry->frameLength; ) {
#ifdef DVRDEBUG
        NSLog(@"Checking line at offset %d, address %p. type=%d", i, diff+i, (int)diff[i]);
#endif
        int n;
        switch (diff[i++]) {
            case kSameSequence:
                memcpy(&n, diff + i, sizeof(n));
                if (!SafeIncr(i, sizeof(n), &i)) {
                    return NO;
                }
#ifdef DVRDEBUG
                NSLog(@"%d bytes of sameness at offset %d", n, i);
#endif
                if (!SafeIncr(n, o, &o)) {
                    return NO;
                }
                // Don't advance i because there's nothing saved in the buffer
                // at this location since it's a SameSequence.
                break;

            case kDiffSequence:
                memcpy(&n, diff + i, sizeof(n));
                if (!SafeIncr(i, sizeof(n), &i)) {
                    return NO;
                }
                int proposedEnd;
                if (!SafeIncr(o, n, &proposedEnd)) {
                    return NO;
                }
                if (proposedEnd -1 >= length_) {
                    return NO;
                }
                memcpy(frame_ + o, diff + i, n);
#ifdef DVRDEBUG
                NSLog(@"%d bytes of difference at offset %d", n, o);
#endif
                if (!SafeIncr(n, o, &o) || !SafeIncr(n, i, &i)) {
                    return NO;
                }
                break;

            default:
                NSLog(@"Unexpected block type %d", (int)diff[i-1]);
                assert(0);
        }
    }
    return YES;
}

@end

