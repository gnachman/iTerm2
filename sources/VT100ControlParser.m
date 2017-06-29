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
    if (_dcsParser.isHooked || isDCS(datap, datalen)) {
        [self parseDCSWithData:datap
                       datalen:datalen
                         rmlen:rmlen
                         token:token
                      encoding:encoding
                    savedState:savedState];
        *dcsHooked = self.dcsParser.isHooked;
    } else if (isCSI(datap, datalen)) {
        iTermParserContext context = iTermParserContextMake(datap, datalen);
        [VT100CSIParser decodeFromContext:&context
                              incidentals:incidentals
                                    token:token];
        *rmlen = context.rmlen;
    } else if (isXTERM(datap, datalen)) {
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
                
            default:
                token->type = *datap;
                *rmlen = 1;
                break;
        }
    }
}

- (void)startTmuxRecoveryMode {
    [_dcsParser startTmuxRecoveryMode];
}

@end
