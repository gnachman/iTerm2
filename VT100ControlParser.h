//
//  VT100ControlParser.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Foundation/Foundation.h>
#import "CVector.h"
#import "VT100Token.h"

NS_INLINE BOOL iscontrol(int c) {
    return c <= 0x1f;
}

@interface VT100ControlParser : NSObject

+ (void)decodeBytes:(unsigned char *)datap
             length:(int)datalen
          bytesUsed:(int *)rmlen
        incidentals:(CVector *)incidentals
              token:(VT100Token *)token
           encoding:(NSStringEncoding)encoding;

@end
