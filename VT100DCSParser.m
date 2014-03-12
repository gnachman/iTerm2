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
    *rmlen=2;
    if (datalen >= 5) {
        if (!strncmp((char *)datap, "1000p", 5)) {
            result->type = DCS_TMUX;
            *rmlen += 5;
        } else {
            result->type = VT100_NOTSUPPORT;
        }
    }
}

@end
