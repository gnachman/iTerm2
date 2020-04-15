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
