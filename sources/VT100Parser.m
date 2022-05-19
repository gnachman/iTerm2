//
//  VT100Parser.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "VT100Parser.h"

#import "DebugLogging.h"
#import "iTermMalloc.h"
#import "VT100ControlParser.h"
#import "VT100StringParser.h"

#define kDefaultStreamSize 100000

@interface VT100Parser()
// Nested parsers count their depth. This happens with ssh integration.
@property (nonatomic) int depth;
@end

@implementation VT100Parser {
    unsigned char *_stream;
    int _currentStreamLength;
    int _totalStreamLength;
    int _streamOffset;
    BOOL _saveData;
    NSMutableDictionary *_savedStateForPartialParse;
    VT100ControlParser *_controlParser;
    BOOL _dcsHooked;  // @synchronized(self)
    VT100Parser *_sshParser;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _totalStreamLength = kDefaultStreamSize;
        _stream = iTermMalloc(_totalStreamLength);
        _savedStateForPartialParse = [[NSMutableDictionary alloc] init];
        _controlParser = [[VT100ControlParser alloc] init];
    }
    return self;
}

- (void)dealloc {
    free(_stream);
    [_savedStateForPartialParse release];
    [_controlParser release];
    [_sshParser release];
    [super dealloc];
}

- (void)forceUnhookDCS:(NSString *)uniqueID {
    @synchronized (self) {
        if (uniqueID == nil || [_controlParser shouldUnhook:uniqueID]) {
            _dcsHooked = NO;
            [_controlParser unhookDCS];
        } else {
            [_sshParser forceUnhookDCS:uniqueID];
        }
    }
}

- (BOOL)addNextParsedTokensToVector:(CVector *)vector {
    unsigned char *datap;
    int datalen;

    VT100Token *token = [VT100Token token];
    token.string = nil;
    // get our current position in the stream
    datap = _stream + _streamOffset;
    datalen = _currentStreamLength - _streamOffset;
    DLog(@"Have %d bytes to parse", datalen);

    unsigned char *position = NULL;
    int length = 0;
    if (datalen == 0) {
        token->type = VT100CC_NULL;
        _streamOffset = 0;
        _currentStreamLength = 0;

        if (_totalStreamLength >= kDefaultStreamSize * 2) {
            // We are done with this stream. Get rid of it and allocate a new one
            // to avoid allowing this to grow too big.
            free(_stream);
            _totalStreamLength = kDefaultStreamSize;
            _stream = iTermMalloc(_totalStreamLength);
        }
    } else {
        int rmlen = 0;
        const NSStringEncoding encoding = self.encoding;
        const BOOL support8BitControlCharacters = (encoding == NSASCIIStringEncoding || encoding == NSISOLatin1StringEncoding);
        
        if (isAsciiString(datap) && !_dcsHooked) {
            ParseString(datap, datalen, &rmlen, token, encoding);
            position = datap;
        } else if (iscontrol(datap[0]) || _dcsHooked || (support8BitControlCharacters && isc1(datap[0]))) {
            [_controlParser parseControlWithData:datap
                                         datalen:datalen
                                           rmlen:&rmlen
                                     incidentals:vector
                                           token:token
                                        encoding:encoding
                                      savedState:_savedStateForPartialParse
                                       dcsHooked:&_dcsHooked];
            if (token->type != VT100_WAIT) {
                [_savedStateForPartialParse removeAllObjects];
            }
            // Some tokens have synchronous side-effects.
            switch (token->type) {
                case XTERMCC_SET_KVP:
                    if ([token.kvpKey isEqualToString:@"CopyToClipboard"]) {
                        _saveData = YES;
                    } else if ([token.kvpKey isEqualToString:@"EndCopy"]) {
                        _saveData = NO;
                    }
                    break;

                case SSH_OUTPUT: {
                    if (!_sshParser) {
                        _sshParser = [[VT100Parser alloc] init];
                        _sshParser.encoding = self.encoding;
                        _sshParser.depth = self.depth + 1;
                    }
                    NSData *data = token.savedData;
                    [_sshParser putStreamData:data.bytes length:data.length];
                    const int start = CVectorCount(vector);
                    [_sshParser addParsedTokensToVector:vector];
                    const int end = CVectorCount(vector);
                    const SSHInfo myInfo = {
                        .pid = token.csi->p[0],
                        .channel = token.csi->p[1],
                        .valid = 1,
                        .depth = self.depth
                    };
                    for (int i = start; i < end; i++) {
                        VT100Token *token = CVectorGet(vector, i);
                        SSHInfo sshInfo = token.sshInfo;
                        if (!sshInfo.valid) {
                            token.sshInfo = myInfo;
                        }
                    }
                    break;
                }

                case DCS_TMUX_CODE_WRAP: {
                    VT100Parser *tempParser = [[[VT100Parser alloc] init] autorelease];
                    tempParser.encoding = encoding;
                    NSData *data = [token.string dataUsingEncoding:encoding];
                    [tempParser putStreamData:data.bytes length:data.length];
                    [tempParser addParsedTokensToVector:vector];
                    break;
                }

                case ISO2022_SELECT_LATIN_1:
                    _encoding = NSISOLatin1StringEncoding;
                    break;

                case ISO2022_SELECT_UTF_8:
                    _encoding = NSUTF8StringEncoding;
                    break;

                default:
                    break;
            }
            position = datap;
        } else {
            if (isString(datap, encoding)) {
                ParseString(datap, datalen, &rmlen, token, encoding);
                // If the encoding is UTF-8 then you get here only if *datap >= 0x80.
                if (token->type != VT100_WAIT && rmlen == 0) {
                    token->type = VT100_UNKNOWNCHAR;
                    token->code = datap[0];
                    rmlen = 1;
                }
            } else {
                // If the encoding is UTF-8 you shouldn't get here.
                token->type = VT100_UNKNOWNCHAR;
                token->code = datap[0];
                rmlen = 1;
            }
            position = datap;
        }
        length = rmlen;


        if (rmlen > 0) {
            NSParameterAssert(_currentStreamLength >= _streamOffset + rmlen);
            // mark our current position in the stream
            _streamOffset += rmlen;
            assert(_streamOffset >= 0);
        }
    }

    token->savingData = _saveData;
    if (token->type != VT100_WAIT && token->type != VT100CC_NULL) {
        if (_saveData) {
            token.savedData = [NSData dataWithBytes:position length:length];
        }
        if (token->type == VT100_ASCIISTRING) {
            [token setAsciiBytes:(char *)position length:length];
        }

        if (gDebugLogging) {
            NSString *prefix = _controlParser.hookDescription;
            if (prefix) {
                prefix = [prefix stringByAppendingString:@" "];
            } else {
                prefix = @"";
            }
            NSMutableString *loginfo = [NSMutableString string];
            NSMutableString *ascii = [NSMutableString string];
            int i = 0;
            int start = 0;
            while (i < length) {
                unsigned char c = datap[i];
                [loginfo appendFormat:@"%02x ", (int)c];
                [ascii appendFormat:@"%c", (c >= 32 && c < 128) ? c : '.'];
                if (i == length - 1) {
                    DLog(@"%@Bytes %d-%d of %d: %@ (%@)", prefix, start, i, (int)length, loginfo, ascii);
                }
                i++;
            }
            DLog(@"%@Parsed as %@", prefix, token);
        }
        // Don't append the outer wrapper to the output. Earlier, it was unwrapped and the inner
        // tokens were already added.
        if (token->type != DCS_TMUX_CODE_WRAP && token->type != SSH_OUTPUT) {
            [token retain];
            CVectorAppend(vector, token);
        }
        return YES;
    }

    return NO;
}

