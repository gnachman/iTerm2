//
//  iTermHTTPConnection.m
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import "iTermHTTPConnection.h"
#import "DebugLogging.h"
#import "iTermSocketAddress.h"
#include <poll.h>
#include <sys/time.h>

// As long as iTermStream exists, fd and stream will be valid.
// This object takes ownership of fd and you must not close it yourself.
@interface iTermStream: NSObject
@property (nonatomic, readonly) dispatch_io_t stream;
@property (nonatomic, readonly) int fd;

- (instancetype)initWithFileDescriptor:(int)fd queue:(dispatch_queue_t)queue;
- (instancetype)init NS_UNAVAILABLE;

@end

@implementation iTermStream {
    int _fd;
}

- (instancetype)initWithFileDescriptor:(int)fd queue:(dispatch_queue_t)queue {
    self = [super init];
    if (self) {
        _fd = fd;
        // cycle ensures that _stream sticks around long enough to close the file descriptor.
        __block dispatch_io_t cycle;
        _stream = dispatch_io_create(DISPATCH_IO_STREAM, fd, queue, ^(int error) {
            close(fd);
            cycle = nil;
        });
        cycle = _stream;
    }
    return self;
}

- (void)dealloc {
    dispatch_io_close(_stream, DISPATCH_IO_STOP);
}

@end

@interface iTermHTTPConnection()
@property (atomic) BOOL closing;
@end

@implementation iTermHTTPConnection {
    NSObject *_lock;
    NSURLRequest *_request;
    NSTimeInterval _deadline;
    NSMutableData *_buffer;
    iTermStream *_stream;
}

- (instancetype)initWithFileDescriptor:(int)fd
                         clientAddress:(iTermSocketAddress *)address
                                  euid:(NSNumber *)euid {
    self = [super init];
    if (self) {
        _lock = [[NSObject alloc] init];
        _buffer = [[NSMutableData alloc] init];
        _clientAddress = address;
        _euid = euid;
        _queue = dispatch_queue_create("com.iterm2.httpconn", NULL);
        _stream = [[iTermStream alloc] initWithFileDescriptor:fd queue:_queue];

    }
    return self;
}

- (void)closeConnection {
    @synchronized (ITNonnilLock(_lock)) {
        _stream = nil;
    }
}

- (BOOL)sendResponseWithCode:(int)code reason:(NSString *)reason headers:(NSDictionary *)headers {
    @synchronized(ITNonnilLock(_lock)) {
        if (!_stream) {
            return NO;
        }

        RLog(@"Send %d code", code);
        BOOL ok;
        ok = [self writeString:[NSString stringWithFormat:@"HTTP/1.1 %d %@\r\n", code, reason]];
        if (!ok) {
            _stream = nil;
            return NO;
        }
        for (NSString *key in headers) {
            ok = [self writeString:[NSString stringWithFormat:@"%@: %@\r\n", key, headers[key]]];
            if (!ok) {
                _stream = nil;
                return NO;
            }
        }
        ok = [self writeString:[NSString stringWithFormat:@"\r\n"]];
        if (!ok) {
            _stream = nil;
            return NO;
        }

        if (code >= 100 && code < 200) {
            DLog(@"Removing deadline because code is in the 100s");
            _deadline = INFINITY;
        } else {
            DLog(@"Non-10x code, closing connection");
            _stream = nil;
        }
    }
    return YES;
}

- (void)badRequest {
    [self sendResponseWithCode:400 reason:@"Bad Request" headers:@{}];
}

- (void)unacceptable {
    [self sendResponseWithCode:406 reason:@"Unacceptable (upgrade Python library)" headers:@{}];
}

- (void)unauthorized {
    [self sendResponseWithCode:401 reason:@"Unauthorized" headers:@{}];
}

// queue
- (NSURLRequest *)readRequest {
    DLog(@"Begin reading request. Begin clock towards deadline.");
    _deadline = [NSDate timeIntervalSinceReferenceDate] + 30;
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    NSString *requestLine = [self nextLine];
    if (!requestLine) {
        DLog(@"No request line");
        [self badRequest];
        return nil;
    }

    NSArray<NSString *> *parts = [requestLine componentsSeparatedByString:@" "];
    if (parts.count != 3) {
        DLog(@"Wrong number of parts in request: %@", parts);
        [self badRequest];
        return nil;
    }

    request.HTTPMethod = parts[0];
    request.URL = [NSURL URLWithString:parts[1]];
    NSString *protocol = parts[2];
    if (![protocol isEqualToString:@"HTTP/1.1"]) {
        DLog(@"Protocol not 1.1: %@", protocol);
        [self badRequest];
        return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *headers = [self readHeaders];
    if (!headers) {
        DLog(@"No headers");
        [self badRequest];
        return nil;
    }
    request.allHTTPHeaderFields = headers;

    // Requests with contents are not supported.
    if (headers[@"content-length"]) {
        DLog(@"Received unsupported header content-length");
        [self badRequest];
        return nil;
    }

    DLog(@"Request looks good");
    return request;
}

- (NSMutableDictionary<NSString *, NSString *> *)readHeaders {
    DLog(@"Reading headers");
    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    const int kMaxHeaders = 100;
    while (headers.count < kMaxHeaders) {
        NSString *line = [self nextLine];
        if (line == nil) {
            // Timeout, EOF, or error
            return nil;
        }
        if (line.length == 0) {
            DLog(@"found end of headers");
            break;
        }
        NSInteger colon = [line rangeOfString:@":"].location;
        if (colon == NSNotFound || colon + 1 == line.length) {
            DLog(@"header has no colon: %@", line);
            return nil;
        }

        NSString *key = [[line substringToIndex:colon] lowercaseString];
        NSString *value = [line substringFromIndex:colon + 1];
        headers[key] = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        DLog(@"Add header: %@: %@", key, value);
    }
    if (headers.count == kMaxHeaders) {
        DLog(@"Too many headers");
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
            if (bytes.length >= 2 && [[bytes subdataWithRange:NSMakeRange(bytes.length - 2, 2)] isEqualToData:crlfData]) {
                return [[NSString alloc] initWithData:[bytes subdataWithRange:NSMakeRange(0, bytes.length - 2)]
                                             encoding:NSISOLatin1StringEncoding];
            }
        } else {
            return nil;
        }
    }
    DLog(@"Overly long line");
    return nil;
}

