//
//  VT100AnsiParser.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "VT100AnsiParser.h"

@implementation VT100AnsiParser

+ (void)decodeBytes:(unsigned char *)datap
             length:(int)datalen
          bytesUsed:(int *)rmlen
              token:(VT100Token *)result {
    result->type = VT100_UNKNOWNCHAR;
    if (datalen >= 2 && datap[0] == VT100CC_ESC) {
        switch (datap[1]) {
            case 'c':
                result->type = ANSI_RIS;
                *rmlen = 2;
                break;

            case ' ':
                if (datalen < 3) {
                    result->type = VT100_WAIT;
                    return;
                }
                switch (datap[2]) {
                    case 'L':
                        result->type = ANSI_LEVEL1;
                        *rmlen = 3;
                        return;
                    case 'M':
                        result->type = ANSI_LEVEL2;
                        *rmlen = 3;
                        return;
                    case 'N':
                        result->type = ANSI_LEVEL3;
                        *rmlen = 3;
                        return;
                }
                result->type = VT100_NOTSUPPORT;
                *rmlen = 3;
                return;
        }
    }
}

@end
