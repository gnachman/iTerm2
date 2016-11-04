//
//  iTermAPIServerConnection.m
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import "iTermAPIServerConnection.h"

#import "iTermSocketAddress.h"

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

- (dispatch_io_t)newChannelOnQueue:(dispatch_queue_t)queue {
    return dispatch_io_create(DISPATCH_IO_STREAM, _fd, queue, ^(int error) {
        // TODO: Figure out what to do here
        assert(false);
    });
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

- (BOOL)waitForIO:(BOOL)read {
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
        if (read) {
            rc = select(_fd + 1, &set, NULL, NULL, &timeout);
        } else {
            rc = select(_fd + 1, NULL, &set, NULL, &timeout);
        }
    } while (rc == -1 && (errno == EINTR || errno == EAGAIN));
    if (rc == 0) {
        return NO;
    }

    return YES;
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
            _fd = -1;
            return NO;
        }
        offset += rc;
    }
    return YES;
}

@end