- (NSMutableData *)readSynchronously {
    if (!_buffer.length) {
        [self readFromFileDescriptor];
    }
    if (_buffer.length) {
        NSMutableData *result = _buffer;
        _buffer = [NSMutableData data];
        return result;
    } else {
        return nil;
    }
}
- (NSData *)nextByte {
    return [self nextBytes:1];
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
    if (![self waitForIO:YES]) {
        return NO;
    }

    iTermStream *stream;
    @synchronized(ITNonnilLock(_lock)) {
        if (!_stream) {
            return NO;
        }
        stream = _stream;
    }

    char buffer[4096];
    int rc;
    do {
        rc = read(stream.fd, buffer, sizeof(buffer));
    } while (rc == -1 && (errno == EINTR || errno == EAGAIN));
    if (rc <= 0) {
        if (rc < 0) {
            RLog(@"Read failed with %s", strerror(errno));
        } else {
            RLog(@"EOF reached");
        }
        @synchronized(ITNonnilLock(_lock)) {
            _stream = nil;
        }
        return NO;
    }

    [_buffer appendBytes:buffer length:rc];
    return YES;
}

// Uses poll() rather than select() because select() can't handle file descriptors >= FD_SETSIZE
// (1024). Past that, FD_SET raises EXC_GUARD and every read and write on the connection fails.
- (BOOL)waitForIO:(BOOL)read {
    // Absolute time to give up, or INFINITY to wait forever.
    NSTimeInterval giveUpTime = INFINITY;
    iTermStream *stream;
    @synchronized(ITNonnilLock(_lock)) {
        if (!_stream) {
            return NO;
        }
        stream = _stream;

        if (!isinf(_deadline)) {
            // The deadline for writes is extended so we can send an error after timing out.
            giveUpTime = _deadline + (read ? 0 : 5);
            if (giveUpTime < [NSDate timeIntervalSinceReferenceDate]) {
                return NO;
            }
        }
    }
    struct pollfd pfd = {
        .fd = stream.fd,
        .events = read ? POLLIN : POLLOUT,
        .revents = 0
    };
    int rc;
    do {
        int timeoutMillis = -1;
        if (!isinf(giveUpTime)) {
            const NSTimeInterval dt = giveUpTime - [NSDate timeIntervalSinceReferenceDate];
            timeoutMillis = (int)MAX(0, ceil(dt * 1000));
        }
        rc = poll(&pfd, 1, timeoutMillis);
    } while (rc == -1 && (errno == EINTR || errno == EAGAIN));
    if (rc == 0) {
        RLog(@"poll timed out");
        return NO;
    } else if (rc < 0) {
        RLog(@"poll failed with %s", strerror(errno));
        return NO;
    }
    if (pfd.revents & POLLNVAL) {
        RLog(@"poll reports invalid file descriptor");
        return NO;
    }
    // POLLHUP and POLLERR fall through so the subsequent read() or write() reports EOF or the
    // error and closes the stream, just as it did when select() reported the descriptor ready.
    return YES;
}

- (BOOL)writeString:(NSString *)string {
    return [self writeData:[string dataUsingEncoding:NSUTF8StringEncoding]];
}

- (BOOL)writeData:(NSData *)data {
    DLog(@"Want to write %d bytes of data", (int)data.length);
    NSInteger offset = 0;
    while (offset < data.length) {
        if (![self waitForIO:NO]) {
            return NO;
        }

        iTermStream *stream;
        @synchronized(ITNonnilLock(_lock)) {
            if (!_stream) {
                return NO;
            }
            stream = _stream;
        }
        int rc;
        do {
            rc = write(stream.fd, data.bytes + offset, data.length - offset);
        } while (rc == -1 && (errno == EINTR || errno == EAGAIN));
        if (rc <= 0) {
            if (rc < 0) {
                RLog(@"Write failed with %s", strerror(errno));
            } else {
                DLog(@"EOF reached");
            }
            @synchronized(ITNonnilLock(_lock)) {
                _stream = nil;
            }
            return NO;
        }
        offset += rc;
    }
    return YES;
}

- (void)writeAsynchronously:(dispatch_data_t)dispatchData
                      queue:(dispatch_queue_t)queue
                 completion:(void (^)(bool done,
                                      dispatch_data_t _Nullable data,
                                      int error))completion {
    @synchronized(ITNonnilLock(_lock)) {
        if (_stream) {
            dispatch_io_write(_stream.stream,
                              0,  // offset
                              dispatchData,
                              queue,
                              ^(bool done, dispatch_data_t  _Nullable data, int error) {
                completion(done, data, error);
            });
            return;
        }
    }
    // The stream is gone, so the write can never be submitted. Still deliver a
    // terminal (error) completion on the caller's queue so that callers relying
    // on completion running exactly once - e.g. to release a backpressure slot -
    // are not wedged forever. Done outside @synchronized because completion may
    // reenter this object.
    dispatch_async(queue, ^{
        completion(true, NULL, EPIPE);
    });
}

@end
