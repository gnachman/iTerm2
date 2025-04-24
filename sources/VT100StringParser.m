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

static void DecodeUTF8Bytes(VT100ByteStreamCursor cursor,
                            int *rmlen,
                            VT100Token *token) {
    int utf8DecodeResult;
    int consumed = 0;

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
        *rmlen = consumed;
        assert(consumed >= 0);
        token->type = VT100_STRING;
    } else {
        // Report error or waiting state.
        if (utf8DecodeResult == 0) {
            token->type = VT100_WAIT;
        } else {
            *rmlen = -utf8DecodeResult;
            token->type = VT100_INVALID_SEQUENCE;
        }
    }
}


static void DecodeEUCCNBytes(VT100ByteStreamCursor cursor,
                             int *rmlen,
                             VT100Token *token) {
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
        *rmlen = 0;
        token->type = VT100_WAIT;
    } else {
        *rmlen = consumed;
        token->type = VT100_STRING;
    }
}

static void DecodeBIG5Bytes(VT100ByteStreamCursor cursor,
                            int *rmlen,
                            VT100Token *token)
{
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
        *rmlen = 0;
        token->type = VT100_WAIT;
    } else {
        *rmlen = consumed;
        token->type = VT100_STRING;
    }
}

static void DecodeEUCJPBytes(VT100ByteStreamCursor cursor,
                             int *rmlen,
                             VT100Token *token)
{
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
        *rmlen = 0;
        token->type = VT100_WAIT;
    } else {
        *rmlen = consumed;
        token->type = VT100_STRING;
    }
}


static void DecodeSJISBytes(VT100ByteStreamCursor cursor,
                            int *rmlen,
                            VT100Token *token) {
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
        *rmlen = 0;
        token->type = VT100_WAIT;
    } else {
        *rmlen = consumed;
        token->type = VT100_STRING;
    }
}

static void DecodeEUCKRBytes(VT100ByteStreamCursor cursor,
                             int *rmlen,
                             VT100Token *token) {
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
        *rmlen = 0;
        token->type = VT100_WAIT;
    } else {
        *rmlen = consumed;
        token->type = VT100_STRING;
    }
}

static void DecodeCP949Bytes(VT100ByteStreamCursor cursor,
                             int *rmlen,
                             VT100Token *token) {
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
        *rmlen = 0;
        token->type = VT100_WAIT;
    } else {
        *rmlen = consumed;
        token->type = VT100_STRING;
    }
}

static void DecodeOtherBytes(VT100ByteStreamCursor cursor,
                             int *rmlen,
                             VT100Token *token) {
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
        *rmlen = 0;
        token->type = VT100_WAIT;
    } else {
        *rmlen = consumed;
        token->type = VT100_STRING;
    }
}

// The datap buffer must be two bytes larger than *lenPtr.
// Returns a string or nil if the array is not well formed UTF-8.
static NSString* SetReplacementCharInArray(unsigned char* datap, int* lenPtr, int badIndex)
{
    // Example: "q?x" with badIndex==1.
    // 01234
    // q?x
    memmove(datap + badIndex + 3, datap + badIndex + 1, *lenPtr - badIndex - 1);
    // 01234
    // q?  x
    const char kUtf8Replacement[] = { 0xEF, 0xBF, 0xBD };
    memmove(datap + badIndex, kUtf8Replacement, 3);
    // q###x
    *lenPtr += 2;
    return [[[NSString alloc] initWithBytes:datap
                                     length:*lenPtr
                                   encoding:NSUTF8StringEncoding] autorelease];
}

static void DecodeASCIIBytes(VT100ByteStreamCursor cursor,
                             int *rmlen,
                             VT100Token *token) {
    int consumed = 0;

    // I tried the ideas mentioned here:
    // http://stackoverflow.com/questions/22218605/is-this-function-a-good-candidate-for-simd-on-intel
    // (using 8-bytes-at-a-time bit twiddling and SIMD)
    // and although this while loop completed faster, the overall benchmark speed on spam.cc did
    // not improve.
    while (VT100ByteStreamCursorGetSize(&cursor) > 0) {
        unsigned char c = VT100ByteStreamCursorPeek(&cursor);
        if (c >= 0x20 && c <= 0x7f) {
            VT100ByteStreamCursorAdvance(&cursor, 1);
            consumed++;
        } else {
            break;
        }
    }

    if (consumed == 0) {
        *rmlen = 0;
        token->type = VT100_WAIT;
    } else {
        *rmlen = consumed;
        token->type = VT100_ASCIISTRING;
    }
}

void ParseString(VT100ByteStreamCursor cursor,
                 int *rmlen,
                 VT100Token *result,
                 NSStringEncoding encoding) {
    *rmlen = 0;
    result->type = VT100_UNKNOWNCHAR;
    result->code = VT100ByteStreamCursorPeek(&cursor);

    BOOL isAscii = NO;
    if (isAsciiString(VT100ByteStreamCursorPeek(&cursor))) {
        isAscii = YES;
        DecodeASCIIBytes(cursor, rmlen, result);
        encoding = NSASCIIStringEncoding;
    } else if (encoding == NSUTF8StringEncoding) {
        DecodeUTF8Bytes(cursor, rmlen, result);
    } else if (isEUCCNEncoding(encoding)) {
        // Chinese-GB
        DecodeEUCCNBytes(cursor, rmlen, result);
    } else if (isBig5Encoding(encoding)) {
        DecodeBIG5Bytes(cursor, rmlen, result);
    } else if (isJPEncoding(encoding)) {
        DecodeEUCJPBytes(cursor, rmlen, result);
    } else if (isSJISEncoding(encoding)) {
        DecodeSJISBytes(cursor, rmlen, result);
    } else if (isEUCKREncoding(encoding)) {
        // korean
        DecodeEUCKRBytes(cursor, rmlen, result);
    } else if (isCP949Encoding(encoding)) {
        // korean
        DecodeCP949Bytes(cursor, rmlen, result);
    } else {
        DecodeOtherBytes(cursor, rmlen, result);
    }

    if (result->type == VT100_INVALID_SEQUENCE) {
        // Output only one replacement symbol, even if rmlen is higher.
        DLog(@"Parsed an invalid sequence of length %d for encoding %@: %@", *rmlen, @(encoding), VT100ByteStreamCursorDescription(&cursor));
        VT100ByteStreamCursorWrite(&cursor, ONECHAR_UNKNOWN);
        result.string = ReplacementString();
        result->type = VT100_STRING;
    } else if (result->type != VT100_WAIT && !isAscii) {
        result.string = VT100ByteStreamCursorMakeString(&cursor, *rmlen, encoding);

        if (result.string == nil) {
            // Invalid bytes, can't encode.
            int i;
            if (encoding == NSUTF8StringEncoding) {
                unsigned char temp[*rmlen * 3];
                VT100ByteStreamCursorCopy(&cursor, temp, *rmlen);

                int length = *rmlen;
                // Replace every byte with unicode replacement char <?>.
                for (i = *rmlen - 1; i >= 0 && !result.string; i--) {
                    result.string = SetReplacementCharInArray(temp, &length, i);
                }
            } else {
                // Replace every byte with ?, the replacement char for non-unicode encodings.
                for (i = *rmlen - 1; i >= 0 && !result.string; i--) {
                    VT100ByteStreamCursorWrite(&cursor, ONECHAR_UNKNOWN);
                    result.string = VT100ByteStreamCursorMakeString(&cursor, *rmlen, encoding);
                }
            }
        }
    }
}
