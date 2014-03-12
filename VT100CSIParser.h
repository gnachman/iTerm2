//
//  VT100CSIParser.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Foundation/Foundation.h>
#import "CVector.h"
#import "VT100Token.h"

typedef enum {
    kIncidentalRingBell,
    kIncidentalBackspace,
    kIncidentalAppendTabAtCursor,
    kIncidentalLineFeed,
    kIncidentalCarriageReturn,
    kIncidentalDeleteCharacterAtCursor
} VT100CSIIncidentalType;

NS_INLINE BOOL isCSI(unsigned char *code, int len) {
    if (len >= 2 && code[0] == ESC && (code[1] == '[')) {
        return YES;
    }
    return NO;
}

@interface VT100CSIParser : NSObject

+ (void)decodeBytes:(unsigned char *)datap
             length:(int)datalen
          bytesUsed:(int *)rmlen
        incidentals:(CVector *)incidentals
              token:(VT100Token *)result;

@end

