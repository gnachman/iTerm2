//
//  iTermWebSocketFrame.m
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import "iTermWebSocketFrame.h"
#import "DebugLogging.h"

#define ILog ELog

@interface iTermWebSocketFrame()
@property (nonatomic, readwrite) BOOL fin;
@property (nonatomic, readwrite) iTermWebSocketOpcode opcode;
@property (nonatomic, copy) NSData *payload;
@end

@implementation iTermWebSocketFrame {
    NSData *_data;
}

+ (instancetype)closeFrame {
    iTermWebSocketFrame *frame = [[iTermWebSocketFrame alloc] init];
    frame.fin = YES;
    frame.opcode = iTermWebSocketOpcodeConnectionClose;
    return frame;
}

+ (instancetype)closeFrameWithCode:(uint16_t)code reason:(NSString *)reason {
    iTermWebSocketFrame *frame = [[iTermWebSocketFrame alloc] init];
    frame.fin = YES;
    frame.opcode = iTermWebSocketOpcodeConnectionClose;
    uint16_t networkCode = htons(code);
    NSMutableData *payload = [NSMutableData dataWithBytes:&networkCode length:sizeof(networkCode)];
    [payload appendData:[reason dataUsingEncoding:NSUTF8StringEncoding]];
    frame.payload = payload;

    if (frame.data.length > 125) {
        return nil;
    }
    return frame;
}

+ (instancetype)pingFrameWithData:(NSData *)data {
    iTermWebSocketFrame *frame = [[iTermWebSocketFrame alloc] init];
    frame.fin = YES;
    frame.opcode = iTermWebSocketOpcodePing;
    frame.payload = data;

    if (frame.data.length > 125) {
        return nil;
    }
    return frame;
}

+ (instancetype)pongFrameForPingFrame:(iTermWebSocketFrame *)ping  {
    iTermWebSocketFrame *frame = [[iTermWebSocketFrame alloc] init];
    frame.fin = YES;
    frame.opcode = iTermWebSocketOpcodePong;
    frame.payload = ping.payload;

    if (frame.data.length > 125) {
        return nil;
    }
    return frame;
}

+ (instancetype)textFrameWithData:(NSData *)data {
    iTermWebSocketFrame *frame = [[iTermWebSocketFrame alloc] init];
    frame.fin = YES;
    frame.opcode = iTermWebSocketOpcodeText;
    frame.payload = data;
    return frame;
}

+ (instancetype)textFrameWithString:(NSString *)string {
    return [self textFrameWithData:[string dataUsingEncoding:NSUTF8StringEncoding]];
}

+ (instancetype)binaryFrameWithData:(NSData *)data {
    iTermWebSocketFrame *frame = [[iTermWebSocketFrame alloc] init];
    frame.fin = YES;
    frame.opcode = iTermWebSocketOpcodeBinary;
    frame.payload = data;
    return frame;
}

+ (instancetype)frameWithDataSource:(unsigned char *(^)(int64_t))dataSource {
    ILog(@"Reading a frame...");
    iTermWebSocketFrame *frame = [[iTermWebSocketFrame alloc] init];

    unsigned char *data;
    data = dataSource(1);
    if (!data) {
        return nil;
    }
    frame.fin = !!(data[0] & 0x80);
    frame.opcode = (data[0] & 0x0f);
    ILog(@"Frame without payload: %@", frame);

    NSInteger payloadLength = 0;
    data = dataSource(1);
    if (!data) {
        return nil;
    }
    BOOL mask = !!(data[0] & 0x80);

    payloadLength = (data[0] & 0x7f);
    if (payloadLength == 126) {
        ILog(@"Read medium length payload size");
        data = dataSource(2);
        if (!data) {
            return nil;
        }
        uint16_t networkLength;
        memmove(&networkLength, data, sizeof(networkLength));
        payloadLength = ntohs(networkLength);
    } else if (payloadLength == 127) {
        ILog(@"Read long payload size");
        data = dataSource(8);
        if (!data) {
            return nil;
        }
        uint64_t networkLength;
        memmove(&networkLength, data, sizeof(networkLength));
        payloadLength = ntohll(networkLength);
    }
    ILog(@"Payload length is %@", @(payloadLength));

    unsigned char maskingKey[4] = { 0 };
    if (mask) {
        ILog(@"Have mask");
        data = dataSource(4);
        if (!data) {
            return nil;
        }
        ILog(@"Mask is %@", [NSData dataWithBytes:data length:4]);
        memmove(maskingKey, data, 4);
    }

    data = dataSource(payloadLength);
    if (!data) {
        return nil;
    }
    if (mask) {
        for (int i = 0; i < payloadLength; i++) {
            data[i] ^= maskingKey[i & 3];
        }
    }
    frame.payload = [NSData dataWithBytes:data length:payloadLength];

    return frame;
}

