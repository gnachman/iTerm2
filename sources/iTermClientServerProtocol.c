//
//  iTermClientServerProtocol.c
//  iTerm2
//
//  Created by George Nachman on 7/25/19.
//

#import "iTermClientServerProtocol.h"

#import "iTermCLogging.h"

#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAX(a, b) ((a) > (b) ? (a) : (b))

const size_t ITERM_MULTISERVER_BUFFER_SIZE = 65536;
const int ITERM_MULTISERVER_MAGIC = 0xdeadbeef;

typedef enum iTermClientServerProtocolError {
    iTermClientServerProtocolErrorTagTruncated,
    iTermClientServerProtocolErrorLengthTruncated,
    iTermClientServerProtocolErrorValueTruncated,
    iTermClientServerProtocolErrorUnexpectedTag,
    iTermClientServerProtocolErrorUnexpectedLength,
    iTermClientServerProtocolErrorStringArrayTruncated,
    iTermClientServerProtocolErrorStringArrayCountTruncated,
    iTermClientServerProtocolErrorStringArrayTooBig,
    iTermClientServerProtocolErrorOutOfSpace
} iTermClientServerProtocolError;

void iTermClientServerProtocolMessageInitialize(iTermClientServerProtocolMessage *message) {
    memset(message, 0, sizeof(*message));
    message->ioVectors[0].iov_base = malloc(ITERM_MULTISERVER_BUFFER_SIZE);
    message->ioVectors[0].iov_len = ITERM_MULTISERVER_BUFFER_SIZE;

    message->message.msg_iov = message->ioVectors;
    message->message.msg_iovlen = 1;

    message->message.msg_name = NULL;
    message->message.msg_namelen = 0;

    message->message.msg_control = &message->controlBuffer;
    message->message.msg_controllen = sizeof(message->controlBuffer);
    message->valid = ITERM_MULTISERVER_MAGIC;
}

void iTermClientServerProtocolMessageEnsureSpace(iTermClientServerProtocolMessage *message,
                                                 ssize_t spaceNeeded) {
    message->ioVectors[0].iov_base = realloc(message->ioVectors[0].iov_base, MAX(1, spaceNeeded));
    assert(message->ioVectors[0].iov_base != NULL);
    message->ioVectors[0].iov_len = spaceNeeded;

    message->message.msg_iov[0].iov_base = message->ioVectors[0].iov_base;
    message->message.msg_iov[0].iov_len = message->ioVectors[0].iov_len;
}

void iTermClientServerProtocolMessageFree(iTermClientServerProtocolMessage *message) {
    free(message->ioVectors[0].iov_base);
    memset(message, 0, sizeof(*message));
}

static size_t iTermClientServerProtocolParserBytesLeft(iTermClientServerProtocolMessageParser *parser) {
    const size_t length = parser->message->message.msg_iov[0].iov_len;
    if (parser->offset >= length) {
        return 0;
    }
    return length - parser->offset;
}

static void iTermClientServerProtocolParserCopyAndAdvance(iTermClientServerProtocolMessageParser *parser,
                                                          void *out,
                                                          size_t size) {
    assert(iTermClientServerProtocolParserBytesLeft(parser) >= size);
    memmove(out, parser->message->ioVectors[0].iov_base + parser->offset, size);
    parser->offset += size;
}

static int iTermClientServerProtocolParseInt(iTermClientServerProtocolMessageParser *parser,
                                             void *out,
                                             size_t size) {
    if (iTermClientServerProtocolParserBytesLeft(parser) < size) {
        return iTermClientServerProtocolErrorValueTruncated;
    }
    iTermClientServerProtocolParserCopyAndAdvance(parser, out, size);
    return 0;
}

int iTermClientServerProtocolParseTaggedInt(iTermClientServerProtocolMessageParser *parser,
                                            void *out,
                                            size_t size,
                                            int tag) {
    int actualTag;
    if (iTermClientServerProtocolParseInt(parser, &actualTag, sizeof(actualTag))) {
        return iTermClientServerProtocolErrorTagTruncated;
    }
    if (actualTag != tag) {
        return iTermClientServerProtocolErrorUnexpectedTag;
    }

    size_t length;
    if (iTermClientServerProtocolParseInt(parser, &length, sizeof(length))) {
        return iTermClientServerProtocolErrorLengthTruncated;
    }
    if (length != size) {
        return iTermClientServerProtocolErrorUnexpectedLength;
    }

    return iTermClientServerProtocolParseInt(parser, out, size);
}

static int iTermClientServerProtocolParseString(iTermClientServerProtocolMessageParser *parser,
                                                char **out) {
    size_t length;
    if (iTermClientServerProtocolParseInt(parser, &length, sizeof(length))) {
        return iTermClientServerProtocolErrorLengthTruncated;
    }
    if (iTermClientServerProtocolParserBytesLeft(parser) < length) {
        return iTermClientServerProtocolErrorValueTruncated;
    }
    *out = malloc(length + 1);
    iTermClientServerProtocolParserCopyAndAdvance(parser, *out, length);
    (*out)[length] = '\0';
    return 0;
}

int iTermClientServerProtocolParseTaggedString(iTermClientServerProtocolMessageParser *parser,
                                               char **out,
                                               int tag) {
    int actualTag;
    if (iTermClientServerProtocolParseInt(parser, &actualTag, sizeof(actualTag))) {
        return iTermClientServerProtocolErrorTagTruncated;
    }
    return iTermClientServerProtocolParseString(parser, out);
}

