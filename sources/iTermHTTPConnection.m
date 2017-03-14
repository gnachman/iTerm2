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

@implementation iTermHTTPConnection {
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
        _clientAddress = address;
    }
    return self;
}

- (dispatch_io_t)newChannelOnQueue:(dispatch_queue_t)queue {
    return dispatch_io_create(DISPATCH_IO_STREAM, _fd, queue, ^(int error) {
        DLog(@"Channel closed");
    });
}

- (void)close {
    if (_fd >= 0) {
        DLog(@"Close http connection from %@", [NSThread callStackSymbols]);
        int rc = close(_fd);
        if (rc != 0) {
            XLog(@"close failed with %s", strerror(errno));
        }
        _fd = -1;
    }
}

- (BOOL)sendResponseWithCode:(int)code reason:(NSString *)reason headers:(NSDictionary *)headers {
    if (_fd < 0) {
        return NO;
    }

    DLog(@"Send %d code", code);
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
    ok = [self writeString:[NSString stringWithFormat:@"\r\n"]];
    if (!ok) {
        [self close];
        return NO;
    }

    if (code >= 100 && code < 200) {
        DLog(@"Removing deadline because code is in the 100s");
        _deadline = INFINITY;
    } else {
        DLog(@"Non-10x code, closing connection");
        [self close];
    }
    return YES;
}

- (void)badRequest {
    [self sendResponseWithCode:400 reason:@"Bad Request" headers:@{}];
}

- (void)unauthorized {
    [self sendResponseWithCode:401 reason:@"Unauthorized" headers:@{}];
}

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

- (NSMutableData *)read {
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

    char buffer[4096];
    int rc;
    do {
        rc = read(_fd, buffer, sizeof(buffer));
    } while (rc == -1 && (errno == EINTR || errno == EAGAIN));
    if (rc <= 0) {
        if (rc < 0) {
            DLog(@"Read failed with %s", strerror(errno));
        } else {
            DLog(@"EOF reached");
        }
        _fd = -1;
        return NO;
    }

    [_buffer appendBytes:buffer length:rc];
    return YES;
}

- (BOOL)waitForIO:(BOOL)read {
    if (_fd < 0) {
        DLog(@"Tried select on closed file descriptor");
        return NO;
    }
    fd_set set;
    FD_ZERO(&set);
    FD_SET(_fd, &set);

    struct timeval *timeoutPointer = NULL;
    struct timeval timeout;
    if (!isinf(_deadline)) {
        CGFloat dt = _deadline - [NSDate timeIntervalSinceReferenceDate];
        if (!read) {
            // The deadline for writes is extended so we can send an error after timing out.
            dt += 5;
        }
        if (dt < 0) {
            return NO;
        }
        timeout.tv_sec = floor(dt);
        timeout.tv_usec = fmod(dt, 1.0) * 1000000;
        timeoutPointer = &timeout;
    }
    int rc;
    do {
        if (read) {
            rc = select(_fd + 1, &set, NULL, NULL, timeoutPointer);
        } else {
            rc = select(_fd + 1, NULL, &set, NULL, timeoutPointer);
        }
    } while (rc == -1 && (errno == EINTR || errno == EAGAIN));
    if (rc == 0) {
        DLog(@"select timed out");
        return NO;
    } else if (rc < 0) {
        DLog(@"Select failed with %s", strerror(errno));
        return NO;
    }

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

        int rc;
        do {
            rc = write(_fd, data.bytes + offset, data.length - offset);
        } while (rc == -1 && (errno == EINTR || errno == EAGAIN));
        if (rc <= 0) {
            if (rc < 0) {
                DLog(@"Write failed with %s", strerror(errno));
            } else {
                DLog(@"EOF reached");
            }
            _fd = -1;
            return NO;
        }
        offset += rc;
    }
    return YES;
}

@end
