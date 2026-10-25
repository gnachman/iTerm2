//
//  VT100XtermParser.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Foundation/Foundation.h>
#import "iTermParser.h"
#import "CVector.h"
#import "VT100Token.h"

NS_INLINE BOOL isXTERM(unsigned char *code, int len, BOOL support8BitControlCharacters) {
    if (support8BitControlCharacters && len >= 1 && (code[0] == VT100CC_C1_OSC ||
                                                     code[0] == VT100CC_C1_APC)) {
        return YES;
    }
    return (len >= 2 && code[0] == VT100CC_ESC && (code[1] == ']' ||  // OSC
                                                   code[1] == '_'));  // APC
}

@interface VT100XtermParser : NSObject

+ (void)decodeFromContext:(iTermParserContext *)context
              incidentals:(CVector *)incidentals
                    token:(VT100Token *)result
                 encoding:(NSStringEncoding)encoding
               savedState:(NSMutableDictionary *)savedState;

// Whether an OSC 134 payload (what follows "134;") begins with an SSH framer notification
// header such as ":%output ". Command replies are not headers.
+ (BOOL)isFramerHeaderPayload:(const unsigned char *)bytes length:(NSUInteger)length;

@end
