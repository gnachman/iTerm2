//
//  VT100StringParser.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "VT100StringParser.h"

#import "DebugLogging.h"
#import "NSStringITerm.h"
#import "ScreenChar.h"

static void DecodeUTF8Bytes(VT100ByteStreamConsumer *consumer,
                            VT100Token *token) {
    int utf8DecodeResult;
    int consumed = 0;

    VT100ByteStreamCursor cursor = VT100ByteStreamConsumerGetCursor(consumer);

    while (true) {
        int codePoint = 0;
        utf8DecodeResult = decode_utf8_char(
            VT100ByteStreamCursorGetPointer(&cursor),
            VT100ByteStreamCursorGetSize(&cursor),
            &codePoint
        );
        // Stop on error or end of stream.
        if (utf8DecodeResult <= 0) {
            break;
        }
        // Intentionally break out at ASCII characters. They are
        // processed separately, e.g. they might get converted into
        // line drawing characters.
        if (codePoint < 0x80) {
            break;
        }
        VT100ByteStreamCursorAdvance(&cursor, utf8DecodeResult);
        consumed += utf8DecodeResult;
    }

    if (consumed > 0) {
        // If some characters were successfully decoded, just return them
        // and ignore the error or end of stream for now.
        VT100ByteStreamConsumerSetConsumed(consumer, consumed);
        assert(consumed >= 0);
        token->type = VT100_STRING;
    } else {
        // Report error or waiting state.
        if (utf8DecodeResult == 0) {
            token->type = VT100_WAIT;
        } else {
            VT100ByteStreamConsumerSetConsumed(consumer, -utf8DecodeResult);
            token->type = VT100_INVALID_SEQUENCE;
        }
    }
}


static void DecodeEUCCNBytes(VT100ByteStreamConsumer *consumer,
                             VT100Token *token) {
    VT100ByteStreamCursor cursor = VT100ByteStreamConsumerGetCursor(consumer);
    int consumed = 0;
    int size;
    while ((size = VT100ByteStreamCursorGetSize(&cursor)) > 0) {
        unsigned char c1 = VT100ByteStreamCursorPeek(&cursor);

        if (iseuccn(c1) && size > 1) {
            unsigned char c2 = VT100ByteStreamCursorPeekOffset(&cursor, 1);
            if ((c2 >= 0x40 && c2 <= 0x7e) ||
                (c2 >= 0x80 && c2 <= 0xfe)) {
                VT100ByteStreamCursorAdvance(&cursor, 2);
                consumed += 2;
            } else {
                // replace invalid second byte
                VT100ByteStreamCursorWrite(&cursor, ONECHAR_UNKNOWN);
                VT100ByteStreamCursorAdvance(&cursor, 1);
                consumed += 1;
            }
        } else {
            break;
        }
    }

    if (consumed == 0) {
        VT100ByteStreamConsumerSetConsumed(consumer, 0);
        token->type = VT100_WAIT;
    } else {
        VT100ByteStreamConsumerSetConsumed(consumer, consumed);
        token->type = VT100_STRING;
    }
}

static void DecodeBIG5Bytes(VT100ByteStreamConsumer *consumer,
                            VT100Token *token) {
    VT100ByteStreamCursor cursor = VT100ByteStreamConsumerGetCursor(consumer);
    int consumed = 0;

    int size;
    while ((size = VT100ByteStreamCursorGetSize(&cursor)) > 0) {
        unsigned char c1 = VT100ByteStreamCursorPeek(&cursor);

        if (isbig5(c1) && size > 1) {
            unsigned char c2 = VT100ByteStreamCursorPeekOffset(&cursor, 1);
            if ((c2 >= 0x40 && c2 <= 0x7e) ||
                (c2 >= 0xa1 && c2 <= 0xfe)) {
                VT100ByteStreamCursorAdvance(&cursor, 2);
                consumed += 2;
            } else {
                VT100ByteStreamCursorWrite(&cursor, ONECHAR_UNKNOWN);
                VT100ByteStreamCursorAdvance(&cursor, 1);
                consumed += 1;
            }
        } else {
            break;
        }
    }

    if (consumed == 0) {
        VT100ByteStreamConsumerSetConsumed(consumer, 0);
        token->type = VT100_WAIT;
    } else {
        VT100ByteStreamConsumerSetConsumed(consumer, consumed);
        token->type = VT100_STRING;
    }
}