- (NSString *)description {
    NSString *opcode;
    switch (_opcode) {
        case iTermWebSocketOpcodePing:
            opcode = @"ping";
            break;

        case iTermWebSocketOpcodePong:
            opcode = @"pong";
            break;

        case iTermWebSocketOpcodeText:
            opcode = @"text";
            break;

        case iTermWebSocketOpcodeBinary:
            opcode = @"binary";
            break;

        case iTermWebSocketOpcodeContinuation:
            opcode = @"continuation";
            break;

        case iTermWebSocketOpcodeConnectionClose:
            opcode = @"close";
            break;

        default:
            opcode = [@(_opcode) stringValue];
    }
    return [NSString stringWithFormat:@"<%@: %p opcode=%@ fin=%@ payloadLength=%@>",
            NSStringFromClass([self class]),
            self,
            opcode,
            _fin ? @"YES": @"NO",
            @(self.payload.length)];
}

- (NSData *)data {
    if (!self.fin) {
        return nil;
    }
    if (!_data) {
        ILog(@"Encoding frame %@", self);
        NSMutableData *data = [NSMutableData data];
        uint8_t byte = 0;
        if (self.fin) {
            ILog(@"Set fin bit");
            byte |= 0x80;
        }
        byte |= (self.opcode & 0x0f);
        [data appendBytes:&byte length:1];

        byte = 0;
        // We're a server so we never mask outgoing data. Mask bit won't get set here (would go in
        // high bit of 'byte').
        if (self.payload.length <= 125) {
            ILog(@"Payload is short so using 1 byte encoding");
            byte = self.payload.length;
            [data appendBytes:&byte length:1];
        } else if (self.payload.length <= 0xffff) {
            ILog(@"Medium length payload, using 3 byte encoding");
            byte = 126;
            [data appendBytes:&byte length:1];

            uint16_t payloadLength = htons(self.payload.length);
            [data appendBytes:&payloadLength length:sizeof(payloadLength)];
        } else {
            ILog(@"Long payload, using 9 byte encoding");
            byte = 127;
            [data appendBytes:&byte length:1];

            uint64_t payloadLength = htonll(self.payload.length);
            [data appendBytes:&payloadLength length:sizeof(payloadLength)];
        }
        ILog(@"Frame without payload: %@", data);

        // Do not encode masking key since we're a server.

        [data appendData:self.payload];
        _data = data;
    }
    return _data;
}

- (uint16_t)closeFrameCode {
    NSAssert(self.opcode = iTermWebSocketOpcodeConnectionClose, @"Not a close frame");
    if (self.payload.length < 2) {
        return 0;
    }
    uint16_t code;
    memmove(&code, self.payload.bytes, 2);
    return ntohs(code);
}

- (NSString *)closeFrameReason {
    NSAssert(self.opcode = iTermWebSocketOpcodeConnectionClose, @"Not a close frame");
    if (self.payload.length < 2) {
        return nil;
    }
    NSData *data = [self.payload subdataWithRange:NSMakeRange(2, self.payload.length - 2)];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (NSString *)text {
    NSAssert(self.opcode == iTermWebSocketOpcodeText, @"Not a text frame");
    return [[NSString alloc] initWithData:self.payload encoding:NSUTF8StringEncoding];
}

- (BOOL)appendFragment:(iTermWebSocketFrame *)fragment {
    if (fragment.opcode != iTermWebSocketOpcodeContinuation) {
        ELog(@"Fragment opcode not continuation");
        return NO;
    }
    if (!self.fin) {
        ELog(@"Appending fragment to finished frame");
        return NO;
    }

    ILog(@"Appending fragment to frame %@", self);

    self.fin = fragment.fin;
    @autoreleasepool {
        NSMutableData *temp = [self.payload mutableCopy];
        [temp appendData:fragment.payload];
        self.payload = temp;
    }
    ILog(@"Frame is now %@", self);

    return YES;
}

- (iTermWebSocketFrame *)fragmentFromStartWithPayloadLength:(uint64_t)length {
    ILog(@"Fragmenting frame by taking %@ bytes from start", @(length));
    iTermWebSocketFrame *first;
    if (length >= self.payload.length) {
        ILog(@"Payload not large enough to fragment");
        return nil;
    }
    if (self.opcode == iTermWebSocketOpcodeText) {
        first = [iTermWebSocketFrame textFrameWithData:[self.payload subdataWithRange:NSMakeRange(0, length)]];
    } else if (self.opcode == iTermWebSocketOpcodeBinary) {
        first = [iTermWebSocketFrame binaryFrameWithData:[self.payload subdataWithRange:NSMakeRange(0, length)]];
    } else {
        return nil;
    }
    self.payload = [self.payload subdataWithRange:NSMakeRange(length, self.payload.length - length)];
    ILog(@"Now have two frames: %@ and %@", first, self);
    return first;
}

@end
