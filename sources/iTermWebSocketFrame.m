//
//  iTermWebSocketFrame.m
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import "iTermWebSocketFrame.h"

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
    iTermWebSocketFrame *frame = [[iTermWebSocketFrame alloc] init];

    unsigned char *data;
    data = dataSource(1);
    if (!data) {
        return nil;
    }
    frame.fin = !!(data[0] & 0x80);
    frame.opcode = (data[0] & 0x0f);

    NSInteger payloadLength = 0;
    data = dataSource(1);
    if (!data) {
        return nil;
    }
    BOOL mask = !!(data[0] & 0x80);

    payloadLength = (mask & 0x7f);
    if (payloadLength == 126) {
        data = dataSource(2);
        if (!data) {
            return nil;
        }
        uint16_t networkLength;
        memmove(&networkLength, data, sizeof(networkLength));
        payloadLength = ntohs(networkLength);
    } else if (payloadLength == 127) {
        data = dataSource(8);
        if (!data) {
            return nil;
        }
        uint64_t networkLength;
        memmove(&networkLength, data, sizeof(networkLength));
        payloadLength = ntohll(networkLength);
    }

    unsigned char maskingKey[4] = { 0 };
    if (mask) {
        data = dataSource(4);
        if (!data) {
            return nil;
        }
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

- (NSData *)data {
    if (!self.fin) {
        return nil;
    }
    if (!_data) {
        NSMutableData *data = [NSMutableData data];
        uint8_t byte = 0;
        if (self.fin) {
            byte |= 0x80;
        }
        byte |= (self.opcode & 0x0f);
        [data appendBytes:&byte length:1];

        byte = 0;
        // We're a server so we never mask outgoing data. Mask bit won't get set here.
        if (self.payload.length <= 125) {
            byte = self.payload.length;
            [data appendBytes:&byte length:1];
        } else if (self.payload.length <= 0xffff) {
            byte = 126;
            [data appendBytes:&byte length:1];

            uint16_t payloadLength = htons(self.payload.length);
            [data appendBytes:&payloadLength length:sizeof(payloadLength)];
        } else {
            byte = 127;
            [data appendBytes:&byte length:1];

            uint64_t payloadLength = htonll(self.payload.length);
            [data appendBytes:&payloadLength length:sizeof(payloadLength)];
        }

        // Do not encode masking key since we're a server.

        [data appendData:self.payload];
        _data = data;
    }
    return _data;
}

- (uint16_t)closeFrameCode {
    if (self.payload.length < 2) {
        return 0;
    }
    uint16_t code;
    memmove(&code, self.payload.bytes, 2);
    return ntohs(code);
}

- (NSString *)closeFrameReason {
    if (self.payload.length < 2) {
        return nil;
    }
    NSData *data = [self.payload subdataWithRange:NSMakeRange(2, self.payload.length - 2)];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (void)appendFragment:(iTermWebSocketFrame *)fragment {
    assert(fragment.opcode == iTermWebSocketOpcodeContinuation);
    assert(!self.fin);

    self.fin = fragment.fin;
    @autoreleasepool {
        NSMutableData *temp = [self.payload mutableCopy];
        [temp appendData:fragment.payload];
        self.payload = temp;
    }
}

- (iTermWebSocketFrame *)fragmentFromStartWithPayloadLength:(uint64_t)length {
    iTermWebSocketFrame *first;
    if (length >= self.payload.length) {
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
    return first;
}

@end