static void DecodeEUCJPBytes(VT100ByteStreamConsumer *consumer,
                             VT100Token *token) {
    VT100ByteStreamCursor cursor = VT100ByteStreamConsumerGetCursor(consumer);
    int consumed = 0;

    int size;
    while ((size = VT100ByteStreamCursorGetSize(&cursor)) > 0) {
        unsigned char c1 = VT100ByteStreamCursorPeek(&cursor);

        if (size > 1 && c1 == 0x8e) {
            VT100ByteStreamCursorAdvance(&cursor, 2);
            consumed += 2;
        } else if (size > 2 && c1 == 0x8f) {
            VT100ByteStreamCursorAdvance(&cursor, 3);
            consumed += 3;
        } else if (size > 1 && c1 >= 0xa1 && c1 <= 0xfe) {
            VT100ByteStreamCursorAdvance(&cursor, 2);
            consumed += 2;
        } else {
            break;
        }
    }

    if (consumed == 0) {
        VT100ByteStreamConsumerSetConsumed(consumer, 0);
        token->type = VT100_WAIT;
    } else {
        VT100ByteStreamConsumerSetConsumed(consumer, consumed);
        token->type = VT100_STRING;
    }
}


static void DecodeSJISBytes(VT100ByteStreamConsumer *consumer,
                            VT100Token *token) {
    VT100ByteStreamCursor cursor = VT100ByteStreamConsumerGetCursor(consumer);
    int consumed = 0;

    while (VT100ByteStreamCursorGetSize(&cursor) > 0) {
        unsigned char c1 = VT100ByteStreamCursorPeek(&cursor);
        int size = VT100ByteStreamCursorGetSize(&cursor);

        if (issjiskanji(c1) && size > 1) {
            VT100ByteStreamCursorAdvance(&cursor, 2);
            consumed += 2;
        } else if (c1 >= 0x80) {
            VT100ByteStreamCursorAdvance(&cursor, 1);
            consumed += 1;
        } else {
            break;
        }
    }

    if (consumed == 0) {
        VT100ByteStreamConsumerSetConsumed(consumer, 0);
        token->type = VT100_WAIT;
    } else {
        VT100ByteStreamConsumerSetConsumed(consumer, consumed);
        token->type = VT100_STRING;
    }
}

static void DecodeEUCKRBytes(VT100ByteStreamConsumer *consumer,
                             VT100Token *token) {
    VT100ByteStreamCursor cursor = VT100ByteStreamConsumerGetCursor(consumer);
    int consumed = 0;

    int size;
    while ((size = VT100ByteStreamCursorGetSize(&cursor)) > 0) {
        unsigned char c1 = VT100ByteStreamCursorPeek(&cursor);

        if (iseuckr(c1) && size > 1) {
            VT100ByteStreamCursorAdvance(&cursor, 2);
            consumed += 2;
        } else {
            break;
        }
    }

    if (consumed == 0) {
        VT100ByteStreamConsumerSetConsumed(consumer, 0);
        token->type = VT100_WAIT;
    } else {
        VT100ByteStreamConsumerSetConsumed(consumer, consumed);
        token->type = VT100_STRING;
    }
}

static void DecodeCP949Bytes(VT100ByteStreamConsumer *consumer,
                             VT100Token *token) {
    VT100ByteStreamCursor cursor = VT100ByteStreamConsumerGetCursor(consumer);
    int consumed = 0;

    int size;
    while ((size = VT100ByteStreamCursorGetSize(&cursor)) > 0) {
        unsigned char c1 = VT100ByteStreamCursorPeek(&cursor);

        if (iscp949(c1) && size > 1) {
            VT100ByteStreamCursorAdvance(&cursor, 2);
            consumed += 2;
        } else {
            break;
        }
    }

    if (consumed == 0) {
        VT100ByteStreamConsumerSetConsumed(consumer, 0);
        token->type = VT100_WAIT;
    } else {
        VT100ByteStreamConsumerSetConsumed(consumer, consumed);
        token->type = VT100_STRING;
    }
}

static void DecodeOtherBytes(VT100ByteStreamConsumer *consumer,
                             VT100Token *token) {
    VT100ByteStreamCursor cursor = VT100ByteStreamConsumerGetCursor(consumer);
    int consumed = 0;

    while (VT100ByteStreamCursorGetSize(&cursor) > 0) {
        unsigned char c = VT100ByteStreamCursorPeek(&cursor);
        if (c >= 0x80) {
            VT100ByteStreamCursorAdvance(&cursor, 1);
            consumed++;
        } else {
            break;
        }
    }

    if (consumed == 0) {
        VT100ByteStreamConsumerSetConsumed(consumer, 0);
        token->type = VT100_WAIT;
    } else {
        VT100ByteStreamConsumerSetConsumed(consumer, consumed);
        token->type = VT100_STRING;
    }
}

