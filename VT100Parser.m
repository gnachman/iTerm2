//
//  VT100Parser.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "VT100Parser.h"
#import "DebugLogging.h"
#import "VT100ControlParser.h"
#import "VT100StringParser.h"
#import "VT100TmuxParser.h"

#define kDefaultStreamSize 100000

@implementation VT100Parser {
    unsigned char *_stream;
    int _currentStreamLength;
    int _totalStreamLength;
    int _streamOffset;
    BOOL _saveData;
}

- (id)init {
    self = [super init];
    if (self) {
        _totalStreamLength = kDefaultStreamSize;
        _stream = malloc(_totalStreamLength);
    }
    return self;
}

- (void)dealloc {
    free(_stream);
    [_tmuxParser release];
    [super dealloc];
}

- (BOOL)addNextParsedTokensToVector:(CVector *)vector {
    unsigned char *datap;
    int datalen;

    VT100Token *token = [VT100Token token];
    token.string = nil;
    // get our current position in the stream
    datap = _stream + _streamOffset;
    datalen = _currentStreamLength - _streamOffset;
    
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
            _stream = malloc(_totalStreamLength);
        }
    } else {
        int rmlen = 0;
        VT100TmuxParser *tmuxParser = [self.tmuxParser retain];
        if (tmuxParser) {
            [tmuxParser decodeBytes:datap length:datalen bytesUsed:&rmlen token:token];
            [tmuxParser release];
            if (token->type == TMUX_EXIT) {
                self.tmuxParser = nil;
            }
        } else if (isAsciiString(datap)) {
            ParseString(datap, datalen, &rmlen, token, self.encoding);
            position = datap;
        } else if (iscontrol(datap[0])) {
            ParseControl(datap,
                         datalen,
                         &rmlen,
                         vector,
                         token,
                         self.encoding);
            if (token->type == XTERMCC_SET_KVP) {
                if ([token.kvpKey isEqualToString:@"CopyToClipboard"]) {
                    _saveData = YES;
                } else if ([token.kvpKey isEqualToString:@"EndCopy"]) {
                    _saveData = NO;
                }
            } else if (token->type == DCS_TMUX && !_tmuxParser) {
                self.tmuxParser = [[[VT100TmuxParser alloc] init] autorelease];
            }
            position = datap;
        } else {
            if (isString(datap, self.encoding)) {
                ParseString(datap, datalen, &rmlen, token, self.encoding);
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
            NSString *prefix = @"";
            if (_tmuxParser) {
                prefix = @"[TMUX GATEWAY] ";
            }
            NSMutableString *loginfo = [NSMutableString string];
            NSMutableString *ascii = [NSMutableString string];
            int i = 0;
            int start = 0;
            while (i < length) {
                unsigned char c = datap[i];
                [loginfo appendFormat:@"%02x ", (int)c];
                [ascii appendFormat:@"%c", (c >= 32 && c < 128) ? c : '.'];
                if (i == length - 1 || loginfo.length > 60) {
                    DLog(@"%@Bytes %d-%d of %d: %@ (%@)", prefix, start, i, (int)length, loginfo, ascii);
                }
                i++;
            }
            DLog(@"%@Parsed as %@", prefix, token);
        }

        CVectorAppend(vector, token);
        return YES;
    } else {
        [token recycleObject];
        return NO;
    }
}

- (void)putStreamData:(const char *)buffer length:(int)length {
    @synchronized(self) {
        if (_currentStreamLength + length > _totalStreamLength) {
            // Grow the stream if needed.
            int n = (length + _currentStreamLength) / kDefaultStreamSize;

            _totalStreamLength += n * kDefaultStreamSize;
            _stream = reallocf(_stream, _totalStreamLength);
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
    }
}

- (void)addParsedTokensToVector:(CVector *)vector {
    @synchronized(self) {
        while ([self addNextParsedTokensToVector:vector]) {
            // Nothing to do.
        }
    }
}


@end
