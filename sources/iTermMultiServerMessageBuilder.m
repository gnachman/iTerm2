//
//  iTermMultiServerMessageBuilder.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/20.
//

#import "iTermMultiServerMessageBuilder.h"

#import "DebugLogging.h"

@implementation iTermMultiServerMessageBuilder {
    NSMutableData *_accumulator;
    NSNumber *_fileDescriptor;
    iTermMultiServerMessage *_message;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _accumulator = [NSMutableData data];
    }
    return self;
}

- (void)dealloc {
    if (!_message && _fileDescriptor && _fileDescriptor.intValue >= 0) {
        DLog(@"Close file descriptor %d in message that was never decoded", _fileDescriptor.intValue);
        close(_fileDescriptor.intValue);
    }
}

- (void)appendBytes:(void *)bytes length:(NSInteger)length {
    [_accumulator appendBytes:bytes
                       length:length];
}

- (void)setFileDescriptor:(int)fileDescriptor {
    _fileDescriptor = @(fileDescriptor);
}

- (NSInteger)length {
    return _accumulator.length;
}

- (iTermMultiServerMessage *)message {
    if (_message) {
        return _message;
    }
    _message = [[iTermMultiServerMessage alloc] initWithData:_accumulator
                                              fileDescriptor:_fileDescriptor];
    return _message;
}

@end