// Mixed ASCII ascii with CRLFs.
// This is a huge performance win for handling big files of mostly plain ascii text.
static void DecodeMixedASCIIBytes(VT100ByteStreamConsumer *consumer,
                                  VT100Token *token) {
    int consumed = 0;

    // I tried the ideas mentioned here:
    // http://stackoverflow.com/questions/22218605/is-this-function-a-good-candidate-for-simd-on-intel
    // (using 8-bytes-at-a-time bit twiddling and SIMD)
    // and although this while loop completed faster, the overall benchmark speed on spam.cc did
    // not improve.
    VT100ByteStreamCursor cursor = VT100ByteStreamConsumerGetCursor(consumer);
    CTVector(int) *crlfs = nil;
    while (VT100ByteStreamCursorGetSize(&cursor) > 0) {
        unsigned char c = VT100ByteStreamCursorPeek(&cursor);
        if (c >= 0x20 && c <= 0x7f) {
            VT100ByteStreamCursorAdvance(&cursor, 1);
            consumed++;
        } else if (c == 13 && VT100ByteStreamCursorDoublePeek(&cursor) == 10) {
            if (!crlfs) {
                [token realizeCRLFsWithCapacity:40];  // This is a wild-ass guess
                crlfs = token.crlfs;
            }
            VT100ByteStreamCursorAdvance(&cursor, 2);
            CTVectorAppend(crlfs, consumed);
            consumed++;
            CTVectorAppend(crlfs, consumed);
            consumed++;
        } else {
            break;
        }
    }

    if (consumed == 0) {
        VT100ByteStreamConsumerReset(consumer);
        token->type = VT100_WAIT;
    } else {
        VT100ByteStreamConsumerSetConsumed(consumer, consumed);
        if (!crlfs) {
            token->type = VT100_ASCIISTRING;
        } else {
            token->type = VT100_MIXED_ASCII_CR_LF;
        }
    }
}

void ParseString(VT100ByteStreamConsumer *consumer,
                 VT100Token *result,
                 NSStringEncoding encoding) {
    VT100ByteStreamConsumerReset(consumer);

    result->type = VT100_UNKNOWNCHAR;
    result->code = VT100ByteStreamConsumerPeek(consumer);

    BOOL isAscii = NO;
    if (isMixedAsciiString(VT100ByteStreamConsumerPeek(consumer),
                           VT100ByteStreamConsumerDoublePeek(consumer))) {
        isAscii = YES;
        DecodeMixedASCIIBytes(consumer, result);
        encoding = NSASCIIStringEncoding;
    } else if (encoding == NSUTF8StringEncoding) {
        DecodeUTF8Bytes(consumer, result);
    } else if (isEUCCNEncoding(encoding)) {
        // Chinese-GB
        DecodeEUCCNBytes(consumer, result);
    } else if (isBig5Encoding(encoding)) {
        DecodeBIG5Bytes(consumer, result);
    } else if (isJPEncoding(encoding)) {
        DecodeEUCJPBytes(consumer, result);
    } else if (isSJISEncoding(encoding)) {
        DecodeSJISBytes(consumer, result);
    } else if (isEUCKREncoding(encoding)) {
        // korean
        DecodeEUCKRBytes(consumer, result);
    } else if (isCP949Encoding(encoding)) {
        // korean
        DecodeCP949Bytes(consumer, result);
    } else {
        DecodeOtherBytes(consumer, result);
    }

    const int consumedCount = VT100ByteStreamConsumerGetConsumed(consumer);
    if (result->type == VT100_INVALID_SEQUENCE) {
        // Output only one replacement symbol, even if rmlen is higher.
        DLog(@"Parsed an invalid sequence of length %d for encoding %@: %@",
             consumedCount,
             @(encoding),
             VT100ByteStreamConsumerDescription(consumer));
        VT100ByteStreamConsumerWriteHead(consumer, ONECHAR_UNKNOWN);
        result.string = ReplacementString();
        result->type = VT100_STRING;
    } else if (result->type != VT100_WAIT && !isAscii) {
        VT100ByteStreamCursor cursor = VT100ByteStreamConsumerGetCursor(consumer);
        result.string = VT100ByteStreamCursorMakeString(&cursor, consumedCount, encoding);

        if (result.string == nil) {
            // Invalid bytes, can't encode.
            int i;
            if (encoding == NSUTF8StringEncoding) {
                // I am 98% sure this is unreachable because the UTF-8 decoder isn't buggy enough
                // to claim success but then leave us unable to create an NSString from it.
                result.string = [@"\uFFFD" stringRepeatedTimes:consumedCount];
            } else {
                // Replace every byte with ?, the replacement char for non-unicode encodings.
                for (i = consumedCount - 1; i >= 0 && !result.string; i--) {
                    VT100ByteStreamCursorWrite(&cursor, ONECHAR_UNKNOWN);
                    result.string = VT100ByteStreamCursorMakeString(&cursor, consumedCount, encoding);
                }
            }
        }
    }
}
