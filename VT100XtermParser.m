//
//  VT100XtermParser.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "VT100XtermParser.h"

#define ADVANCE(datap, datalen, rmlen) do { datap++; datalen--; (*rmlen)++; } while (0)
#define kMaxTempBufferLength 1024

@implementation VT100XtermParser

+ (void)decodeBytes:(unsigned char *)datap
             length:(int)datalen
          bytesUsed:(int *)rmlen
              token:(VT100Token *)result
           encoding:(NSStringEncoding)encoding {
    int mode = 0;
    NSData *data;
    char tempBuffer[kMaxTempBufferLength] = { 0 };
    char *outputPointer = NULL;
    
    assert(datap != NULL);
    assert(datalen >= 2);
    *rmlen = 0;
    assert(*datap == ESC);
    ADVANCE(datap, datalen, rmlen);
    assert(*datap == ']');
    ADVANCE(datap, datalen, rmlen);
    
    if (datalen > 0 && isdigit(*datap)) {
        // read an integer from datap and store it in mode.
        int n = *datap - '0';
        ADVANCE(datap, datalen, rmlen);
        while (datalen > 0 && isdigit(*datap)) {
            // TODO(georgen): Handle integer overflow
            n = n * 10 + *datap - '0';
            ADVANCE(datap, datalen, rmlen);
        }
        mode = n;
    }
    BOOL unrecognized = NO;
    if (datalen > 0) {
        if (*datap != ';' && *datap != 'P') {
            // Bogus first char after "esc ] [number]". Consume up to and
            // including terminator and then return VT100_NOTSUPPORT.
            unrecognized = YES;
        } else {
            if (*datap == 'P') {
                mode = -1;
            }
            // Consume ';' or 'P'.
            ADVANCE(datap, datalen, rmlen);
        }
        BOOL str_end = NO;
        outputPointer = tempBuffer;
        // Search for the end of a ^G/ST terminated string (but see the note below about other ways to terminate it).
        while (datalen > 0) {
            // broken OSC (ESC ] P NRRGGBB) does not need any terminator
            if (mode == -1 && outputPointer - tempBuffer >= 7) {
                str_end = YES;
                break;
            }
            // A string control should be canceled by CAN or SUB.
            if (*datap == VT100CC_CAN || *datap == VT100CC_SUB) {
                ADVANCE(datap, datalen, rmlen);
                str_end = YES;
                unrecognized = YES;
                break;
            }
            // BEL terminator
            if (*datap == VT100CC_BEL) {
                ADVANCE(datap, datalen, rmlen);
                str_end = YES;
                break;
            }
            if (*datap == VT100CC_ESC) {
                if (datalen >= 2 && *(datap + 1) == ']') {
                    // if Esc + ] is present recursively, simply skip it.
                    //
                    // Example:
                    //
                    //    ESC ] 0 ; a b c ESC ] d e f BEL
                    //
                    // title string "abcdef" should be accepted.
                    //
                    ADVANCE(datap, datalen, rmlen);
                    ADVANCE(datap, datalen, rmlen);
                    continue;
                } else if (datalen >= 2 && *(datap + 1) == '\\') {
                    // if Esc + \ is present, terminate OSC successfully.
                    //
                    // Example:
                    //
                    //    ESC ] 0 ; a b c ESC '\\'
                    //
                    // title string "abc" should be accepted.
                    //
                    ADVANCE(datap, datalen, rmlen);
                    ADVANCE(datap, datalen, rmlen);
                    str_end = YES;
                    break;
                } else {
                    // otherwise, terminate OSC unsuccessfully and backtrack before ESC.
                    //
                    // Example:
                    //
                    //    ESC ] 0 ; a b c ESC c
                    //
                    // "abc" should be discarded.
                    // ESC c is also accepted and causes hard reset(RIS).
                    //
                    str_end = YES;
                    unrecognized = YES;
                    break;
                }
            }
            if ((mode == 50 || mode == 1337) &&
                *datap == ':' &&
                !memcmp(tempBuffer, "File=", MIN(outputPointer - tempBuffer, 5))) {
                // Long base-64 encoded part of code begins. Terminate the OSC so we don't have to
                // buffer the whole string here.
                ADVANCE(datap, datalen, rmlen);
                str_end = YES;
                break;
            } else if (outputPointer - tempBuffer < kMaxTempBufferLength) {
                // if 0 <= mode <=2 and current *datap is a control character, replace it with '?'.
                if ((*datap < 0x20 || *datap == 0x7f) && (mode == 0 || mode == 1 || mode == 2)) {
                    *outputPointer = '?';
                } else {
                    *outputPointer = *datap;
                }
                outputPointer++;
            }
            ADVANCE(datap, datalen, rmlen);
        }
        if (!str_end && datalen == 0) {
            // Ran out of data before terminator. Keep trying.
            *rmlen = 0;
        }
    } else {
        // No data yet, keep trying.
        *rmlen = 0;
    }
    
    if (!(*rmlen)) {
        result->type = VT100_WAIT;
    } else if (unrecognized) {
        // Found terminator but it's malformed.
        result->type = VT100_NOTSUPPORT;
    } else {
        data = [NSData dataWithBytes:tempBuffer length:outputPointer - tempBuffer];
        result.string = [[[NSString alloc] initWithData:data
                                               encoding:encoding] autorelease];
        switch (mode) {
            case -1:
                // Nonstandard Linux OSC P nrrggbb ST to change color palette
                // entry.
                result->type = XTERMCC_SET_PALETTE;
                break;
            case 0:
                result->type = XTERMCC_WINICON_TITLE;
                break;
            case 1:
                result->type = XTERMCC_ICON_TITLE;
                break;
            case 2:
                result->type = XTERMCC_WIN_TITLE;
                break;
            case 4:
                result->type = XTERMCC_SET_RGB;
                break;
            case 6:
                // This is not a real xterm code. It is from eTerm, which extended the xterm
                // protocol for its own purposes. We don't follow the eTerm protocol,
                // but we follow the template it set.
                // http://www.eterm.org/docs/view.php?doc=ref#escape
                result->type = XTERMCC_PROPRIETARY_ETERM_EXT;
                break;
            case 9:
                result->type = ITERM_GROWL;
                break;
            case 50:
            case 1337:
                // 50 is a nonstandard escape code implemented by Konsole.
                // xterm since started using it for setting the font, so 1337 is the preferred code
                // for this in iterm.
                // <Esc>]50;key=value^G
                // <Esc>]1337;key=value^G
                result->type = XTERMCC_SET_KVP;
                [self parseKeyValuePairInToken:result];
                break;
            case 52:
                // base64 copy/paste (OPT_PASTE64)
                result->type = XTERMCC_PASTE64;
                break;
            case 133:
                // FinalTerm proprietary codes
                result->type = XTERMCC_FINAL_TERM;
                break;
            default:
                result->type = VT100_NOTSUPPORT;
                break;
        }
    }
}

+ (void)parseKeyValuePairInToken:(VT100Token *)token {
    // argument is of the form key=value
    // key: Sequence of characters not = or ^G
    // value: Sequence of characters not ^G
    NSString* argument = token.string;
    NSRange eqRange = [argument rangeOfString:@"="];
    NSString* key;
    NSString* value;
    if (eqRange.location != NSNotFound) {
        key = [argument substringToIndex:eqRange.location];;
        value = [argument substringFromIndex:eqRange.location+1];
    } else {
        key = argument;
        value = @"";
    }
    
    token.kvpKey = key;
    token.kvpValue = value;
}

@end
