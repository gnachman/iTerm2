//
//  VT100ByteStream.h
//  iTerm2
//
//  Created by George Nachman on 4/24/25.
//

#import <AppKit/AppKit.h>
#import "DebugLogging.h"
#import "iTermMalloc.h"

#define kDefaultStreamSize 100000

typedef struct {
    unsigned char *stream;

    // Used space in `stream`, including already-processed bytes at the head.
    int currentLength;

    // Allocated capacity of `stream`.
    int totalLength;

    // Number of bytes at the head of `stream` that have already been consumed.
    int offset;
} VT100ByteStream;

NS_INLINE void VT100ByteStreamInit(VT100ByteStream *self) {
    self->totalLength = kDefaultStreamSize;
    self->stream = iTermMalloc(self->totalLength);
    self->currentLength = 0;
    self->offset = 0;
}

NS_INLINE void VT100ByteStreamFree(VT100ByteStream *self) {
    free(self->stream);
}

NS_INLINE int VT100ByteStreamGetCapacity(VT100ByteStream *self) {
    return self->totalLength;
}

NS_INLINE int VT100ByteStreamGetConsumed(VT100ByteStream *self) {
    return self->offset;
}

NS_INLINE int VT100ByteStreamGetRemainingSize(VT100ByteStream *self) {
    return self->currentLength - self->offset;
}

NS_INLINE NSData *VT100ByteStreamMakeData(VT100ByteStream *self) {
    return [NSData dataWithBytes:self->stream + self->offset
                          length:VT100ByteStreamGetRemainingSize(self)];
}

NS_INLINE void VT100ByteStreamConsumeAll(VT100ByteStream *self) {
    self->offset = self->currentLength;
    ITAssertWithMessage(self->offset >= 0, @"Negative offset");
}

NS_INLINE void VT100ByteStreamConsume(VT100ByteStream *self, int count) {
    self->offset += count;
    ITAssertWithMessage(self->offset >= 0, @"Negative offset after consuming %d", count);
    ITAssertWithMessage(self->offset <= self->currentLength, @"Offset too big");
}

NS_INLINE void VT100ByteStreamReset(VT100ByteStream *self) {
    self->offset = 0;
    self->currentLength = 0;

    if (VT100ByteStreamGetCapacity(self) >= kDefaultStreamSize * 2) {
        // We are done with this stream. Get rid of it and allocate a new one
        // to avoid allowing this to grow too big.
        free(self->stream);
        self->totalLength = kDefaultStreamSize;
        self->stream = iTermMalloc(self->totalLength);
    }
}

NS_INLINE void VT100ByteStreamAppend(VT100ByteStream *self, const unsigned char *bytes, int length) {
    if (self->currentLength + length > self->totalLength) {
        // Grow the stream if needed. Don't grow too fast so the xterm parser can catch overflow.
        int n = MIN(500, (length + self->currentLength) / kDefaultStreamSize);

        // Make sure it grows enough to hold this.
        NSInteger proposedSize = self->totalLength;
        proposedSize += MAX(n * kDefaultStreamSize, length);
        if (proposedSize >= INT_MAX) {
            DLog(@"Stream too big!");
            return;
        }
        self->totalLength = proposedSize;
        self->stream = iTermRealloc(self->stream, self->totalLength, 1);
    }

    memcpy(self->stream + self->currentLength, bytes, length);
    self->currentLength += length;
    assert(self->currentLength >= 0);
    if (self->currentLength == 0) {
        self->offset = 0;
    }
}

#pragma mark - Cursor

typedef struct {
    unsigned char *datap;
    int datalen;
} VT100ByteStreamCursor;

NS_INLINE void VT100ByteStreamCursorInit(VT100ByteStreamCursor *self,
                                      VT100ByteStream *stream) {
    self->datap = stream->stream + stream->offset;
    self->datalen = stream->currentLength - stream->offset;
    ITAssertWithMessage(self->datalen >= 0, @"Negative data length");
}

// Returns the number of bytes remaining to parse.
NS_INLINE int VT100ByteStreamCursorGetSize(const VT100ByteStreamCursor *self) {
    return self->datalen;
}

NS_INLINE unsigned char VT100ByteStreamCursorPeek(const VT100ByteStreamCursor *self) {
    ITAssertWithMessage(self->datalen > 0, @"Peek on empty cursor");
    return *self->datap;
 }

