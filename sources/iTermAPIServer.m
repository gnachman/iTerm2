//
//  iTermAPIServer.m
//  iTerm2
//
//  Created by George Nachman on 11/3/16.
//
//

#import "iTermAPIServer.h"

#import "DebugLogging.h"
#import "NSData+iTerm.h"
#import <CommonCrypto/CommonDigest.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/socket.h>
#include <sys/types.h>

static NSString *const kProtocolName = @"api.iterm2.com";

@interface iTermIPV4Address : NSObject
@property (nonatomic) in_addr_t address;
@property (nonatomic, readonly) in_addr_t networkByteOrderAddress;

- (instancetype)initWithString:(NSString *)address;
- (instancetype)initWithAnyAddress;
- (instancetype)initWithLoopback;
@end

@implementation iTermIPV4Address

- (instancetype)initWithAnyAddress {
    self = [super init];
    if (self) {
        _address = INADDR_ANY;
    }
    return self;
}

- (instancetype)initWithLoopback {
    self = [super init];
    if (self) {
        _address = INADDR_LOOPBACK;
    }
    return self;
}

- (instancetype)initWithString:(NSString *)address {
    self = [super init];
    if (self) {
        if (!inet_pton(AF_INET, address.UTF8String, &_address)) {
            return nil;
        }
    }
    return self;
}

- (in_addr_t)networkByteOrderAddress {
    return htonl(_address);
}

@end

@interface iTermSocketAddress : NSObject<NSCopying>
@property (nonatomic, readonly) struct sockaddr *sockaddr;
@property (nonatomic, readonly) socklen_t sockaddrSize;

+ (instancetype)socketAddressWithIPV4Address:(iTermIPV4Address *)address port:(uint16_t)port;

@end

@interface iTermSocketIPV4Address : iTermSocketAddress
- (instancetype)initWithIPV4Address:(iTermIPV4Address *)address port:(uint16_t)port;
@end

@implementation iTermSocketIPV4Address {
    struct sockaddr_in _sockaddr;
}

- (instancetype)initWithIPV4Address:(iTermIPV4Address *)address port:(uint16_t)port {
    self = [super init];
    if (self) {
        _sockaddr.sin_family = AF_INET;
        _sockaddr.sin_addr.s_addr = address.networkByteOrderAddress;
        _sockaddr.sin_port = htons(port);
    }
    return self;
}

- (struct sockaddr *)sockaddr {
    return (struct sockaddr *)&_sockaddr;
}

- (socklen_t)sockaddrSize {
    return (socklen_t)sizeof(_sockaddr);
}

- (id)copyWithZone:(NSZone *)zone {
    iTermSocketIPV4Address *other = [[iTermSocketIPV4Address alloc] init];
    if (other) {
        other->_sockaddr = _sockaddr;
    }
    return other;
}

@end

@implementation iTermSocketAddress

+ (instancetype)socketAddressWithIPV4Address:(iTermIPV4Address *)address port:(uint16_t)port {
    return [[iTermSocketIPV4Address alloc] initWithIPV4Address:address port:port];
}

