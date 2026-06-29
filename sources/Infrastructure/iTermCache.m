//
//  iTermCache.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/5/19.
//

#import "iTermCache.h"

#import "DebugLogging.h"
#import "iTermDoublyLinkedList.h"

@interface iTermCacheEntry: NSObject
@property (nonatomic, strong) id key;
@property (nonatomic, strong) id object;
@end

@implementation iTermCacheEntry
@end

@implementation iTermCache {
    // All ivars should be accessed only on _queue.
    NSInteger _capacity;
    NSMutableDictionary<id, iTermDoublyLinkedListEntry<iTermCacheEntry *> *> *_dict;
    iTermDoublyLinkedList *_mru;
    dispatch_queue_t _queue;
}

- (instancetype)initWithCapacity:(NSInteger)capacity {
    self = [super init];
    if (self) {
        _capacity = capacity;
        _dict = [NSMutableDictionary dictionaryWithCapacity:capacity];
        _mru = [[iTermDoublyLinkedList alloc] init];
        _queue = dispatch_queue_create("com.iterm2.cache", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (id)objectForKeyedSubscript:(id)key {
    __block id result = nil;
    dispatch_sync(_queue, ^{
        iTermDoublyLinkedListEntry<iTermCacheEntry *> *entry = self->_dict[key];
        if (!entry) {
            return;
        }
        [self->_mru remove:entry];
        [self->_mru prepend:entry];
        result = entry.object.object;
    });
    return result;
}

- (void)setObject:(id)obj forKeyedSubscript:(id)key {
    dispatch_sync(_queue, ^{
        iTermDoublyLinkedListEntry<iTermCacheEntry *> *dllEntry = self->_dict[key];
        if (dllEntry) {
            [self->_mru remove:dllEntry];
        }
        iTermCacheEntry *cacheEntry = [[iTermCacheEntry alloc] init];
        cacheEntry.key = key;
        cacheEntry.object = obj;
        dllEntry = [[iTermDoublyLinkedListEntry alloc] initWithObject:cacheEntry];
        self->_dict[key] = dllEntry;
        [self->_mru prepend:dllEntry];
        DLog(@"%@ Insert object %@ with key %@", self, obj, key);
        assert(self->_dict.count == self->_mru.count);

        while (self->_mru.count > self->_capacity) {
            iTermDoublyLinkedListEntry<iTermCacheEntry *> *lru = self->_mru.last;
            DLog(@"%@ Evict object %@ with key %@", self, lru.object.object, lru.object.key);
            assert(self->_dict[lru.object.key]);
            [self->_dict removeObjectForKey:lru.object.key];
            [self->_mru remove:lru];
            assert(self->_dict.count == self->_mru.count);
        }
    });
}

@end
