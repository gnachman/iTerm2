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

NS_INLINE BOOL iseuccn(unsigned char c) {
    return (c >= 0x81 && c <= 0xfe);
}

NS_INLINE BOOL isbig5(unsigned char c) {
    return (c >= 0xa1 && c <= 0xfe);
}

NS_INLINE BOOL issjiskanji(unsigned char c) {
    return ((c >= 0x81 && c <= 0x9f) ||
            (c >= 0xe0 && c <= 0xef));
}

NS_INLINE BOOL iseuckr(unsigned char c) {
    return (c >= 0xa1 && c <= 0xfe);
}

NS_INLINE BOOL iscp949(unsigned char c) {
    return (c >= 0x81 && c <= 0xfe);
}

NS_INLINE BOOL isEUCCNEncoding(NSStringEncoding stringEncoding) {
    return (stringEncoding == (0x80000000 | kCFStringEncodingMacChineseSimp) ||
            stringEncoding == (0x80000000 | kCFStringEncodingDOSChineseSimplif) ||
            stringEncoding == (0x80000000 | kCFStringEncodingGBK_95) ||
            stringEncoding == (0x80000000 | kCFStringEncodingGB_18030_2000) ||
            stringEncoding == (0x80000000 | kCFStringEncodingEUC_CN));
}

NS_INLINE BOOL isBig5Encoding(NSStringEncoding stringEncoding) {
    return (stringEncoding == (0x80000000 | kCFStringEncodingMacChineseTrad) ||
            stringEncoding == (0x80000000 | kCFStringEncodingDOSChineseTrad) ||
            stringEncoding == (0x80000000 | kCFStringEncodingEUC_TW) ||
            stringEncoding == (0x80000000 | kCFStringEncodingBig5) ||
            stringEncoding == (0x80000000 | kCFStringEncodingBig5_HKSCS_1999));
}

NS_INLINE BOOL isJPEncoding(NSStringEncoding stringEncoding) {
    return (stringEncoding == (0x80000000 | kCFStringEncodingMacJapanese) ||
            stringEncoding == NSShiftJISStringEncoding ||
            stringEncoding == NSISO2022JPStringEncoding);
}

NS_INLINE BOOL isSJISEncoding(NSStringEncoding stringEncoding) {
    return (stringEncoding == (0x80000000 | kCFStringEncodingShiftJIS_X0213) ||
            stringEncoding == (0x80000000 | kCFStringEncodingShiftJIS));
}

NS_INLINE BOOL isEUCKREncoding(NSStringEncoding stringEncoding) {
    return (stringEncoding == (0x80000000 | kCFStringEncodingMacKorean) ||
            stringEncoding == (0x80000000 | kCFStringEncodingISO_2022_KR) ||
            stringEncoding == (0x80000000 | kCFStringEncodingEUC_KR));
}
NS_INLINE BOOL isCP949Encoding(NSStringEncoding stringEncoding) {
    return (stringEncoding == (0x80000000 | kCFStringEncodingDOSKorean));
}

NS_INLINE BOOL isAsciiString(unsigned char *code) {
    return *code >= 0x20 && *code <= 0x7f;
}

NS_INLINE BOOL isString(unsigned char *code, NSStringEncoding encoding) {
    if (encoding == NSUTF8StringEncoding) {
        return (*code >= 0x80);
    } else if (isEUCCNEncoding(encoding)) {
        return iseuccn(*code);
    } else if (isBig5Encoding(encoding)) {
        return isbig5(*code);
    } else if (isJPEncoding(encoding)) {
        return (*code == 0x8e || *code == 0x8f || (*code >= 0xa1 && *code <= 0xfe));
    } else if (isSJISEncoding(encoding)) {
        return *code >= 0x80;
    } else if (isEUCKREncoding(encoding)) {
        return iseuckr(*code);
    } else if (isCP949Encoding(encoding)) {
        return iscp949(*code);
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
