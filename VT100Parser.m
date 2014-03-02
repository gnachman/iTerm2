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

#define kDefaultStreamSize 100000

@implementation VT100Parser {
    unsigned char *_stream;
    int _currentStreamLength;
    int _totalStreamLength;
    int _streamOffset;
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
    [super dealloc];
}

- (BOOL)parseNextToken:(VT100TCC *)token incidentals:(NSMutableArray *)incidentals {
    unsigned char *datap;
    int datalen;
    
    token->isControl = NO;
    // get our current position in the stream
    datap = _stream + _streamOffset;
    datalen = _currentStreamLength - _streamOffset;
    
    if (datalen == 0) {
        token->type = VT100CC_NULL;
        token->length = 0;
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
        if (isAsciiString(datap)) {
            [VT100StringParser decodeBytes:datap
                                    length:datalen
                                 bytesUsed:&rmlen
                                     token:token
                                  encoding:self.encoding];
            token->length = rmlen;
            token->position = datap;
        } else if (iscontrol(datap[0])) {
            [VT100ControlParser decodeBytes:datap
                                     length:datalen
                                  bytesUsed:&rmlen
                                incidentals:incidentals
                                      token:token
                                   encoding:self.encoding];
            token->length = rmlen;
            token->position = datap;
            token->isControl = YES;
        } else {
            if (isString(datap, self.encoding)) {
                [VT100StringParser decodeBytes:datap
                                        length:datalen
                                     bytesUsed:&rmlen
                                         token:token
                                      encoding:self.encoding];
                // If the encoding is UTF-8 then you get here only if *datap >= 0x80.
                if (token->type != VT100_WAIT && rmlen == 0) {
                    token->type = VT100_UNKNOWNCHAR;
                    token->u.code = datap[0];
                    rmlen = 1;
                }
            } else {
                // If the encoding is UTF-8 you shouldn't get here.
                token->type = VT100_UNKNOWNCHAR;
                token->u.code = datap[0];
                rmlen = 1;
            }
            token->length = rmlen;
            token->position = datap;
        }
        
        
        if (rmlen > 0) {
            NSParameterAssert(_currentStreamLength >= _streamOffset + rmlen);
            // mark our current position in the stream
            _streamOffset += rmlen;
            assert(_streamOffset >= 0);
        }
    }
    
    if (gDebugLogging) {
        NSMutableString *loginfo = [NSMutableString string];
        NSMutableString *ascii = [NSMutableString string];
        int i = 0;
        int start = 0;
        while (i < token->length) {
            unsigned char c = datap[i];
            [loginfo appendFormat:@"%02x ", (int)c];
            [ascii appendFormat:@"%c", (c>=32 && c<128) ? c : '.'];
            if (i == token->length - 1 || loginfo.length > 60) {
                DebugLog([NSString stringWithFormat:@"Bytes %d-%d of %d: %@ (%@)", start, i, (int)token->length, loginfo, ascii]);
                [loginfo setString:@""];
                [ascii setString:@""];
                start = i;
            }
            i++;
        }
    }
    
    return token->type != VT100_WAIT && token->type != VT100CC_NULL;
}

- (void)putStreamData:(const char *)buffer length:(int)length {
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

- (NSData *)streamData {
    return [NSData dataWithBytes:_stream + _streamOffset
                          length:_currentStreamLength - _streamOffset];
}

- (void)clearStream {
    _streamOffset = _currentStreamLength;
    assert(_streamOffset >= 0);
}

@end