NS_INLINE void VT100ByteStreamCursorAdvance(VT100ByteStreamCursor *self, int count) {
    ITAssertWithMessage(count <= self->datalen,
                        @"Advance past end of cursor (count=%d, remaining=%d)",
                        count, self->datalen);
    self->datap += count;
    self->datalen -= count;
}

NS_INLINE const unsigned char *VT100ByteStreamCursorGetPointer(const VT100ByteStreamCursor *self) {
    return self->datap;
}

NS_INLINE unsigned char *VT100ByteStreamCursorGetMutablePointer(VT100ByteStreamCursor *self) {
    return self->datap;
}

NS_INLINE unsigned char VT100ByteStreamCursorPeekOffset(const VT100ByteStreamCursor *self, int offset) {
    return *(self->datap + offset);
}

#warning TODO: This is gonna be a problem
NS_INLINE void VT100ByteStreamCursorWrite(VT100ByteStreamCursor *self, unsigned char c) {
    self->datap[0] = c;
}

NS_INLINE NSString *VT100ByteStreamCursorMakeString(const VT100ByteStreamCursor *self,
                                                    int length,
                                                    NSStringEncoding encoding) {
    return [[[NSString alloc] initWithBytes:self->datap
                                     length:length
                                   encoding:encoding] autorelease];
}

NS_INLINE NSString *VT100ByteStreamCursorDescription(const VT100ByteStreamCursor *self) {
    return [NSString stringWithFormat:@"%.*s", self->datalen, self->datap];
}

NS_INLINE void VT100ByteStreamCursorCopy(VT100ByteStreamCursor *self,
                                         void *destination,
                                         int count) {
    memcpy(destination, self->datap, count);
}

NS_INLINE NSData *VT100ByteStreamCursorMakeData(const VT100ByteStreamCursor *self,
                                                int length) {
    return [NSData dataWithBytes:VT100ByteStreamCursorGetPointer(self)
                          length:length];
}

typedef struct {
    VT100ByteStreamCursor cursor;
    int rmlen;
} VT100ByteStreamConsumer;

NS_INLINE void VT100ByteStreamConsumerInit(VT100ByteStreamConsumer *self,
                                           VT100ByteStreamCursor cursor) {
    self->cursor = cursor;
    self->rmlen = 0;
}

NS_INLINE void VT100ByteStreamConsumerReset(VT100ByteStreamConsumer *self) {
    self->rmlen = 0;
}

NS_INLINE unsigned char VT100ByteStreamConsumerPeek(VT100ByteStreamConsumer *self) {
    return VT100ByteStreamCursorPeek(&self->cursor);
}

NS_INLINE int VT100ByteStreamConsumerGetSize(VT100ByteStreamConsumer *self) {
    return VT100ByteStreamCursorGetSize(&self->cursor);
}

NS_INLINE VT100ByteStreamCursor VT100ByteStreamConsumerGetCursor(VT100ByteStreamConsumer *self) {
    return self->cursor;
}

NS_INLINE void VT100ByteStreamConsumerConsume(VT100ByteStreamConsumer *self, int count) {
    self->rmlen += count;
    ITAssertWithMessage(self->rmlen <= VT100ByteStreamCursorGetSize(&self->cursor), @"Consumed too much");
}

NS_INLINE void VT100ByteStreamConsumerSetConsumed(VT100ByteStreamConsumer *self, int count) {
    self->rmlen = count;
    ITAssertWithMessage(self->rmlen <= VT100ByteStreamCursorGetSize(&self->cursor), @"Consumed too much");
}

NS_INLINE int VT100ByteStreamConsumerGetConsumed(VT100ByteStreamConsumer *self) {
    return self->rmlen;
}

NS_INLINE NSString *VT100ByteStreamConsumerDescription(VT100ByteStreamConsumer *self) {
    return [NSString stringWithFormat:@"<Consumer rmlen=%d cursor=%@>", self->rmlen,
            VT100ByteStreamCursorDescription(&self->cursor)];
}

NS_INLINE void VT100ByteStreamConsumerWriteHead(VT100ByteStreamConsumer *self, unsigned char c) {
    VT100ByteStreamCursorWrite(&self->cursor, c);
}
