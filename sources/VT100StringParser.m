//
//  VT100StringParser.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "VT100StringParser.h"
#import "NSStringITerm.h"
#import "ScreenChar.h"

static void DecodeUTF8Bytes(unsigned char *datap,
                            int datalen,
                            int *rmlen,
                            VT100Token *token)
{
    unsigned char *p = datap;
    int len = datalen;
    int utf8DecodeResult;
    int theChar = 0;
    
    while (true) {
        utf8DecodeResult = decode_utf8_char(p, len, &theChar);
        // Stop on error or end of stream.
        if (utf8DecodeResult <= 0) {
            break;
        }
        // Intentionally break out at ASCII characters. They are
        // processed separately, e.g. they might get converted into
        // line drawing characters.
        if (theChar < 0x80) {
            break;
        }
        p += utf8DecodeResult;
        len -= utf8DecodeResult;
    }
    
    if (p > datap) {
        // If some characters were successfully decoded, just return them
        // and ignore the error or end of stream for now.
        *rmlen = p - datap;
        assert(p >= datap);
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


static void DecodeEUCCNBytes(unsigned char *datap,
                             int datalen,
                             int *rmlen,
                             VT100Token *token)
{
    unsigned char *p = datap;
    int len = datalen;
    
    
    while (len > 0) {
        if (iseuccn(*p) && len > 1) {
            if ((*(p+1) >= 0x40 &&
                 *(p+1) <= 0x7e) ||
                (*(p+1) >= 0x80 &&
                 *(p+1) <= 0xfe)) {
                    p += 2;
                    len -= 2;
                } else {
                    *p = ONECHAR_UNKNOWN;
                    p++;
                    len--;
                }
        } else {
            break;
        }
    }
    if (len == datalen) {
        *rmlen = 0;
        token->type = VT100_WAIT;
    } else {
        *rmlen = datalen - len;
        token->type = VT100_STRING;
    }
}

static void DecodeBIG5Bytes(unsigned char *datap,
                            int datalen,
                            int *rmlen,
                            VT100Token *token)
{
    unsigned char *p = datap;
    int len = datalen;
    
    while (len > 0) {
        if (isbig5(*p) && len > 1) {
            if ((*(p+1) >= 0x40 &&
                 *(p+1) <= 0x7e) ||
                (*(p+1) >= 0xa1 &&
                 *(p+1)<=0xfe)) {
                    p += 2;
                    len -= 2;
                } else {
                    *p = ONECHAR_UNKNOWN;
                    p++;
                    len--;
                }
        } else {
            break;
        }
    }
    if (len == datalen) {
        *rmlen = 0;
        token->type = VT100_WAIT;
    } else {
        *rmlen = datalen - len;
        token->type = VT100_STRING;
    }
}

static void DecodeEUCJPBytes(unsigned char *datap,
                             int datalen,
                             int *rmlen,
                             VT100Token *token)
{
    unsigned char *p = datap;
    int len = datalen;
    
    while (len > 0) {
        if  (len > 1 && *p == 0x8e) {
            p += 2;
            len -= 2;
        } else if (len > 2  && *p == 0x8f ) {
            p += 3;
            len -= 3;
        } else if (len > 1 && *p >= 0xa1 && *p <= 0xfe ) {
            p += 2;
            len -= 2;
        } else {
            break;
        }
    }
    if (len == datalen) {
        *rmlen = 0;
        token->type = VT100_WAIT;
    } else {
        *rmlen = datalen - len;
        token->type = VT100_STRING;
    }
}


static void DecodeSJISBytes(unsigned char *datap,
                            int datalen,
                            int *rmlen,
                            VT100Token *token)
{
    unsigned char *p = datap;
    int len = datalen;
    
    while (len > 0) {
        if (issjiskanji(*p) && len > 1) {
            p += 2;
            len -= 2;
        } else if (*p>=0x80) {
            p++;
            len--;
        } else {
            break;
        }
    }
    
    if (len == datalen) {
        *rmlen = 0;
        token->type = VT100_WAIT;
    } else {
        *rmlen = datalen - len;
        token->type = VT100_STRING;
    }
}

static void DecodeEUCKRBytes(unsigned char *datap,
                             int datalen,
                             int *rmlen,
                             VT100Token *token)
{
    unsigned char *p = datap;
    int len = datalen;
    
    while (len > 0) {
        if (iseuckr(*p) && len > 1) {
            p += 2;
            len -= 2;
        } else {
            break;
        }
    }
    if (len == datalen) {
        *rmlen = 0;
        token->type = VT100_WAIT;
    } else {
        *rmlen = datalen - len;
        token->type = VT100_STRING;
    }
}

static void DecodeCP949Bytes(unsigned char *datap,
                             int datalen,
                             int *rmlen,
                             VT100Token *token)
{
    unsigned char *p = datap;
    int len = datalen;
    
    while (len > 0) {
        if (iscp949(*p) && len > 1) {
            p += 2;
            len -= 2;
        } else {
            break;
        }
    }
    if (len == datalen) {
        *rmlen = 0;
        token->type = VT100_WAIT;
    } else {
        *rmlen = datalen - len;
        token->type = VT100_STRING;
    }
}

static void DecodeOtherBytes(unsigned char *datap,
                             int datalen,
                             int *rmlen,
                             VT100Token *token)
{
    unsigned char *p = datap;
    int len = datalen;
    
    while (len > 0) {
        if (*p >= 0x80) {
            p++;
            len--;
        } else {
            break;
        }
    }
    if (len == datalen) {
        *rmlen = 0;
        token->type = VT100_WAIT;
    } else {
        *rmlen = datalen - len;
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

static void DecodeASCIIBytes(unsigned char *datap,
                             int datalen,
                             int *rmlen,
                             VT100Token *token) {
    unsigned char *p = datap;
    int len = datalen;
    
    // I tried the ideas mentioned here:
    // http://stackoverflow.com/questions/22218605/is-this-function-a-good-candidate-for-simd-on-intel
    // (using 8-bytes-at-a-time bit twiddling and SIMD)
    // and although this while loop completed faster, the overall benchmark speed on spam.cc did
    // not improve.
    while (len > 0) {
        if (*p >= 0x20 && *p <= 0x7f) {
            p++;
            len--;
        } else {
            break;
        }
    }
    if (len == datalen) {
        *rmlen = 0;
        token->type = VT100_WAIT;
    } else {
        *rmlen = datalen - len;
        assert(datalen >= len);
        token->type = VT100_ASCIISTRING;
    }
}

void ParseString(unsigned char *datap,
                 int datalen,
                 int *rmlen,
                 VT100Token *result,
                 NSStringEncoding encoding) {
    *rmlen = 0;
    result->type = VT100_UNKNOWNCHAR;
    result->code = datap[0];

    BOOL isAscii = NO;
    if (isAsciiString(datap)) {
        isAscii = YES;
        DecodeASCIIBytes(datap, datalen, rmlen, result);
        encoding = NSASCIIStringEncoding;
    } else if (encoding == NSUTF8StringEncoding) {
        DecodeUTF8Bytes(datap, datalen, rmlen, result);
    } else if (isEUCCNEncoding(encoding)) {
        // Chinese-GB
        DecodeEUCCNBytes(datap, datalen, rmlen, result);
    } else if (isBig5Encoding(encoding)) {
        DecodeBIG5Bytes(datap, datalen, rmlen, result);
    } else if (isJPEncoding(encoding)) {
        DecodeEUCJPBytes(datap, datalen, rmlen, result);
    } else if (isSJISEncoding(encoding)) {
        DecodeSJISBytes(datap, datalen, rmlen, result);
    } else if (isEUCKREncoding(encoding)) {
        // korean
        DecodeEUCKRBytes(datap, datalen, rmlen, result);
    } else if (isCP949Encoding(encoding)) {
        // korean
        DecodeCP949Bytes(datap, datalen, rmlen, result);
    } else {
        DecodeOtherBytes(datap, datalen, rmlen, result);
    }
    
    if (result->type == VT100_INVALID_SEQUENCE) {
        // Output only one replacement symbol, even if rmlen is higher.
        datap[0] = ONECHAR_UNKNOWN;
        result.string = ReplacementString();
        result->type = VT100_STRING;
    } else if (result->type != VT100_WAIT && !isAscii) {
        result.string = [[[NSString alloc] initWithBytes:datap
                                                    length:*rmlen
                                                  encoding:encoding] autorelease];
        if (result.string == nil) {
            // Invalid bytes, can't encode.
            int i;
            if (encoding == NSUTF8StringEncoding) {
                unsigned char temp[*rmlen * 3];
                memcpy(temp, datap, *rmlen);
                int length = *rmlen;
                // Replace every byte with unicode replacement char <?>.
                for (i = *rmlen - 1; i >= 0 && !result.string; i--) {
                    result.string = SetReplacementCharInArray(temp, &length, i);
                }
            } else {
                // Replace every byte with ?, the replacement char for non-unicode encodings.
                for (i = *rmlen - 1; i >= 0 && !result.string; i--) {
                    datap[i] = ONECHAR_UNKNOWN;
                    result.string = [[[NSString alloc] initWithBytes:datap
                                                                 length:*rmlen
                                                               encoding:encoding] autorelease];
                }
            }
        }
    }
}