- (id)copyWithZone:(NSZone *)zone {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

@end

@interface iTermSocket : NSObject
@property (nonatomic, readonly) int fd;
- (void)setReuseAddr:(BOOL)reuse;
- (BOOL)bindToAddress:(iTermSocketAddress *)address;
- (BOOL)listenWithBacklog:(int)backlog accept:(void (^)(int, iTermSocketAddress *))acceptBlock;
@end

@implementation iTermSocket {
    int _addressFamily;
    int _socketType;
    iTermSocketAddress *_boundAddress;
    dispatch_queue_t _acceptQueue;
}

+ (instancetype)tcpIPV4Socket {
    return [[[self alloc] initWithAddressFamily:AF_INET socketType:SOCK_STREAM] autorelease];
}

- (instancetype)initWithAddressFamily:(int)addressFamily
                           socketType:(int)socketType {
    self = [super init];
    if (self) {
        _addressFamily = addressFamily;
        _socketType = socketType;
        _fd = socket(_addressFamily, _socketType, 0);
        if (_fd < 0) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    if (_fd >= 0) {
        close(_fd);
    }
    [_boundAddress release];
    if (_acceptQueue) {
        dispatch_release(_acceptQueue);
    }
    [super dealloc];
}

- (void)setReuseAddr:(BOOL)reuse {
    int optionValue = reuse ? 1 : 0;
    setsockopt(_fd,
               SOL_SOCKET,
               SO_REUSEADDR,
               (const void *)&optionValue,
               sizeof(optionValue));
}

- (BOOL)bindToAddress:(iTermSocketAddress *)address {
    if (bind(_fd, address.sockaddr, address.sockaddrSize) == 0) {
        [_boundAddress release];
        _boundAddress = [address copy];
        return YES;
    }
    return NO;
}

- (BOOL)listenWithBacklog:(int)backlog accept:(void (^)(int, iTermSocketAddress *))acceptBlock {
    if (listen(_fd, backlog) < 0) {
        return NO;
    }

    if (!_acceptQueue) {
        _acceptQueue = dispatch_queue_create("com.iterm2.accept", NULL);
    };

    int fd = _fd;
    dispatch_async(_acceptQueue, ^{
        while (1) {
            @autoreleasepool {
                iTermSocketAddress *clientSocketAddress = [[[_boundAddress class] alloc] init];
                socklen_t clientAddressLength = clientSocketAddress.sockaddrSize;
                int acceptFd = accept(fd, clientSocketAddress.sockaddr, &clientAddressLength);
                if (acceptFd < 0) {
                    if (errno == EINTR || errno == EWOULDBLOCK) {
                        continue;
                    } else {
                        ELog(@"Accept failed with %s", strerror(errno));
                        return;
                    }
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    acceptBlock(acceptFd, clientSocketAddress);
                });
            }
        }
    });
    return YES;
}

@end

@class iTermAPIServerConnection;

@interface iTermAPIServerConnection : NSObject

- (instancetype)initWithFileDescriptor:(int)fd clientAddress:(iTermSocketAddress *)address;
- (NSURLRequest *)readRequest;
- (void)sendResultCode:(int)code;
- (void)close;

@end

@implementation iTermAPIServerConnection {
    int _fd;
    iTermSocketAddress *_clientAddress;
    NSURLRequest *_request;
    NSTimeInterval _deadline;
    NSMutableData *_buffer;
}

- (instancetype)initWithFileDescriptor:(int)fd clientAddress:(iTermSocketAddress *)address {
    self = [super init];
    if (self) {
        _fd = fd;
        _buffer = [[NSMutableData alloc] init];
        _clientAddress = [address retain];
    }
    return self;
}

- (void)dealloc {
    [_clientAddress release];
    [_request release];
    [_buffer release];
    [super dealloc];
}

- (void)close {
    if (_fd >= 0) {
        close(_fd);
        _fd = -1;
    }
}
- (BOOL)sendResponseWithCode:(int)code reason:(NSString *)reason headers:(NSDictionary *)headers {
    BOOL ok;
    ok = [self writeString:[NSString stringWithFormat:@"HTTP/1.1 %d %@\r\n", code, reason]];
    if (!ok) {
        [self close];
        return NO;
    }
    for (NSString *key in headers) {
        ok = [self writeString:[NSString stringWithFormat:@"%@: %@\r\n", key, headers[key]]];
        if (!ok) {
            [self close];
            return NO;
        }
    }

    if (code == 101) {
        _deadline = DBL_MAX;
    } else {
        [self close];
    }
    return YES;
}

- (void)badRequest {
    [self sendResponseWithCode:400 reason:@"Bad Request" headers:@{}];
}

- (NSURLRequest *)readRequest {
    _deadline = [NSDate timeIntervalSinceReferenceDate] + 30;
    NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] init] autorelease];
    NSString *requestLine = [self nextLine];
    if (!requestLine) {
        [self badRequest];
        return nil;
    }

    NSArray<NSString *> *parts = [requestLine componentsSeparatedByString:@" "];
    if (parts.count != 3) {
        [self badRequest];
        return nil;
    }

    request.HTTPMethod = parts[0];
    request.URL = [NSURL URLWithString:parts[1]];
    NSString *protocol = parts[2];
    if (![protocol isEqualToString:@"HTTP/1.1"]) {
        [self badRequest];
        return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *headers = [self readHeaders];
    if (!headers) {
        [self badRequest];
        return nil;
    }
    request.allHTTPHeaderFields = headers;

    // Requests with contents are not supported.
    if (headers[@"content-length"]) {
        [self badRequest];
        return nil;
    }

    return request;
}

