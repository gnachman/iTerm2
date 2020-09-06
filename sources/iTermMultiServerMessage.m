//
//  iTermMultiServerMessage.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/20.
//

#import "iTermMultiServerMessage.h"

#import "DebugLogging.h"

@implementation iTermMultiServerMessage {
    NSNumber *_fileDescriptor;
    BOOL _fileDescriptorAccessed;
}

- (instancetype)initWithData:(NSData *)data fileDescriptor:(NSNumber *)fileDescriptor {
    self = [super init];
    if (self) {
        _data = [data copy];
        _fileDescriptor = fileDescriptor;
    }
    return self;
}

- (instancetype)initWithProtocolMessage:(const iTermClientServerProtocolMessage *)protocolMessage
                         fileDescriptor:(NSNumber *)fileDescriptor {
    NSData *data = [NSData dataWithBytes:protocolMessage->ioVectors[0].iov_base
                                  length:protocolMessage->ioVectors[0].iov_len];
    return [self initWithData:data fileDescriptor:fileDescriptor];
}

- (instancetype)initWithProtocolMessage:(const iTermClientServerProtocolMessage *)protocolMessage {
    NSNumber *fileDescriptor = nil;
    if (protocolMessage->controlBuffer.cm.cmsg_len == CMSG_LEN(sizeof(int)) &&
        protocolMessage->controlBuffer.cm.cmsg_level == SOL_SOCKET &&
        protocolMessage->controlBuffer.cm.cmsg_type == SCM_RIGHTS) {
        const int fd = *((int *)CMSG_DATA(&protocolMessage->controlBuffer.cm));
        fileDescriptor = @(fd);
    }
    return [self initWithProtocolMessage:protocolMessage fileDescriptor:fileDescriptor];
}

- (void)dealloc {
    if (!_fileDescriptorAccessed && _fileDescriptor && _fileDescriptor.intValue >= 0) {
        DLog(@"File descriptor in message never accessed. Closing %d", _fileDescriptor.intValue);
        close(_fileDescriptor.intValue);
    }
}

- (NSNumber *)fileDescriptor {
    _fileDescriptorAccessed = YES;
    return _fileDescriptor;
}

@end
