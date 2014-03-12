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
                  NSStringEncoding encoding) {
    if (isCSI(datap, datalen)) {
        [VT100CSIParser decodeBytes:datap
                             length:datalen
                          bytesUsed:rmlen
                        incidentals:incidentals
                              token:token];
    } else if (isXTERM(datap, datalen)) {
        [VT100XtermParser decodeBytes:datap
                               length:datalen
                            bytesUsed:rmlen
                                token:token
                             encoding:encoding];
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
