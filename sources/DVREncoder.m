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

#import "DVREncoder.h"
#import "DebugLogging.h"
#import "DVRIndexEntry.h"
#include "LineBuffer.h"
#include <sys/time.h>
//#define DVRDEBUG

// Returns a timestamp for the current time.
static long long now()
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    long long result = tv.tv_sec;
    result *= 1000000;
    result += tv.tv_usec;
    return result;
}

@interface DVREncoder ()
// Save a key frame into DVRBuffer.
- (void)_appendKeyFrame:(NSArray *)frameLines length:(int)length info:(DVRFrameInfo*)info;

// Save a diff frame into DVRBuffer.
- (void)_appendDiffFrame:(NSArray *)frameLine length:(int)length info:(DVRFrameInfo*)info;

// Save a frame into DVRBuffer.
- (void)_appendFrameImpl:(char *)buffer length:(int)length type:(DVRFrameType)type info:(DVRFrameInfo*)info;

// Calculate the diff between buffer,length and the previous frame. Saves results into
// scratch. Won't use more than maxSize bytes in scratch. Returns number of bytes used or
// -1 if the diff was larger than maxSize.
- (int)_computeDiff:(NSArray *)frameLines length:(int)length dest:(char*)scratch maxSize:(int)maxSize;

@end


@implementation DVREncoder {
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

- (instancetype)initWithBuffer:(DVRBuffer *)buffer {
    self = [super init];
    if (self) {
        buffer_ = [buffer retain];
        lastFrame_ = nil;
        count_ = 0;
        haveReservation_ = NO;
    }
    return self;
}

- (void)dealloc
{
    [lastFrame_ release];
    [buffer_ release];
    [super dealloc];
}

- (NSString *)stringForFrameLines:(NSArray *)lines width:(int)width height:(int)height
{
    NSMutableString *s = [NSMutableString string];
    for (int y = 0; y < height; y++) {
        screen_char_t *line = (screen_char_t*)[lines[y] mutableBytes];
        for (int x = 0; x < width; x++) {
            [s appendFormat:@"%c", line[x].code];
        }
        [s appendString:@"\n"];
    }
    return s;
}

- (void)appendFrame:(NSArray *)frameLines length:(int)length info:(DVRFrameInfo*)info
{
    BOOL eligibleForDiff;
    if (lastFrame_ &&
        length == [lastFrame_ length] &&
        info->width == lastInfo_.width &&
        info->height == lastInfo_.height &&
        bytesSinceLastKeyFrame_ < [buffer_ capacity] / 2) {
        eligibleForDiff = YES;
    } else {
        eligibleForDiff = NO;
    }

    const int kKeyFrameFrequency = 100;

    if (!eligibleForDiff || count_++ % kKeyFrameFrequency == 0) {
        [self _appendKeyFrame:frameLines length:length info:info];
    } else {
        [self _appendDiffFrame:frameLines length:length info:info];
    }
}

- (BOOL)reserve:(int)length
{
    haveReservation_ = YES;
    reservation_ = length;
    BOOL hadToFree = [buffer_ reserve:length];

    // Deallocate leading blocks until the first one is a key frame. If the first
    // block is a diff frame it's useless.
    while (![buffer_ isEmpty] && hadToFree) {
        DVRIndexEntry* entry = [buffer_ entryForKey:[buffer_ firstKey]];
        assert(entry);
        if (entry->info.frameType == DVRFrameTypeKeyFrame) {
            break;
        } else {
            [buffer_ deallocateBlock];
        }
    }
    return hadToFree;
}

#pragma mark - Private

- (void)debug:(NSString*)prefix buffer:(char*)buffer length:(int)length
{
#ifdef DVRDEBUG
    char d[30000];
    int i;
    for (i = 0; i * sizeof(screen_char_t) < length; i++) {
        screen_char_t s = ((screen_char_t*)buffer)[i];
        if (s.code && !s.complexChar) {
            d[i] = s.code;
        } else {
            d[i] = ' ';
        }
    }
    d[i] = 0;
    NSLog(@"%@ length %d: \"%s\"", prefix, length, d);
#endif
}

- (NSMutableData *)combinedFrameLines:(NSArray *)frameLines {
    NSMutableData *data = [[[NSMutableData alloc] init] autorelease];
    for (NSData *line in frameLines) {
        [data appendData:line];
    }
    return data;
}

- (void)_appendKeyFrame:(NSArray *)frameLines length:(int)length info:(DVRFrameInfo*)info
{
    [lastFrame_ release];
    lastFrame_ = [[self combinedFrameLines:frameLines] retain];
    assert(lastFrame_.length == length);
    char* scratch = [buffer_ scratch];
    memcpy(scratch, [lastFrame_ mutableBytes], length);
    [self _appendFrameImpl:scratch length:length type:DVRFrameTypeKeyFrame info:info];
    bytesSinceLastKeyFrame_ = 0;
}

- (void)_appendDiffFrame:(NSArray *)frameLines length:(int)length info:(DVRFrameInfo*)info
{
    char* scratch = [buffer_ scratch];
    int diffBytes = [self _computeDiff:frameLines
                                length:length
                                  dest:scratch
                               maxSize:reservation_];
    if (diffBytes < 0) {
        // Diff ended up being larger than a key frame would be.
        [self _appendKeyFrame:frameLines length:length info:info];
        return;
    }

#ifdef DVRDEBUG2
    int i;
    screen_char_t* s = scratch;
    for (i = 0; i < diffBytes; ++i) {
        NSLog(@"Offset %d: %d (%c)", i, (int)scratch[i], scratch[i]);
    }
#endif
    [self _appendFrameImpl:scratch length:diffBytes type:DVRFrameTypeDiffFrame info:info];
    bytesSinceLastKeyFrame_ += diffBytes;
}

- (void)_appendFrameImpl:(char*)dest length:(int)length type:(DVRFrameType)type info:(DVRFrameInfo*)info
{
    assert(haveReservation_);
    haveReservation_ = NO;

#ifdef DVRDEBUG
    NSLog(@"Append frame of type %d starting at %x length %d at index %d", (int)type, dest, length, [buffer_ lastKey]+1);
#endif

    lastInfo_ = *info;

    long long key = [buffer_ allocateBlock:length];
    DVRIndexEntry* entry = [buffer_ entryForKey:key];
    entry->info = *info;
    entry->info.timestamp = now();
    entry->info.frameType = type;
    DLog(@"Append frame with key %lld, size %dx%d", key, info->width, info->height);
}

- (int)_computeDiff:(NSArray *)frameLines length:(int)length dest:(char*)scratch maxSize:(int)maxBytes
{
    assert(length == [lastFrame_ length]);
    char* other = [lastFrame_ mutableBytes];
    assert(other);

    int o = 0;
    int sameCount = 0;
    int diffCount = 0;
    char* startDiff = 0;

    // TODO(georgen): Implement a better diff
    int numLines = [frameLines count];
    int i = 0;
    for (int y = 0; y < numLines; y++) {
        NSMutableData *lineData = [frameLines objectAtIndex:y];
        char *frameLine = [lineData mutableBytes];
        const int numChars = lineData.length;
        for (int x = 0; x < numChars; x++, i++) {
            // TODO: This should be a screen_char_t-wise comparison, not bytewise
            if (frameLine[x] == other[i]) {
                if (diffCount > 0) {
                    if (o + 1 + sizeof(diffCount) + diffCount > maxBytes) {
                        // Diff is too big.
                        return -1;
                    }
                    scratch[o++] = kDiffSequence;
                    memcpy(scratch + o, &diffCount, sizeof(diffCount));
                    o += sizeof(diffCount);
                    memcpy(scratch + o, startDiff, diffCount);
                    o += diffCount;
                    [self debug:@"diff " buffer:startDiff length:diffCount];
                    diffCount = 0;
                }
                ++sameCount;
            } else {
                if (sameCount > 0) {
                    if (o + 1 + sizeof(sameCount) > maxBytes) {
                        // Diff is too big.
                        return -1;
                    }
                    scratch[o++] = kSameSequence;
                    memcpy(scratch + o, &sameCount, sizeof(sameCount));
                    o += sizeof(sameCount);
    #ifdef DVRDEBUG
                    NSLog(@"%d the same", sameCount);
    #endif
                    sameCount = 0;
                }
                if (!diffCount) {
                    startDiff = frameLine + x;
                }
                other[i] = frameLine[x];
                ++diffCount;
            }
        }
        if (diffCount > 0) {
            if (o + 1 + sizeof(diffCount) + diffCount > maxBytes) {
                // Diff is too big.
                return -1;
            }
            scratch[o++] = kDiffSequence;
            memcpy(scratch + o, &diffCount, sizeof(diffCount));
            o += sizeof(diffCount);
            memcpy(scratch + o, startDiff, diffCount);
            o += diffCount;
            [self debug:@"diff " buffer:startDiff length:diffCount];
            diffCount = 0;
        }
        if (sameCount > 0) {
            if (o + 1 + sizeof(sameCount) > maxBytes) {
                // Diff is too big.
                return -1;
            }
            scratch[o++] = kSameSequence;
            memcpy(scratch + o, &sameCount, sizeof(sameCount));
            o += sizeof(sameCount);
#ifdef DVRDEBUG
            NSLog(@"%d the same", sameCount);
#endif
            sameCount = 0;
        }
    }
    return o;
}

@end
