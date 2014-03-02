//
//  VT100CSIParser.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Foundation/Foundation.h>
#import "VT100Token.h"

typedef enum {
    kIncidentalRingBell,
    kIncidentalBackspace,
    kIncidentalAppendTabAtCursor,
    kIncidentalLineFeed,
    kIncidentalCarriageReturn,
    kIncidentalDeleteCharacterAtCursor
} VT100CSIIncidentalType;

static BOOL isCSI(unsigned char *code, int len) {
    if (len >= 2 && code[0] == ESC && (code[1] == '[')) {
        return YES;
    }
    return NO;
}

@interface VT100CSIIncidental : NSObject

@property(nonatomic, readonly) VT100CSIIncidentalType type;
@property(nonatomic, assign) int intValue;

+ (VT100CSIIncidental *)ringBell;
+ (VT100CSIIncidental *)backspace;
+ (VT100CSIIncidental *)appendTabAtCursor;
+ (VT100CSIIncidental *)lineFeed;
+ (VT100CSIIncidental *)carriageReturn;
+ (VT100CSIIncidental *)deleteCharacterAtCursor:(int)n;

@end

@interface VT100CSIParser : NSObject

+ (void)decodeBytes:(unsigned char *)datap
             length:(int)datalen
          bytesUsed:(int *)rmlen
        incidentals:(NSMutableArray *)incidentals
              token:(VT100TCC *)result;

@end

