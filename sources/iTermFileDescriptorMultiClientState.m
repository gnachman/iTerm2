//
//  iTermFileDescriptorMultiClientState.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/20.
//

#import "iTermFileDescriptorMultiClientState.h"

@implementation iTermFileDescriptorMultiClientState {
    dispatch_source_t _writeSource;
    NSMutableArray *_writeQueue;
    dispatch_source_t _readSource;
    NSMutableArray *_readQueue;
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue {
    self = [super initWithQueue:queue];
    if (self) {
        _children = [NSMutableArray array];
        _pendingLaunches = [NSMutableDictionary dictionary];
        _readFD = -1;
        _writeFD = -1;
        _serverPID = -1;
        _writeQueue = [NSMutableArray array];
        _readQueue = [NSMutableArray array];
    }
    return self;
}

- (void)setFileDescriptorNonblocking:(int)fd {
    const int flags = fcntl(fd, F_GETFL, 0);
    if (flags != -1) {
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    }
}

- (void)setWriteFD:(int)writeFD {
    if (writeFD >= 0) {
        [self setFileDescriptorNonblocking:writeFD];
    }
    const BOOL cancelWrites = (writeFD < 0 && _writeFD >= 0);
    _writeFD = writeFD;
    if (cancelWrites) {
        [self didBecomeWritable];
        assert(_writeQueue.count == 0);
    }
}

- (void)setReadFD:(int)readFD {
    if (readFD >= 0) {
        [self setFileDescriptorNonblocking:readFD];
    }
    const BOOL cancelReads = (readFD < 0 && _readFD >= 0);
    _readFD = readFD;
    if (cancelReads) {
        [self didBecomeReadable];
        assert(_readQueue.count == 0);
    }
}

// There is an important subtlety here. If you call whenReadable: from within a
// whenReadable block, that call gets inserted at the head of the list. That is
// essential for the two-stage reads that are performed here: first we read the
// length and then the payload. We can't allow another read to be interposed
// between them. As long as whenReadable: for the payload is called from within
// the whenReadable block for the length, it is safe.
- (void)whenReadable:(void (^)(iTermFileDescriptorMultiClientState *))block {
    if (_readFD < 0) {
        block(self);
        return;
    }
    [_readQueue addObject:[block copy]];
    if (_readSource) {
        return;
    }
    _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _readFD, 0, self.queue);
    if (!_readSource) {
        DLog(@"Failed to create dispatch source for read!");
        close(_readFD);
        _readFD = -1;
        return;
    }

    __weak __typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_readSource, ^{
        [weakSelf didBecomeReadable];
    });

    dispatch_resume(_readSource);
}

- (void)didBecomeReadable {
    NSArray *queue = [_readQueue copy];
    [_readQueue removeAllObjects];

    for (void (^block)(iTermFileDescriptorMultiClientState *) in queue) {
        if (_readQueue.count) {
            [_readQueue addObject:block];
        } else {
            block(self);
        }
    }
    if (_readQueue.count == 0 && _readSource != nil) {
        dispatch_source_cancel(_readSource);
        _readSource = nil;
    }
}

// See the comment on whenReadable:. This works the same way.
- (void)whenWritable:(void (^)(iTermFileDescriptorMultiClientState *state))block {
    if (_writeFD < 0) {
        block(self);
        return;
    }

    [_writeQueue addObject:[block copy]];
    if (_writeSource) {
        return;
    }
    _writeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, _writeFD, 0, self.queue);
    if (!_writeSource) {
        DLog(@"Failed to create dispatch source for write!");
        close(_writeFD);
        _writeFD = -1;
        return;
    }

    __weak __typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_writeSource, ^{
        [weakSelf didBecomeWritable];
    });

    dispatch_resume(_writeSource);
}

- (void)didBecomeWritable {
    NSArray *queue = [_writeQueue copy];
    [_writeQueue removeAllObjects];

    for (void (^block)(iTermFileDescriptorMultiClientState *) in queue) {
        if (_writeQueue.count) {
            [_writeQueue addObject:block];
        } else {
            block(self);
        }
    }
    if (_writeQueue.count == 0 && _writeSource != nil) {
        dispatch_source_cancel(_writeSource);
        _writeSource = nil;
    }
}

@end
