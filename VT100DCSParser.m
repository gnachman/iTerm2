//
//  VT100DCSParser.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "VT100DCSParser.h"

@implementation VT100DCSParser

+ (void)decodeBytes:(unsigned char *)datap
             length:(int)datalen
          bytesUsed:(int *)rmlen
              token:(VT100Token *)result
           encoding:(NSStringEncoding)encoding {
    // DCS is kind of messy to parse, but we only support one code, so we just check if it's that.
    result->type = VT100_WAIT;
    // Can assume we have "ESC P" so skip past that.
    datap += 2;
    datalen -= 2;
    *rmlen = 2;
    if (datalen >= 2) {
        if (!strncmp((char *)datap, "+q", 2)) {
            datap += 2;
            datalen -= 2;
            *rmlen += 2;
            char st[3] = { ESC, '\\', '\0' };
            char *positionOfST = strnstr((const char *)datap, st, datalen);
            if (!positionOfST) {
                return;
            }
            int length = positionOfST - (char *)datap;
            *rmlen += length + 2;
            NSString *semicolonDelimitedHexEncodedNames =
                [NSString stringWithFormat:@"%.*s", length, (char *)datap];
            NSArray *hexEncodedNames =
                [semicolonDelimitedHexEncodedNames componentsSeparatedByString:@";"];
            result->type = DCS_REQUEST_TERMCAP_TERMINFO;
            result.csi->count = 0;
            NSDictionary *nameMap = [[self class] termcapTerminfoNameDictionary];
            for (NSString *hexEncodedName in hexEncodedNames) {
                NSString *name = [NSString stringWithHexEncodedString:hexEncodedName];
                NSNumber *value = nameMap[name];
                if (value) {
                    result.csi->p[result.csi->count++] = [value intValue];
                } else {
                    result.csi->p[result.csi->count++] = kDcsTermcapTerminfoRequestUnrecognizedName;
                }
                if (result.csi->count == VT100CSIPARAM_MAX) {
                    break;
                }
            }
            return;
        }
    }
    if (datalen >= 5) {
        if (!strncmp((char *)datap, "1000p", 5)) {
            result->type = DCS_TMUX;
            *rmlen += 5;
        } else {
            result->type = VT100_NOTSUPPORT;
        }
    }
}

+ (NSDictionary *)termcapTerminfoNameDictionary {
    return @{ @"TN": @(kDcsTermcapTerminfoRequestTerminalName),
              @"name": @(kDcsTermcapTerminfoRequestTerminfoName) };
}

+ (NSDictionary *)termcapTerminfoInverseNameDictionary {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSDictionary *dict = [self termcapTerminfoNameDictionary];
    for (NSString *key in dict) {
        id value = dict[key];
        result[value] = key;
    }
    return result;
}


@end
