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
#import "iTerm2SharedARC-Swift.h"

@interface VT100ControlParser ()
@property(nonatomic, retain) VT100DCSParser *dcsParser;
@end

@implementation VT100ControlParser

- (instancetype)init {
    self = [super init];
    if (self) {
        _dcsParser = [[VT100DCSParser alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_dcsParser release];
    [super dealloc];
}

- (BOOL)shouldUnhook:(NSString *)uniqueID {
    return [_dcsParser.uniqueID isEqualToString:uniqueID];
}

- (void)unhookDCS {
    [_dcsParser reset];
}

- (NSString *)hookDescription {
    return _dcsParser.hookDescription;
}

- (void)parseDCSWithData:(unsigned char *)datap
                 datalen:(int)datalen
                   rmlen:(int *)rmlen
                   token:(VT100Token *)token
                encoding:(NSStringEncoding)encoding
              savedState:(NSMutableDictionary *)savedState {
    iTermParserContext context = iTermParserContextMake(datap, datalen);
    [_dcsParser decodeFromContext:&context
                            token:token
                         encoding:encoding
                       savedState:savedState];
    *rmlen = context.rmlen;
}

- (BOOL)dcsHooked {
    return _dcsParser.isHooked;
}


- (void)parseControlWithData:(unsigned char *)datap
                     datalen:(int)datalen
                       rmlen:(int *)rmlen
                 incidentals:(CVector *)incidentals
                       token:(VT100Token *)token
                    encoding:(NSStringEncoding)encoding
                  savedState:(NSMutableDictionary *)savedState
                   dcsHooked:(BOOL *)dcsHooked {
    const BOOL support8BitControlCharacters = (encoding == NSASCIIStringEncoding || encoding == NSISOLatin1StringEncoding);
    if (_dcsParser.isHooked || isDCS(datap, datalen, support8BitControlCharacters)) {
        [self parseDCSWithData:datap
                       datalen:datalen
                         rmlen:rmlen
                         token:token
                      encoding:encoding
                    savedState:savedState];
        *dcsHooked = self.dcsParser.isHooked;
    } else if (isCSI(datap, datalen, support8BitControlCharacters)) {
        iTermParserContext context = iTermParserContextMake(datap, datalen);
        [VT100CSIParser decodeFromContext:&context
             support8BitControlCharacters:support8BitControlCharacters
                              incidentals:incidentals
                                    token:token];
        *rmlen = context.rmlen;
    } else if (isXTERM(datap, datalen, support8BitControlCharacters)) {
        iTermParserContext context = iTermParserContextMake(datap, datalen);
        [VT100XtermParser decodeFromContext:&context
                                incidentals:incidentals
                                      token:token
                                   encoding:encoding
                                 savedState:savedState];
        *rmlen = context.rmlen;
    } else if (isANSI(datap, datalen)) {
        [VT100AnsiParser decodeBytes:datap
                              length:datalen
                           bytesUsed:rmlen
                               token:token];
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

            case VT100CC_C1_IND:
                if (support8BitControlCharacters) {
                    token->type = VT100CSI_IND;
                    *rmlen = 1;
                    break;
                }
                // Fall through

            case VT100CC_C1_NEL:
                if (support8BitControlCharacters) {
                    token->type = VT100CSI_NEL;
                    *rmlen = 1;
                    break;
                }
                // Fall through

            case VT100CC_C1_HTS:
                if (support8BitControlCharacters) {
                    token->type = VT100CSI_HTS;
                    *rmlen = 1;
                    break;
                }
                // Fall through

            case VT100CC_C1_RI:
                if (support8BitControlCharacters) {
                    token->type = VT100CSI_RI;
                    *rmlen = 1;
                    break;
                }
                // Fall through

            case VT100CC_C1_SS2:
            case VT100CC_C1_SS3:
            case VT100CC_C1_SPA:
            case VT100CC_C1_EPA:
            case VT100CC_C1_SOS:
            case VT100CC_C1_DECID:
            case VT100CC_C1_PM:
                if (support8BitControlCharacters) {
                    token->type = VT100_NOTSUPPORT;
                    *rmlen = 1;
                    break;
                }
                // Fall through

            default:
                token->type = *datap;
                *rmlen = 1;
                break;
        }
    }
}

- (void)startTmuxRecoveryModeWithID:(NSString *)dcsID {
    [_dcsParser startTmuxRecoveryModeWithID:dcsID];
}

- (void)cancelTmuxRecoveryMode {
    [_dcsParser cancelTmuxRecoveryMode];
}

- (void)startConductorRecoveryModeWithID:(NSString *)dcsID {
    [_dcsParser startConductorRecoveryModeWithID:dcsID];
}

- (void)cancelConductorRecoveryMode {
    [_dcsParser cancelConductorRecoveryMode];
}

- (BOOL)dcsHookIsSSH {
    return _dcsParser.isHooked && [_dcsParser.hookDescription isEqualToString:[VT100ConductorParser hookDescription]];
}

@end
