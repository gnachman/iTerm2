//
//  VT100AnsiParser.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Foundation/Foundation.h>
#import "VT100Token.h"

NS_INLINE BOOL isANSI(unsigned char *code, int len) {
    // Currently, we only support esc-c as an ANSI code (other ansi codes are CSI).
    if (len >= 2 && code[0] == VT100CC_ESC && code[1] == 'c') {
        return YES;
    }
    return NO;
}


@interface VT100AnsiParser : NSObject

+ (void)decodeBytes:(unsigned char *)datap
             length:(int)datalen
          bytesUsed:(int *)rmlen
              token:(VT100Token *)result;

@end

