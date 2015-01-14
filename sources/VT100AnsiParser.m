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
        }
    }
}

@end
