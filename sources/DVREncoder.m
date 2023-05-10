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

//#if DEBUG
//#define DVRDEBUG
//#endif

// Returns a timestamp for the current time.
static long long now(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    long long result = tv.tv_sec;
    result *= 1000000;
    result += tv.tv_usec;
    return result;
}

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

// NOTE: length is the size needed for frameLines but not for metadata.
- (void)appendFrame:(NSArray *)frameLines
             length:(int)length
           metadata:(NSArray<id<DVREncodable>> *)metadata
         cleanLines:(NSIndexSet *)cleanLines
               info:(DVRFrameInfo*)info {
#ifdef DVRDEBUG
    NSLog(@"Encoding frame");
#endif
    BOOL eligibleForDiff;
    if (cleanLines.count > info->height * 0.8 &&
        lastFrame_ &&
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
        [self _appendKeyFrame:frameLines length:length metadata:metadata info:info];
    } else {
        [self _appendDiffFrame:frameLines length:length metadata:metadata cleanLines:cleanLines info:info];
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

- (void)debug:(NSString*)prefix buffer:(const char *)buffer length:(int)length
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
    NSLog(@"Encoder: %@ length %d: \"%s\"", prefix, length, d);
#endif
}

- (NSMutableData *)combinedFrameLines:(NSArray *)frameLines {
    NSMutableData *data = [[[NSMutableData alloc] init] autorelease];
    for (NSData *line in frameLines) {
        [data appendData:line];
    }
    return data;
}

// Save a key frame into DVRBuffer.
- (void)_appendKeyFrame:(NSArray *)frameLines length:(int)length metadata:(NSArray<id<DVREncodable>> *)metadata info:(DVRFrameInfo*)info {
    [lastFrame_ release];
    lastFrame_ = [[self combinedFrameLines:frameLines] retain];
    assert(lastFrame_.length == length);
    char* scratch = [buffer_ scratch];
    memcpy(scratch, [lastFrame_ mutableBytes], length);
    __block int offset = length;
    [metadata enumerateObjectsUsingBlock:^(id<DVREncodable>  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSData *data = [obj dvrEncodableData];
#ifdef DVRDEBUG
        NSLog(@"Append metadata at offset %@, length is %@", @(offset), @(data.length));
#endif
        assert(data.length < INT_MAX);
        int length = data.length;
        memcpy(scratch + offset, &length, sizeof(length));
        offset += sizeof(length);
        memcpy(scratch + offset, data.bytes, data.length);
        offset += data.length;
    }];
    [self _appendFrameImpl:scratch length:offset type:DVRFrameTypeKeyFrame info:info];
    bytesSinceLastKeyFrame_ = 0;
}

// Save a diff frame into DVRBuffer.
- (void)_appendDiffFrame:(NSArray *)frameLines
                  length:(int)length
                metadata:(NSArray<id<DVREncodable>> *)metadata
              cleanLines:(NSIndexSet *)cleanLines
                    info:(DVRFrameInfo *)info {
    char* scratch = [buffer_ scratch];
#ifdef DVRDEBUG
    NSLog(@"Compute diff…");
#endif
    int diffBytes = [self _computeDiff:frameLines
                                length:length
                              metadata:metadata
                            cleanLines:cleanLines
                                  dest:scratch
                               maxSize:reservation_];
    if (diffBytes < 0) {
#ifdef DVRDEBUG
        NSLog(@"Abandon diff and append a key frame instead");
#endif
        // Diff ended up being larger than a key frame would be.
        [self _appendKeyFrame:frameLines length:length metadata:metadata info:info];
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

// Save a frame into DVRBuffer.
- (void)_appendFrameImpl:(char*)dest length:(int)length type:(DVRFrameType)type info:(DVRFrameInfo*)info
{
    assert(haveReservation_);
    haveReservation_ = NO;

#ifdef DVRDEBUG
    NSLog(@"Encoder: Append frame of type %d starting at offset %d length %d at index %lld",
          (int)type, (int)[buffer_ offsetOfPointer:dest], length, [buffer_ lastKey]+1);
#endif

    lastInfo_ = *info;

    long long key = [buffer_ allocateBlock:length];
#ifdef DVRDEBUG
    NSLog(@"Commit frame with key %@", @(key));
#endif
    DVRIndexEntry* entry = [buffer_ entryForKey:key];
    entry->info = *info;
    entry->info.timestamp = now();
    entry->info.frameType = type;
    DLog(@"Append frame with key %lld, size %dx%d", key, info->width, info->height);
}

// Calculate the diff between buffer,length and the previous frame. Saves results into
// scratch. Won't use more than maxSize bytes in scratch. Returns number of bytes used or
// -1 if the diff was larger than maxSize.
- (int)_computeDiff:(NSArray<NSData *> *)frameLines
             length:(int)length
           metadata:(NSArray<id<DVREncodable>> *)metadata
         cleanLines:(NSIndexSet *)cleanLines
               dest:(char *)scratch
            maxSize:(int)maxBytes {
    assert(length == [lastFrame_ length]);

    int o = 0;

#ifdef DVRDEBUG
    NSLog(@"Computing diff");
#endif
    const int numLines = [frameLines count];
    {
        const int numChars = numLines > 0 ? frameLines[0].length : 0;
        for (int y = 0; y < numLines; y++) {
            if ([cleanLines containsIndex:y]) {
                if (o + 1 + sizeof(numChars) > maxBytes) {
                    // Diff is too big.
                    return -1;
                }
#ifdef DVRDEBUG
                NSLog(@"Append samesequence at offset %@, address %p. No data is appended for samesequence.", @(o), scratch+o);
#endif
                scratch[o++] = kSameSequence;
                memcpy(scratch + o, &numChars, sizeof(numChars));
                o += sizeof(numChars);
            } else {
                if (o + 1 + sizeof(numChars) + numChars > maxBytes) {
                    // Diff is too big.
                    return -1;
                }
#ifdef DVRDEBUG
                NSLog(@"Append diffsequence at offset %@ of length %@", @(o), @(numChars));
#endif
                scratch[o++] = kDiffSequence;
                memcpy(scratch + o, &numChars, sizeof(numChars));
                o += sizeof(numChars);
                NSData *lineData = frameLines[y];
                const char *frameLine = [lineData bytes];
                memcpy(scratch + o, frameLine, numChars);
                o += numChars;
#ifdef DVRDEBUG
                [self debug:@"Encoder: diff " buffer:frameLine length:numChars];
#endif
            }
        }
    }

    // Append metadata.
    {
        for (int y = 0; y < numLines; y++) {
            if ([cleanLines containsIndex:y]) {
                // [byte(kSameSequence), int32(0)]
                const int payloadLength = 0;
                if (o + 1 + sizeof(payloadLength) > maxBytes) {
                    // Diff is too big.
                    return -1;
                }
#ifdef DVRDEBUG
                NSLog(@"Append metadata samesequence at offset %@, address %p. No data is appended for samesequence.", @(o), scratch+o);
#endif
                scratch[o++] = kSameSequence;
                memcpy(scratch + o, &payloadLength, sizeof(payloadLength));
                o += sizeof(payloadLength);
            } else {
                // [byte(kDiffSequence), int32(payloadLength), byte[payloadLength]]
                NSData *encoded = [metadata[y] dvrEncodableData];
                const int payloadLength = encoded.length;
                if (o + 1 + sizeof(payloadLength) + payloadLength > maxBytes) {
                    // Diff is too big.
                    return -1;
                }
#ifdef DVRDEBUG
                NSLog(@"Append metadata at offset %@ of length %@", @(o), @(encoded.length));
#endif
                scratch[o++] = kDiffSequence;
                memcpy(scratch + o, &payloadLength, sizeof(payloadLength));
                o += sizeof(payloadLength);
                NSData *lineData = encoded;
                const char *frameLine = lineData.bytes;
                memcpy(scratch + o, frameLine, payloadLength);
                o += payloadLength;
#ifdef DVRDEBUG
                NSLog(@"Encoder: append metadata diff of length %@", @(encoded.length));
#endif
            }
        }
    }
#ifdef DVRDEBUG
    NSLog(@"Done computing diff");
#endif
    return o;
}

@end