static int iTermClientServerProtocolParseStringArray(iTermClientServerProtocolMessageParser *parser,
                                                     int tag,
                                                     char ***arrayOut,
                                                     int *countOut) {
    if (iTermClientServerProtocolParseInt(parser, countOut, sizeof(*countOut))) {
        return iTermClientServerProtocolErrorStringArrayCountTruncated;
    }
    static const int MAX_STRING_ARRAY_COUNT = 1024 * 1024;
    if (*countOut > MAX_STRING_ARRAY_COUNT) {
        return iTermClientServerProtocolErrorStringArrayTooBig;
    }
    *arrayOut = malloc(sizeof(char *) * (*countOut + 1));
    int truncated = 0;
    for (int i = 0; i < *countOut; i++) {
        if (!truncated && iTermClientServerProtocolParseTaggedString(parser, &(*arrayOut)[i], tag)) {
            truncated = 1;
        }
        if (truncated) {
            (*arrayOut)[i] = NULL;
        }
    }
    (*arrayOut)[*countOut] = NULL;
    return truncated ? iTermClientServerProtocolErrorStringArrayTruncated : 0;
}

int iTermClientServerProtocolParseTaggedStringArray(iTermClientServerProtocolMessageParser *parser,
                                                    char ***arrayOut,
                                                    int *countOut,
                                                    int tag) {
    int actualTag;
    if (iTermClientServerProtocolParseInt(parser, &actualTag, sizeof(actualTag))) {
        return iTermClientServerProtocolErrorTagTruncated;
    }
    if (actualTag != tag) {
        return iTermClientServerProtocolErrorUnexpectedTag;
    }
    return iTermClientServerProtocolParseStringArray(parser, tag, arrayOut, countOut);
}

#pragma mark - Encoding

static size_t iTermClientServerProtocolEncoderBytesLeft(iTermClientServerProtocolMessageEncoder *encoder) {
    const size_t length = encoder->message->message.msg_iov[0].iov_len;
    if (encoder->offset >= length) {
        return 0;
    }
    return length - encoder->offset;
}

static void iTermClientServerProtocolEncoderEnsureSpace(iTermClientServerProtocolMessageEncoder *encoder,
                                                        ssize_t additionalSpace) {
    const size_t freeSpace = iTermClientServerProtocolEncoderBytesLeft(encoder);
    if (freeSpace >= additionalSpace) {
        return;
    }
    iTermClientServerProtocolMessageEnsureSpace(encoder->message, additionalSpace - freeSpace);
}

static void iTermClientServerProtocolEncoderCopyAndAdvance(iTermClientServerProtocolMessageEncoder *encoder,
                                                           const void *ptr,
                                                           size_t size) {
    iTermClientServerProtocolEncoderEnsureSpace(encoder, size);
    memmove(encoder->message->ioVectors[0].iov_base + encoder->offset, ptr, size);
    encoder->offset += size;
}

static void iTermClientServerProtocolEncodeInt(iTermClientServerProtocolMessageEncoder *encoder,
                                               void *valuePtr,
                                               size_t size) {
    iTermClientServerProtocolEncoderCopyAndAdvance(encoder, valuePtr, size);
}

int iTermClientServerProtocolEncodeTaggedInt(iTermClientServerProtocolMessageEncoder *encoder,
                                             void *valuePtr,
                                             size_t size,
                                             int tag) {
    iTermClientServerProtocolEncodeInt(encoder, &tag, sizeof(tag));
    iTermClientServerProtocolEncodeInt(encoder, &size, sizeof(size));
    iTermClientServerProtocolEncodeInt(encoder, valuePtr, size);

    return 0;
}

static int iTermClientServerProtocolEncodeString(iTermClientServerProtocolMessageEncoder *encoder,
                                                 const char *string) {
    size_t length = strlen(string);
    iTermClientServerProtocolEncodeInt(encoder, &length, sizeof(length));
    iTermClientServerProtocolEncoderCopyAndAdvance(encoder, string, length);
    return 0;
}

int iTermClientServerProtocolEncodeTaggedString(iTermClientServerProtocolMessageEncoder *encoder,
                                                const char *string,
                                                int tag) {
    iTermClientServerProtocolEncodeInt(encoder, &tag, sizeof(tag));
    return iTermClientServerProtocolEncodeString(encoder, string);
}

static int iTermClientServerProtocolEncodeStringArray(iTermClientServerProtocolMessageEncoder *encoder,
                                                      int tag,
                                                      char **array,
                                                      int count) {
    iTermClientServerProtocolEncodeInt(encoder, &count, sizeof(count));
    for (int i = 0; i < count; i++) {
        iTermClientServerProtocolEncodeTaggedString(encoder, array[i], tag);
    }
    return 0;
}

int iTermClientServerProtocolEncodeTaggedStringArray(iTermClientServerProtocolMessageEncoder *encoder,
                                                     char **array,
                                                     int count,
                                                     int tag) {
    iTermClientServerProtocolEncodeInt(encoder, &tag, sizeof(tag));
    return iTermClientServerProtocolEncodeStringArray(encoder, tag, array, count);
}

void iTermEncoderCommit(iTermClientServerProtocolMessageEncoder *encoder) {
    encoder->message->ioVectors[0].iov_len = encoder->offset;
}
