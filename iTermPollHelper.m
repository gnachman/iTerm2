//
//  iTermPollHelper.m
//  iTerm
//
//  Created by George Nachman on 3/26/14.
//
//

#import "iTermPollHelper.h"
#include <poll.h>

char gBuffer[100];
@interface CStructMutableArray : NSObject

@property(nonatomic, readonly) int count;

- (id)initWithStructSize:(size_t)structSize;
- (void)addObjectWithBlock:(void (^)(void *ptr))assignBlock;
- (void *)pointerToObjectAtIndex:(NSInteger)index;

@end

@implementation CStructMutableArray {
    char *_storage;
    size_t _structSize;
    int _count;
    int _capacity;
}

- (id)initWithStructSize:(size_t)structSize {
    self = [super init];
    if (self) {
        _capacity = 1;
        _structSize = structSize;
        _storage = calloc(_capacity, _structSize);
    }
    return self;
}

- (int)count {
    return _count;
}

- (void)addObjectWithBlock:(void (^)(void *ptr))assignBlock {
    if (_capacity == _count) {
        int originalSizeInBytes = _capacity * _structSize;
        _capacity *= 2;
        _storage = realloc(_storage, _capacity * _structSize);
        memset(_storage + originalSizeInBytes, 0, originalSizeInBytes);
    }
    int index = _count;
    ++_count;
    assignBlock(_storage + (_structSize * index));
}

- (void *)pointerToObjectAtIndex:(NSInteger)index {
    assert(index >= 0 && index < _count);
    return _storage + (_structSize * index);
}

@end

@implementation iTermPollHelper {
    CStructMutableArray *_fds;
    NSMutableArray *_identifiers;  // parallel to fds
    NSMutableDictionary *_index;  // file descriptor -> index
}

NSMutableString *gLog;

- (id)init {
    gLog = [[NSMutableString alloc] init];
    self = [super init];
    if (self) {
        _fds = [[CStructMutableArray alloc] initWithStructSize:sizeof(struct pollfd)];
        _identifiers = [[NSMutableArray alloc] init];
        _index = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)reset {
    LOG(@"Reset");
    [_fds release];
    _fds = [[CStructMutableArray alloc] initWithStructSize:sizeof(struct pollfd)];
    [_identifiers removeAllObjects];
    [_index removeAllObjects];
}

- (void)addFileDescriptor:(int)fd
               forReading:(BOOL)reading
                  writing:(BOOL)writing
               identifier:(NSObject *)identifier {
    LOG(@"Poll on %d", fd);
    _index[@(fd)] = @(_fds.count);
    [_identifiers addObject:identifier ?: [NSNull null]];
    [_fds addObjectWithBlock:^(void *ptr) {
        struct pollfd *pollfd = (struct pollfd *)ptr;
        pollfd->fd = fd;
        pollfd->events = ((reading ? (POLLIN) : 0) | (writing ? POLLOUT : 0));
        pollfd->revents = 0;
    }];
}

void TryReadingFromFd(int fd) {
    char buffer[1];
    int n = read(fd, buffer, 1);
    NSLog(@"Read returns %d, errno=%d", n, errno);
}

- (void)poll {
    struct pollfd *pollfds = [_fds pointerToObjectAtIndex:0];
    int count = _fds.count;
    int numDescriptors;
    do {
        LOG(@"Start poll");
        numDescriptors = poll(pollfds, count, -1);
        LOG(@"Return from poll");
        assert(numDescriptors != 0);
        if (numDescriptors < 0) {
            assert(errno == EAGAIN || errno == EINTR);
        }
    } while (numDescriptors < 0);
}

- (NSUInteger)flagsForFd:(int)fd {
    NSNumber *n = _index[@(fd)];
    if (!n) {
        return 0;
    }
    int index = [n intValue];
    struct pollfd *pollfd = [_fds pointerToObjectAtIndex:index];
    NSUInteger flags = 0;
    assert(!(pollfd->revents & POLLNVAL));
    if (pollfd->revents & (POLLIN | POLLERR | POLLHUP)) {
        LOG(@"fd %d is readable", fd);
        flags |= kiTermPollHelperFlagReadable;
    }
    if (pollfd->revents & POLLOUT) {
        LOG(@"fd %d is writable", fd);
        flags |= kiTermPollHelperFlagWritable;
    }
    return flags;
}

@end
