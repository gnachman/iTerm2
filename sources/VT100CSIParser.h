//
//  VT100CSIParser.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Foundation/Foundation.h>
#import "CVector.h"
#import "iTermParser.h"
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
    return (len >= 2 && code[0] == VT100CC_ESC && (code[1] == '['));
}

@interface VT100CSIParser : NSObject

+ (void)decodeFromContext:(iTermParserContext *)context
              incidentals:(CVector *)incidentals
                    token:(VT100Token *)result;

@end

