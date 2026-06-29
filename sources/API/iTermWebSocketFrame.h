//
//  iTermWebSocketFrame.h
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import <Foundation/Foundation.h>

/*
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 +-+-+-+-+-------+-+-------------+-------------------------------+
 |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
 |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
 |N|V|V|V|       |S|             |   (if payload len==126/127)   |
 | |1|2|3|       |K|             |                               |
 +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
 |     Extended payload length continued, if payload len == 127  |
 + - - - - - - - - - - - - - - - +-------------------------------+
 |                               |Masking-key, if MASK set to 1  |
 +-------------------------------+-------------------------------+
 | Masking-key (continued)       |          Payload Data         |
 +-------------------------------- - - - - - - - - - - - - - - - +
 :                     Payload Data continued ...                :
 + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
 |                     Payload Data continued ...                |
 +---------------------------------------------------------------+
*/

typedef NS_ENUM(int, iTermWebSocketOpcode) {
    iTermWebSocketOpcodeContinuation = 0x0,
    iTermWebSocketOpcodeText = 0x1,
    iTermWebSocketOpcodeBinary = 0x2,

    // Control opcodes
    iTermWebSocketOpcodeConnectionClose = 0x8,
    iTermWebSocketOpcodePing = 0x9,
    iTermWebSocketOpcodePong = 0xa,
};

@interface iTermWebSocketFrame : NSObject
@property (nonatomic, readonly) BOOL fin;
@property (nonatomic, readonly) iTermWebSocketOpcode opcode;
@property (nonatomic, readonly) NSData *payload;
@property (nonatomic, readonly) NSString *text;
@property (nonatomic, readonly) NSData *data;

+ (instancetype)closeFrame;
+ (instancetype)closeFrameWithCode:(uint16_t)code reason:(NSString *)reason;
+ (instancetype)pingFrameWithData:(NSData *)data;
+ (instancetype)pongFrameForPingFrame:(iTermWebSocketFrame *)ping;
+ (instancetype)textFrameWithString:(NSString *)string;
+ (instancetype)binaryFrameWithData:(NSData *)data;
+ (instancetype)frameWithDataSource:(unsigned char *(^)(int64_t))dataSource;

// Valid if opcode is ConnectionClose
- (uint16_t)closeFrameCode;
- (NSString *)closeFrameReason;

- (BOOL)appendFragment:(iTermWebSocketFrame *)fragment;

@end
