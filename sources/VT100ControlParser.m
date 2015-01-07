//
//  VT100ControlParser.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "VT100ControlParser.h"
#import "VT100CSIParser.h"
#import "VT100XtermParser.h"
#import "VT100AnsiParser.h"
#import "VT100DCSParser.h"
#import "VT100OtherParser.h"

@implementation VT100ControlParser

void ParseControl(unsigned char *datap,
                  int datalen,
                  int *rmlen,
                  CVector *incidentals,
                  VT100Token *token,
                  NSStringEncoding encoding,
                  int tmuxCodeWrapCount,
                  NSMutableDictionary *savedState) {
    if (tmuxCodeWrapCount && datalen >= 2 && datap[0] == ESC && datap[1] == '\\') {
        token->type = DCS_END_TMUX_CODE_WRAP;
        *rmlen = 2;
        return;
    }
    if (isCSI(datap, datalen)) {
        [VT100CSIParser decodeBytes:datap
                             length:datalen
                          bytesUsed:rmlen
                        incidentals:incidentals
                              token:token];
    } else if (isXTERM(datap, datalen)) {
        iTermParserContext context = iTermParserContextMake(datap, datalen);
        [VT100XtermParser decodeFromContext:&context
                                      token:token
                                   encoding:encoding
                                 savedState:savedState];
        *rmlen = context.rmlen;
    } else if (isANSI(datap, datalen)) {
        [VT100AnsiParser decodeBytes:datap
                              length:datalen
                           bytesUsed:rmlen
                               token:token];
    } else if (isDCS(datap, datalen)) {
        [VT100DCSParser decodeBytes:datap
                             length:datalen
                          bytesUsed:rmlen
                              token:token
                           encoding:encoding];
    } else {
        NSCParameterAssert(datalen > 0);
        
        switch (*datap) {
            case VT100CC_NULL:
                token->type = VT100_SKIP;
                *rmlen = 0;
                while (datalen > 0 && *datap == '\0') {
                    ++datap;
                    --datalen;
                    ++*rmlen;
                }
                break;

            case VT100CC_ESC:
                if (datalen == 1) {
                    token->type = VT100_WAIT;
                } else {
                    [VT100OtherParser decodeBytes:datap
                                           length:datalen
                                        bytesUsed:rmlen
                                            token:token
                                         encoding:encoding];
                }
                break;
                
            default:
                token->type = *datap;
                *rmlen = 1;
                break;
        }
    }
}

@end
