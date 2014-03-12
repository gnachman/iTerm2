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

void ParseControl(unsigned char *datap,
                  int datalen,
                  int *rmlen,
                  CVector *incidentals,
                  VT100Token *token,
                  NSStringEncoding encoding);

@end
