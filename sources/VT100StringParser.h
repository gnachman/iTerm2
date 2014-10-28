//
//  VT100StringParser.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Foundation/Foundation.h>
#import "VT100Token.h"

// Code to detect if characters are properly encoded for each encoding.

// Traditional Chinese (Big5)
// 1st   0xa1-0xfe
// 2nd   0x40-0x7e || 0xa1-0xfe
//
// Simplifed Chinese (EUC_CN)
// 1st   0x81-0xfe
// 2nd   0x40-0x7e || 0x80-0xfe
#define iseuccn(c)   ((c) >= 0x81 && (c) <= 0xfe)
#define isbig5(c)    ((c) >= 0xa1 && (c) <= 0xfe)
#define issjiskanji(c)  (((c) >= 0x81 && (c) <= 0x9f) ||  \
                         ((c) >= 0xe0 && (c) <= 0xef))
#define iseuckr(c)   ((c) >= 0xa1 && (c) <= 0xfe)

// TODO: Do this less hackily! These encodings (I think) have constants defined in
// CFStringEncodingExt along with functions that convert from NSStringEncoding.
#define isGBEncoding(e)     ((e)==0x80000019 || (e)==0x80000421|| \
                             (e)==0x80000631 || (e)==0x80000632|| \
                             (e)==0x80000930)
#define isBig5Encoding(e)   ((e)==0x80000002 || (e)==0x80000423|| \
                             (e)==0x80000931 || (e)==0x80000a03|| \
                             (e)==0x80000a06)
#define isJPEncoding(e)     ((e)==0x80000001 || (e)==0x8||(e)==0x15)
#define isSJISEncoding(e)   ((e)==0x80000628 || (e)==0x80000a01)
#define isKREncoding(e)     ((e)==0x80000422 || (e)==0x80000003|| \
                             (e)==0x80000840 || (e)==0x80000940)

NS_INLINE BOOL isAsciiString(unsigned char *code) {
    return *code >= 0x20 && *code <= 0x7f;
}

NS_INLINE BOOL isString(unsigned char *code, NSStringEncoding encoding) {
    if (encoding == NSUTF8StringEncoding) {
        return (*code >= 0x80);
    } else if (isGBEncoding(encoding)) {
        return iseuccn(*code);
    } else if (isBig5Encoding(encoding)) {
        return isbig5(*code);
    } else if (isJPEncoding(encoding)) {
        return (*code == 0x8e || *code == 0x8f || (*code >= 0xa1 && *code <= 0xfe));
    } else if (isSJISEncoding(encoding)) {
        return *code >= 0x80;
    } else if (isKREncoding(encoding)) {
        return iseuckr(*code);
    } else if (*code >= 0x20) {
        return YES;
    }

    return NO;
}

void ParseString(unsigned char *datap,
                 int datalen,
                 int *rmlen,
                 VT100Token *result,
                 NSStringEncoding encoding);
