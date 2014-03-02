//
//  VT100ControlParser.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Foundation/Foundation.h>
#import "VT100Token.h"

static BOOL iscontrol(int c) {
    return c <= 0x1f;
}

@interface VT100ControlParser : NSObject

+ (void)decodeBytes:(unsigned char *)datap
             length:(int)datalen
          bytesUsed:(int *)rmlen
        incidentals:(NSMutableArray *)incidentals
              token:(VT100TCC *)token
           encoding:(NSStringEncoding)encoding;

@end
