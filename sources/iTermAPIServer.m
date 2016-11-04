//
//  iTermAPIServer.m
//  iTerm2
//
//  Created by George Nachman on 11/3/16.
//
//

#import "iTermAPIServer.h"

#import "DebugLogging.h"
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/socket.h>
#include <sys/types.h>

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

@protocol iTermAPIServerConnectionDelegate<NSObject>
- (void)apiConnection:(iTermAPIServerConnection *)connection didReadRequest:(NSURLRequest *)request;
- (void)apiConnection:(iTermAPIServerConnection *)connection didFailWithError:(NSError *)error;
@end

@interface iTermAPIServerConnection : NSObject

@property (nonatomic, assign) id<iTermAPIServerConnectionDelegate> delegate;

- (instancetype)initWithFileDescriptor:(int)fd clientAddress:(iTermSocketAddress *)address;
- (void)readRequest;

@end

@implementation iTermAPIServerConnection {
    int _fd;
    iTermSocketAddress *_clientAddress;
    NSURLRequest *_request;
    NSTimeInterval _deadline;
}

- (instancetype)initWithFileDescriptor:(int)fd clientAddress:(iTermSocketAddress *)address {
    self = [super init];
    if (self) {
        _fd = fd;
        _clientAddress = [address retain];
    }
    return self;
}

- (void)dealloc {
    [_clientAddress release];
    [_request release];
    [super dealloc];
}

- (void)readRequest {
    _deadline = [NSDate timeIntervalSinceReferenceDate] + 30;
    NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] init] autorelease];
    NSString *requestLine = [self readLine];
    if (!requestLine) {
        [_delegate apiConnection:self didFailWithError:[NSError errorWithDomain:@"com.iterm2" code:400 userInfo:nil]];
        return;
    }

    NSArray<NSString *> *parts = [requestLine componentsSeparatedByString:@" "];
    if (parts.count != 3) {
        [_delegate apiConnection:self didFailWithError:[NSError errorWithDomain:@"com.iterm2" code:400 userInfo:nil]];
        return;
    }

    request.HTTPMethod = parts[0];
    request.URL = [NSURL URLWithString:parts[1]];
    NSString *protocol = parts[2];
    if (![protocol isEqualToString:@"HTTP/1.1"]) {
        [_delegate apiConnection:self didFailWithError:[NSError errorWithDomain:@"com.iterm2" code:400 userInfo:nil]];
        return;
    }

    NSMutableDictionary<NSString *, NSString *> *headers = [self readHeaders];
    if (!headers) {
        [_delegate apiConnection:self didFailWithError:[NSError errorWithDomain:@"com.iterm2" code:400 userInfo:nil]];
        return;
    }
    request.allHTTPHeaderFields = headers;

    // Requests with contents are not supported.
    [_delegate apiConnection:self didReadRequest:request];

}

- (NSMutableDictionary<NSString *, NSString *> *)readHeaders {
    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    while (1) {
        NSString *line = [self readLine];
        if (line == nil) {
            // Timeout
            return nil;
        }
        if (line.length == 0) {
            break;
        }
        NSInteger colon = [line rangeOfString:@":"].location;
        if (colon == NSNotFound || colon + 1 == line.length) {
            return nil;
        }

        NSString *key = [line substringToIndex:colon];
        NSString *value = [line substringFromIndex:colon + 1];
        headers[key] = value;
    }
    return headers;
}

- (NSString *)readLine {
    NSMutableData *bytes = [NSMutableData data];
    NSData *crlfData = [NSData dataWithBytes:"\r\n" length:2];
    while ([NSDate timeIntervalSinceReferenceDate] < _deadline) {
        NSData *data = [self readByte];
        if (data) {
            [bytes appendData:data];
            if (bytes.length > 2 && [[bytes subdataWithRange:NSMakeRange(bytes.length - 2, 2)] isEqualToData:crlfData]) {
                return [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
            }
        }
    }
    return nil;
}

- (NSData *)readByte {
    // TODO
}

@end

@interface iTermAPIServer()<iTermAPIServerConnectionDelegate>
@end

@implementation iTermAPIServer {
    iTermSocket *_socket;
    NSMutableArray<iTermAPIServerConnection *> *_connections;
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
        connection.delegate = self;
        [_connections addObject:connection];

        [connection readRequest];
    });
}

#pragma mark - iTermAPIServerConnectionDelegate

- (void)apiConnection:(iTermAPIServerConnection *)connection didReadRequest:(NSURLRequest *)request {

}

- (void)apiConnection:(iTermAPIServerConnection *)connection didFailWithError:(NSError *)error {

}

@end
