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

const size_t ITERM_MULTISERVER_BUFFER_SIZE = 65536;
const int ITERM_MULTISERVER_MAGIC = 0xdeadbeef;

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
        return -1;
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
        return -1;
    }
    if (actualTag != tag) {
        return -1;
    }

    size_t length;
    if (iTermClientServerProtocolParseInt(parser, &length, sizeof(length))) {
        return -1;
    }
    if (length != size) {
        return -1;
    }

    return iTermClientServerProtocolParseInt(parser, out, size);
}

static int iTermClientServerProtocolParseString(iTermClientServerProtocolMessageParser *parser,
                                                char **out) {
    size_t length;
    if (iTermClientServerProtocolParseInt(parser, &length, sizeof(length))) {
        return -1;
    }
    if (iTermClientServerProtocolParserBytesLeft(parser) < length) {
        return -1;
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
        return -1;
    }
    return iTermClientServerProtocolParseString(parser, out);
}

static int iTermClientServerProtocolParseStringArray(iTermClientServerProtocolMessageParser *parser,
                                                     int tag,
                                                     char ***arrayOut,
                                                     int *countOut) {
    if (iTermClientServerProtocolParseInt(parser, countOut, sizeof(*countOut))) {
        return -1;
    }
    *arrayOut = malloc(sizeof(char *) * (*countOut + 1));
    for (int i = 0; i < *countOut; i++) {
        if (iTermClientServerProtocolParseTaggedString(parser, &(*arrayOut)[i], tag)) {
            return -1;
        }
    }
    (*arrayOut)[*countOut] = NULL;
    return 0;
}

int iTermClientServerProtocolParseTaggedStringArray(iTermClientServerProtocolMessageParser *parser,
                                                    char ***arrayOut,
                                                    int *countOut,
                                                    int tag) {
    int actualTag;
    if (iTermClientServerProtocolParseInt(parser, &actualTag, sizeof(actualTag))) {
        return -1;
    }
    if (actualTag != tag) {
        return -1;
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

static void iTermClientServerProtocolEncoderCopyAndAdvance(iTermClientServerProtocolMessageEncoder *encoder,
                                                           const void *ptr,
                                                           size_t size) {
    assert(iTermClientServerProtocolEncoderBytesLeft(encoder) >= size);
    memmove(encoder->message->ioVectors[0].iov_base + encoder->offset, ptr, size);
    encoder->offset += size;
}

static int iTermClientServerProtocolEncodeInt(iTermClientServerProtocolMessageEncoder *encoder,
                                              void *valuePtr,
                                              size_t size) {
    if (iTermClientServerProtocolEncoderBytesLeft(encoder) < size) {
        FDLog(LOG_ERR, "Ran out of space while encoding int value of size %d at offset %d",
              (int)size, (int)encoder->offset);
        return -1;
    }
    iTermClientServerProtocolEncoderCopyAndAdvance(encoder, valuePtr, size);
    return 0;
}

int iTermClientServerProtocolEncodeTaggedInt(iTermClientServerProtocolMessageEncoder *encoder,
                                             void *valuePtr,
                                             size_t size,
                                             int tag) {
    if (iTermClientServerProtocolEncodeInt(encoder, &tag, sizeof(tag))) {
        return -1;
    }

    if (iTermClientServerProtocolEncodeInt(encoder, &size, sizeof(size))) {
        return -1;
    }

    if (iTermClientServerProtocolEncodeInt(encoder, valuePtr, size)) {
        return -1;
    }

    return 0;
}

static int iTermClientServerProtocolEncodeString(iTermClientServerProtocolMessageEncoder *encoder,
                                                 const char *string) {
    size_t length = strlen(string);
    if (iTermClientServerProtocolEncodeInt(encoder, &length, sizeof(length))) {
        return -1;
    }
    if (iTermClientServerProtocolEncoderBytesLeft(encoder) < length) {
        FDLog(LOG_ERR, "Ran out of space while encoding string of size %d at offset %d",
              (int)length, (int)encoder->offset);
        return -1;
    }
    iTermClientServerProtocolEncoderCopyAndAdvance(encoder, string, length);
    return 0;
}

int iTermClientServerProtocolEncodeTaggedString(iTermClientServerProtocolMessageEncoder *encoder,
                                                const char *string,
                                                int tag) {
    if (iTermClientServerProtocolEncodeInt(encoder, &tag, sizeof(tag))) {
        return -1;
    }
    return iTermClientServerProtocolEncodeString(encoder, string);
}

static int iTermClientServerProtocolEncodeStringArray(iTermClientServerProtocolMessageEncoder *encoder,
                                                      int tag,
                                                      char **array,
                                                      int count) {
    if (iTermClientServerProtocolEncodeInt(encoder, &count, sizeof(count))) {
        return -1;
    }
    for (int i = 0; i < count; i++) {
        if (iTermClientServerProtocolEncodeTaggedString(encoder, array[i], tag)) {
            return -1;
        }
    }
    return 0;
}

int iTermClientServerProtocolEncodeTaggedStringArray(iTermClientServerProtocolMessageEncoder *encoder,
                                                     char **array,
                                                     int count,
                                                     int tag) {
    if (iTermClientServerProtocolEncodeInt(encoder, &tag, sizeof(tag))) {
        return -1;
    }
    return iTermClientServerProtocolEncodeStringArray(encoder, tag, array, count);
}

void iTermEncoderCommit(iTermClientServerProtocolMessageEncoder *encoder) {
    encoder->message->ioVectors[0].iov_len = encoder->offset;
}