- (NSMutableDictionary<NSString *, NSString *> *)readHeaders {
    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    const int kMaxHeaders = 100;
    while (headers.count < kMaxHeaders) {
        NSString *line = [self nextLine];
        if (line == nil) {
            // Timeout, EOF, or error
            return nil;
        }
        if (line.length == 0) {
            break;
        }
        NSInteger colon = [line rangeOfString:@":"].location;
        if (colon == NSNotFound || colon + 1 == line.length) {
            return nil;
        }

        NSString *key = [[line substringToIndex:colon] lowercaseString];
        NSString *value = [line substringFromIndex:colon + 1];
        headers[key] = value;
    }
    if (headers.count == kMaxHeaders) {
        return nil;
    }
    return headers;
}

- (NSString *)nextLine {
    NSMutableData *bytes = [NSMutableData data];
    NSData *crlfData = [NSData dataWithBytes:"\r\n" length:2];
    // Upper bound on length of a line
    while (bytes.length < 4096) {
        NSData *data = [self nextByte];
        if (data) {
            [bytes appendData:data];
            if (bytes.length > 2 && [[bytes subdataWithRange:NSMakeRange(bytes.length - 2, 2)] isEqualToData:crlfData]) {
                return [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
            }
        } else {
            return nil;
        }
    }
    return nil;
}

- (NSData *)nextByte {
    if (_buffer.length == 0) {
        [self readFromFileDescriptor];
    }

    if (_buffer.length > 0) {
        NSData *result = [_buffer subdataWithRange:NSMakeRange(0, 1)];
        [_buffer replaceBytesInRange:NSMakeRange(0, 1) withBytes:"" length:0];
        return result;
    } else {
        return nil;
    }
}

- (NSMutableData *)nextBytes:(int64_t)length {
    int64_t bytesLeftToRead = length;
    NSMutableData *bytes = [NSMutableData data];
    while (bytes.length < length) {
        if (_buffer.length == 0) {
            [self readFromFileDescriptor];
        }

        if (_buffer.length > 0) {
            int64_t chunkSize = MIN(_buffer.length, bytesLeftToRead);
            [bytes appendData:[_buffer subdataWithRange:NSMakeRange(0, chunkSize)]];
            bytesLeftToRead -= chunkSize;
            [_buffer replaceBytesInRange:NSMakeRange(0, chunkSize) withBytes:"" length:0];
        } else {
            return nil;
        }
    }

    return bytes;
}

- (BOOL)readFromFileDescriptor {
    if (_fd < 0) {
        return NO;
    }
    fd_set set;
    FD_ZERO(&set);
    FD_SET(_fd, &set);

    struct timeval timeout;
    CGFloat dt = _deadline - [NSDate timeIntervalSinceReferenceDate];
    if (dt < 0) {
        return NO;
    }
    timeout.tv_sec = floor(dt);
    timeout.tv_usec = fmod(dt, 1.0) * 1000000;
    int rc;
    do {
        rc = select(_fd + 1, &set, NULL, NULL, &timeout);
    } while (rc == -1 && (errno == EINTR || errno == EAGAIN));
    if (rc == 0) {
        return NO;
    }

    char buffer[4096];
    do {
        rc = read(_fd, buffer, sizeof(buffer));
    } while (rc == -1 && (errno == EINTR || errno == EAGAIN));
    if (rc <= 0) {
        _fd = -1;
        return NO;
    }

    [_buffer appendBytes:buffer length:rc];
    return YES;
}

- (BOOL)writeString:(NSString *)string {
    return [self writeData:[string dataUsingEncoding:NSUTF8StringEncoding]];
}

- (BOOL)writeData:(NSData *)data {
    if (_fd < 0) {
        return NO;
    }
    NSInteger offset = 0;
    while (offset < data.length) {
        int rc;
        do {
            rc = write(_fd, data.bytes + offset, data.length - offset);
        } while (rc == -1 && (errno == EINTR || errno == EAGAIN));
        if (rc <= 0) {
            _fd = -1;
            return NO;
        }
        offset += rc;
    }
    return YES;
}

@end

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

- (void)appendFragment:(iTermWebSocketFrame *)fragment;

@end

@interface iTermWebSocketFrame()
@property (nonatomic, readwrite) BOOL fin;
@property (nonatomic, readwrite) iTermWebSocketOpcode opcode;
@property (nonatomic, copy) NSData *payload;
@end

@implementation iTermWebSocketFrame {
    NSData *_data;
}

+ (instancetype)closeFrame {
    iTermWebSocketFrame *frame = [[[iTermWebSocketFrame alloc] init] autorelease];
    frame.fin = YES;
    frame.opcode = iTermWebSocketOpcodeConnectionClose;
    return frame;
}

+ (instancetype)closeFrameWithCode:(uint16_t)code reason:(NSString *)reason {
    iTermWebSocketFrame *frame = [[[iTermWebSocketFrame alloc] init] autorelease];
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
    iTermWebSocketFrame *frame = [[[iTermWebSocketFrame alloc] init] autorelease];
    frame.fin = YES;
    frame.opcode = iTermWebSocketOpcodePing;
    frame.payload = data;

    if (frame.data.length > 125) {
        return nil;
    }
    return frame;
}

+ (instancetype)pongFrameForPingFrame:(iTermWebSocketFrame *)ping  {
    iTermWebSocketFrame *frame = [[[iTermWebSocketFrame alloc] init] autorelease];
    frame.fin = YES;
    frame.opcode = iTermWebSocketOpcodePong;
    frame.payload = ping.payload;

    if (frame.data.length > 125) {
        return nil;
    }
    return frame;
}

+ (instancetype)textFrameWithData:(NSData *)data {
    iTermWebSocketFrame *frame = [[[iTermWebSocketFrame alloc] init] autorelease];
    frame.fin = YES;
    frame.opcode = iTermWebSocketOpcodeText;
    frame.payload = data;
    return frame;
}

+ (instancetype)textFrameWithString:(NSString *)string {
    return [self textFrameWithData:[string dataUsingEncoding:NSUTF8StringEncoding]];
}

+ (instancetype)binaryFrameWithData:(NSData *)data {
    iTermWebSocketFrame *frame = [[[iTermWebSocketFrame alloc] init] autorelease];
    frame.fin = YES;
    frame.opcode = iTermWebSocketOpcodeBinary;
    frame.payload = data;
    return frame;
}

+ (instancetype)frameWithDataSource:(unsigned char *(^)(int64_t))dataSource {
    iTermWebSocketFrame *frame = [[[iTermWebSocketFrame alloc] init] autorelease];

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
        _data = [data retain];
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
    return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}

- (void)appendFragment:(iTermWebSocketFrame *)fragment {
    assert(fragment.opcode == iTermWebSocketOpcodeContinuation);
    assert(!self.fin);

    self.fin = fragment.fin;
    @autoreleasepool {
        NSMutableData *temp = [[self.payload mutableCopy] autorelease];
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

@class iTermWebSocketConnection;

@protocol iTermWebSocketConnectionDelegate<NSObject>
- (void)webSocketConnectionDidTerminate:(iTermWebSocketConnection *)webSocketConnection;
- (void)webSocketConnection:(iTermWebSocketConnection *)webSocketConnection didReadFrame:(iTermWebSocketFrame *)frame;
@end

@interface iTermWebSocketConnection : NSObject
@property(nonatomic, assign) id<iTermWebSocketConnectionDelegate> delegate;

- (instancetype)initWithConnection:(iTermAPIServerConnection *)connection;
- (void)start;
- (void)close;
- (void)enqueueData:(NSData *)data;

@end

typedef NS_ENUM(NSUInteger, iTermWebSocketConnectionState) {
    iTermWebSocketConnectionStateConnecting,
    iTermWebSocketConnectionStateOpen,
    iTermWebSocketConnectionStateClosing,
    iTermWebSocketConnectionStateClosed
};

@implementation iTermWebSocketConnection {
    iTermAPIServerConnection *_connection;
    iTermWebSocketConnectionState _state;
    iTermWebSocketFrame *_fragment;
    NSMutableArray<NSData *> *_dataQueue;
}

- (instancetype)initWithConnection:(iTermAPIServerConnection *)connection {
    self = [super init];
    if (self) {
        _connection = [connection retain];
        _dataQueue = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_connection release];
    [_dataQueue release];
    [super dealloc];
}

- (void)start {
    NSURLRequest *request = [_connection readRequest];
    if (!request) {
        [_delegate webSocketConnectionDidTerminate:self];
        return;
    }

    if (![self validateRequest:request]) {
        [_connection badRequest];
        [_delegate webSocketConnectionDidTerminate:self];
        return;
    }

    if (![self sendUpgradeResponseWithKey:request.allHTTPHeaderFields[@"sec-websocket-key"]]) {
        [_connection badRequest];
        [_delegate webSocketConnectionDidTerminate:self];
        return;
    }
    _state = iTermWebSocketConnectionStateOpen;

    // TODO: Use dispatch_io to read and write asynchronously since we could block while reading
    // and then suddenly another queue wants to write.
    while (_state != iTermWebSocketConnectionStateClosed) {
        [self readFrame];
        if (_state == iTermWebSocketConnectionStateOpen) {
            [self writeQueuedFrames];
        }
    }
    [_connection close];
}

- (void)enqueueData:(NSData *)data {
    @synchronized (self) {
        [_dataQueue addObject:data];
    }
}

- (void)abort {
    [_delegate webSocketConnectionDidTerminate:self];
    [_connection close];
    _state = iTermWebSocketConnectionStateClosed;
}

- (void)readFrame {
    iTermWebSocketFrame *frame = [iTermWebSocketFrame frameWithDataSource:^unsigned char *(int64_t length) {
        return (unsigned char *)[[_connection nextBytes:length] mutableBytes];
    }];

    switch (frame.opcode) {
        case iTermWebSocketOpcodeBinary:
        case iTermWebSocketOpcodeText:
            if (_state == iTermWebSocketConnectionStateOpen) {
                if (frame.fin) {
                    [_delegate webSocketConnection:self didReadFrame:frame];
                } else if (_fragment == nil) {
                    _fragment = [frame retain];
                } else {
                    [self abort];
                }
            } else {
                [self abort];
            }
            break;

        case iTermWebSocketOpcodePing:
            if (_state == iTermWebSocketConnectionStateOpen) {
                if (![_connection writeData:[[iTermWebSocketFrame pongFrameForPingFrame:frame] data]]) {
                    [self abort];
                }
            } else {
                [self abort];
            }
            break;

        case iTermWebSocketOpcodePong:
            break;

        case iTermWebSocketOpcodeContinuation:
            if (_state == iTermWebSocketConnectionStateOpen) {
                if (!_fragment) {
                    [self abort];
                    break;
                }
                [_fragment appendFragment:frame];
                if (frame.fin) {
                    [_delegate webSocketConnection:self didReadFrame:_fragment];
                    [_fragment release];
                    _fragment = nil;
                }
            } else {
                [self abort];
            }
            break;

        case iTermWebSocketOpcodeConnectionClose:
            if (_state == iTermWebSocketConnectionStateOpen) {
                if (![_connection writeData:[[iTermWebSocketFrame closeFrame] data]]) {
                    [self abort];
                } else {
                    _state = iTermWebSocketConnectionStateClosing;
                }
            } else if (_state == iTermWebSocketConnectionStateClosing) {
                _state = iTermWebSocketConnectionStateClosed;
            }
            break;
    }
}

- (void)close {
    if (_state == iTermWebSocketConnectionStateOpen) {
        if (![_connection writeData:[[iTermWebSocketFrame closeFrame] data]]) {
            [self abort];
        } else {
            _state = iTermWebSocketConnectionStateClosing;
        }
    }
}

- (BOOL)validateRequest:(NSURLRequest *)request {
    if (![request.HTTPMethod isEqualToString:@"GET"]) {
        return NO;
    }
    if (request.URL.path.length == 0) {
        return NO;
    }
    NSDictionary<NSString *, NSString *> *headers = request.allHTTPHeaderFields;
    NSDictionary<NSString *, NSString *> *requiredValues =
        @{ @"host": @"localhost",
           @"upgrade": @"websocket",
           @"connection": @"Upgrade",
           @"sec-websocket-protocol": kProtocolName,
           @"sec-websocket-version": @"1",
           @"origin": @"localhost" };
    for (NSString *key in requiredValues) {
        if (![headers[key] isEqualToString:requiredValues[key]]) {
            return NO;
        }
    }
    NSArray<NSString *> *requiredKeys =
        @[ @"sec-websocket-key",
           @"origin" ];
    for (NSString *key in requiredKeys) {
        if (!headers[key]) {
            return NO;
        }
    }

    if ([headers[@"sec-websocket-key"] length] == 0) {
        return NO;
    }

    return YES;
}

- (BOOL)sendUpgradeResponseWithKey:(NSString *)key {
    key = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    key = [key stringByAppendingString:@"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"];

    NSData *data = [key dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA1_DIGEST_LENGTH];
    if (CC_SHA1([data bytes], [data length], hash) ) {
        NSData *sha1 = [NSData dataWithBytes:hash length:CC_SHA1_DIGEST_LENGTH];
        NSDictionary<NSString *, NSString *> *headers =
            @{ @"Upgrade": @"websocket",
               @"Connection": @"Upgrade",
               @"Sec-WebSocket-Accept": [sha1 stringWithBase64EncodingWithLineBreak:NO],
               @"Sec-WebSocket-Protocol": kProtocolName };
        return [_connection sendResponseWithCode:101
                                          reason:@"Switching Protocols"
                                         headers:headers];
    } else {
        return NO;
    }
}

@end

@interface iTermAPIServer()<iTermWebSocketConnectionDelegate>
@end

@implementation iTermAPIServer {
    iTermSocket *_socket;
    NSMutableArray<iTermWebSocketConnection *> *_connections;
    dispatch_queue_t _queue;
}

+ (instancetype)sharedInstance {
    static id instance;
    @synchronized (self) {
        if (!instance) {
            instance = [[self alloc] init];
        }
    }
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _connections = [[NSMutableArray alloc] init];
        _socket = [[iTermSocket tcpIPV4Socket] retain];
        _queue = dispatch_queue_create("com.iterm2.apisockets", NULL);
        if (!_socket) {
            return nil;
        }
        [_socket setReuseAddr:YES];
        iTermIPV4Address *loopback = [[iTermIPV4Address alloc] initWithLoopback];
        iTermSocketAddress *socketAddress = [[[iTermSocketIPV4Address alloc] initWithIPV4Address:[loopback autorelease]
                                                                                            port:1912] autorelease];
        if (![_socket bindToAddress:socketAddress]) {
            return nil;
        }

        BOOL ok = [_socket listenWithBacklog:5 accept:^(int fd, iTermSocketAddress *clientAddress) {
            [self didAcceptConnectionOnFileDescriptor:fd fromAddress:clientAddress];
        }];
        if (!ok) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    dispatch_release(_queue);
    [_socket release];
    [_connections release];
    [super dealloc];
}

- (void)didAcceptConnectionOnFileDescriptor:(int)fd fromAddress:(iTermSocketAddress *)address {
    dispatch_async(_queue, ^{
        iTermAPIServerConnection *connection = [[[iTermAPIServerConnection alloc] initWithFileDescriptor:fd clientAddress:address] autorelease];
        iTermWebSocketConnection *webSocketConnection = [[[iTermWebSocketConnection alloc] initWithConnection:connection] autorelease];
        webSocketConnection.delegate = self;
        [_connections addObject:webSocketConnection];
        [webSocketConnection start];
    });
}

#pragma mark - iTermWebSocketConnectionDelegate

- (void)webSocketConnectionDidTerminate:(iTermWebSocketConnection *)webSocketConnection {
    [_connections removeObject:webSocketConnection];
}


@end
