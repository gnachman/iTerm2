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
    // Key is pid
    NSMutableDictionary<NSNumber *, VT100Parser *> *_sshParsers;
    int _mainSSHParserPID;
    // for ssh conductor recovery. When true this causes the parser to emit a special token
    // that marks the first post-recovery token to be parsed.
    BOOL _emitRecoveryToken;
    NSInteger _nextBoundaryNumber;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _totalStreamLength = kDefaultStreamSize;
        _stream = iTermMalloc(_totalStreamLength);
        _savedStateForPartialParse = [[NSMutableDictionary alloc] init];
        _controlParser = [[VT100ControlParser alloc] init];
        _sshParsers = [[NSMutableDictionary alloc] init];
        _mainSSHParserPID = -1;
    }
    return self;
}

- (void)dealloc {
    free(_stream);
    [_savedStateForPartialParse release];
    [_controlParser release];
    [_sshParsers release];
    [super dealloc];
}

- (void)forceUnhookDCS:(NSString *)uniqueID {
    @synchronized (self) {
        if (uniqueID == nil || [_controlParser shouldUnhook:uniqueID]) {
            _dcsHooked = NO;
            [_controlParser unhookDCS];
        } else {
            // TOOD: Maybe do something with ssh parsers?
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

    if (_emitRecoveryToken) {
        VT100Token *recoveryToken = [VT100Token token];
        recoveryToken.type = SSH_RECOVERY_BOUNDARY;
        recoveryToken.csi->p[0] = _nextBoundaryNumber - 1;
        recoveryToken.csi->count = 1;
        [recoveryToken retain];
        CVectorAppend(vector, recoveryToken);
        _emitRecoveryToken = NO;
    }

    unsigned char *position = NULL;
    int length = 0;
    if (datalen == 0) {
        DLog(@"datalen is 0");
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
            DLog(@"%@: control parser produced %@", self, token);
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

                case SSH_TERMINATE: {
                    // TODO: Make sure we don't leak sshparsers when connections end
                    const int pid = token.csi->p[0];
                    DLog(@"Remove ssh parser for pid %@", @(pid));
                    [_sshParsers removeObjectForKey:@(pid)];
                    if (pid == _mainSSHParserPID) {
                        DLog(@"Lost main SSH process %d", pid);
                        _mainSSHParserPID = -1;
                    }
                    break;
                }

                case SSH_UNHOOK:
                    [_sshParsers removeAllObjects];
                    break;

                case SSH_OUTPUT: {
                    const int pid = token.csi->p[0];
                    DLog(@"%@: handling SSH_OUTPUT", self);
                    VT100Parser *sshParser = _sshParsers[@(pid)];
                    if (!sshParser) {
                        DLog(@"%@: I lack a parser for pid %@. Existing parsers:\n%@",
                              self,@(pid), _sshParsers);
                        if (_sshParsers.count == 0 && token.csi->p[1] == -1) {
                            DLog(@"Inferring %d is the main SSH process", pid);
                            _mainSSHParserPID = pid;
                        }
                        sshParser = [[[VT100Parser alloc] init] autorelease];
                        sshParser.encoding = self.encoding;
                        sshParser.depth = self.depth + 1;
                        DLog(@"%@: Allocate ssh parser %@", self, sshParser);
                        _sshParsers[@(pid)] = sshParser;
                    }
                    DLog(@"%@: Using child %@, begin reparsing SSH output in token %@ at depth %@: %@",
                          self, sshParser, token, @(self.depth), token.savedData);
                    NSData *data = token.savedData;
                    [sshParser putStreamData:data.bytes length:data.length];
                    const int start = CVectorCount(vector);
                    DLog(@"count before adding parsed tokens is %@", @(start));
                    [sshParser addParsedTokensToVector:vector];
                    const int end = CVectorCount(vector);
                    DLog(@"count after adding parsed tokens is %@", @(end));
                    const SSHInfo myInfo = {
                        .pid = pid,
                        .channel = token.csi->p[1],
                        .valid = 1,
                        .depth = self.depth
                    };
                    const SSHInfo childInfo = {
                        .pid = pid,
                        .channel = token.csi->p[1],
                        .valid = 1,
                        .depth = self.depth + 1
                    };
                    DLog(@"%@: reparsing yielded %d tokens", self, end - start);
                    for (int i = start; i < end; i++) {
                        VT100Token *token = CVectorGet(vector, i);
                        SSHInfo sshInfo = token.sshInfo;
                        if (!sshInfo.valid) {
                            DLog(@"%@: Update ssh info in rewritten token %@ to %@", self, token, SSHInfoDescription(myInfo));
                            switch (token.type) {
                                case SSH_OUTPUT:
                                    // VT100Parser cannot emit SSH_OUTPUT.
                                    assert(NO);
                                case SSH_INIT:
                                case SSH_LINE:
                                case SSH_UNHOOK:
                                case SSH_BEGIN:
                                case SSH_END:
                                case SSH_TERMINATE:
                                    // Meta-tokens, when emitted as the product of %output, belong
                                    // to the child but will not be properly marked up with ssh info.
                                    token.sshInfo = childInfo;
                                    break;
                                default:
                                    // Regular tokens (e.g., VT100_STRING) belong to this parser's
                                    // depth. The extra parser just decoded the output that belongs
                                    // to us.
                                    token.sshInfo = myInfo;
                                    break;
                            }
                        } else {
                            DLog(@"%@: Rewritten token %@ has valid SSH info %@ so not rewriting it",
                                  self, token, SSHInfoDescription(token.sshInfo));
                        }
                        DLog(@"%@: Emit subtoken %@ with info %@", self, token, SSHInfoDescription(token.sshInfo));
                    }
                    DLog(@"%@: done reparsing SSH output at depth %@", self, @(self.depth));
                    if (pid == SSH_OUTPUT_AUTOPOLL_PID|| pid == SSH_OUTPUT_NOTIF_PID) {
                        // No need to keep this around, especially since it may carry some state we don't want.
                        [_sshParsers removeObjectForKey:@(pid)];
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
    } else {
        DLog(@"unable to parse. Resulting token was %@", token);
    }

    return NO;
}

- (void)putStreamData:(const char *)buffer length:(int)length {
    @synchronized(self) {
        if (_currentStreamLength + length > _totalStreamLength) {
            // Grow the stream if needed. Don't grow too fast so the xterm parser can catch overflow.
            int n = MIN(500, (length + _currentStreamLength) / kDefaultStreamSize);

            // Make sure it grows enough to hold this.
            NSInteger proposedSize = _totalStreamLength;
            proposedSize += MAX(n * kDefaultStreamSize, length);
            if (proposedSize >= INT_MAX) {
                DLog(@"Stream too big!");
                return;
            }
            _totalStreamLength = proposedSize;
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
        [_sshParsers[@(_mainSSHParserPID)] clearStream];
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
        [_controlParser startTmuxRecoveryModeWithID:dcsID];
        _dcsHooked = YES;
    }
}

- (void)cancelTmuxRecoveryMode {
    @synchronized(self) {
        [_controlParser cancelTmuxRecoveryMode];
        _dcsHooked = NO;
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p dcsHooked=%@ depth=%@>",
            NSStringFromClass([self class]),
            self,
            @(_dcsHooked),
            @(_depth)];
}

// tree: [child pid: [dcs ID, tree]]
- (NSInteger)startConductorRecoveryModeWithID:(NSString *)dcsID tree:(NSDictionary *)tree {
    DLog(@"%@: startConductorRecoveryModeWithID:%@ tree:%@", self, dcsID, tree);
    [_sshParsers removeAllObjects];
    const NSInteger boundary = [self reallyStartConductorRecoveryModeWithID:dcsID tree:tree];
    DLog(@"After recovery:");
    [self printParsers:@""];
    return boundary;
}

- (void)printParsers:(NSString *)prefix {
    [_sshParsers enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, VT100Parser * _Nonnull obj, BOOL * _Nonnull stop) {
        DLog(@"%@%@", prefix, obj);
        [obj printParsers:[@"    " stringByAppendingString:prefix]];
    }];
}

- (NSInteger)reallyStartConductorRecoveryModeWithID:(NSString *)dcsID tree:(NSDictionary *)tree {
    DLog(@"%@: reallyStartConductorRecoveryModeWithID:%@ tree:%@", self, dcsID, tree);
    @synchronized (self) {
        if (tree.count == 0) {
            return _nextBoundaryNumber++;
        }
        if (tree[@0]) {
            // No special parsing needed by this node.
            NSArray *tuple = tree[@0];
            NSString *childDcsId = tuple[0];
            NSDictionary *childTree = tuple[1];
            [self startConductorRecoveryModeWithID:childDcsId tree:childTree];
            return _nextBoundaryNumber++;
        }
        [_controlParser startConductorRecoveryModeWithID:dcsID];
        _dcsHooked = YES;
        [self recoverWithConductorTree:tree];
        _emitRecoveryToken = YES;
        return _nextBoundaryNumber++;
    }
}

- (void)recoverWithConductorTree:(NSDictionary *)tree {
    for (NSNumber *childPID in tree) {
        NSArray *tuple = tree[childPID];
        NSString *childDcsId = tuple[0];
        NSDictionary *childTree = tuple[1];

        VT100Parser *childParser = [[[VT100Parser alloc] init] autorelease];
        childParser.encoding = self.encoding;
        childParser.depth = self.depth + 1;
        _sshParsers[childPID] = childParser;
        [childParser reallyStartConductorRecoveryModeWithID:childDcsId tree:childTree];
        DLog(@"%@: add recovered child parser with pid %@: %@", self, childPID, childParser);
    }
}

- (void)cancelConductorRecoveryMode {
    @synchronized(self) {
        // TODO: This doesn't attempt to handle nested conductors.
        [_controlParser cancelConductorRecoveryMode];
        _dcsHooked = NO;
    }
}

- (void)reset {
    @synchronized(self) {
        [_savedStateForPartialParse removeAllObjects];
        [self forceUnhookDCS:nil];
        [self clearStream];
        [_sshParsers[@(_mainSSHParserPID)] reset];
    }
}

- (void)resetExceptSSH {
    @synchronized(self) {
        [_savedStateForPartialParse removeAllObjects];
        if (!_controlParser.dcsHookIsSSH) {
            [self forceUnhookDCS:nil];
            [self clearStream];
            [_sshParsers[@(_mainSSHParserPID)] reset];
        }
    }
}

@end