- (void)putStreamData:(const char *)buffer length:(int)length {
    @synchronized(self) {
        if (_currentStreamLength + length > _totalStreamLength) {
            // Grow the stream if needed.
            int n = (length + _currentStreamLength) / kDefaultStreamSize;

            _totalStreamLength += n * kDefaultStreamSize;
            _stream = iTermRealloc(_stream, _totalStreamLength, 1);
        }

        memcpy(_stream + _currentStreamLength, buffer, length);
        _currentStreamLength += length;
        assert(_currentStreamLength >= 0);
        if (_currentStreamLength == 0) {
            _streamOffset = 0;
        }
    }
}

- (int)streamLength {
    @synchronized(self) {
        return _currentStreamLength - _streamOffset;
    }
}

- (NSData *)streamData {
    @synchronized(self) {
        return [NSData dataWithBytes:_stream + _streamOffset
                              length:_currentStreamLength - _streamOffset];
    }
}

- (void)clearStream {
    @synchronized(self) {
        _streamOffset = _currentStreamLength;
        assert(_streamOffset >= 0);
        [_sshParser clearStream];
    }
}

- (void)addParsedTokensToVector:(CVector *)vector {
    @synchronized(self) {
        while ([self addNextParsedTokensToVector:vector]) {
            // Nothing to do.
        }
    }
}

- (void)startTmuxRecoveryModeWithID:(NSString *)dcsID {
    @synchronized(self) {
        if (_sshParser) {
#warning TODO: This definitely doesn't work
            [_sshParser startTmuxRecoveryModeWithID:dcsID];
        } else {
            [_controlParser startTmuxRecoveryModeWithID:dcsID];
            _dcsHooked = YES;
        }
    }
}

- (void)cancelTmuxRecoveryMode {
    @synchronized(self) {
        if (_sshParser) {
#warning TODO: This definitely doesn't work
            [_sshParser cancelTmuxRecoveryMode];
        } else {
            [_controlParser cancelTmuxRecoveryMode];
            _dcsHooked = NO;
        }
    }
}

- (void)reset {
    @synchronized(self) {
        [_savedStateForPartialParse removeAllObjects];
        [self forceUnhookDCS:nil];
        [self clearStream];
        [_sshParser reset];
    }
}

@end
