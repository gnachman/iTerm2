//
//  iTermObjectPool.m
//  iTerm
//
//  Created by George Nachman on 3/3/14.
//
//

#import "iTermObjectPool.h"
#import <stdatomic.h>

@interface iTermObjectPool ()
- (void)recycleObject:(iTermPooledObject *)object;
@end

@interface iTermPooledObject ()

- (instancetype)initWithPool:(iTermObjectPool *)pool collectionNumber:(int)collectionNumber;
- (int)poolCollectionNumber;

@end

@implementation iTermPooledObject {
    iTermObjectPool *_pool;  // Weak reference
    int _collectionNumber;
}

- (instancetype)initWithPool:(iTermObjectPool *)pool collectionNumber:(int)collectionNumber {
    self = [super init];
    if (self) {
        _pool = pool;
        _collectionNumber = collectionNumber;
    }
    return self;
}

- (void)destroyPooledObject {
}

- (void)dealloc {
    [self destroyPooledObject];
    [super dealloc];
}

- (int)poolCollectionNumber {
    return _collectionNumber;
}

- (void)recycleObject {
    [_pool recycleObject:self];
}

@end

typedef struct {
    iTermPooledObject **objects;
    int count;
    int allocated;
    int freed;

    // The queue is used as a mutual exclusion lock.
    // http://www.fieryrobot.com/blog/2010/09/01/synchronization-using-grand-central-dispatch/
    dispatch_queue_t queue;
} ObjectCollection;

@implementation iTermObjectPool {
    ObjectCollection **_collections;
    int _objectsPerCollection;
    int _numCollections;
    _Atomic int _counter;
    Class _class;
}

- (instancetype)initWithClass:(Class)theClass
        collections:(int)numCollections
      objectsPerCollection:(int)objectsPerCollection {
    self = [super init];
    if (self) {
        _numCollections = numCollections;
        _objectsPerCollection = objectsPerCollection;
        _collections = malloc(sizeof(ObjectCollection *) * numCollections);
        for (int i = 0 ; i < numCollections; i++) {
            _collections[i] = calloc(1, sizeof(ObjectCollection));
            _collections[i]->objects = malloc(sizeof(iTermPooledObject *) * objectsPerCollection);
            NSString *queueName =
                [NSString stringWithFormat:@"com.iterm2.ObjectPool.%@.collection%d", _class, i];
            _collections[i]->queue = dispatch_queue_create([queueName UTF8String], 0);
        }
        _class = theClass;
    }
    return self;
}

// Dealing with multiple threads gets hairy and this class is intended to have global scope and
// lifetime, so dealloc asserts.
- (void)dealloc {
    assert(false);
    [super dealloc];
}

- (NSString *)description {
    int unused = 0;
    int allocated = 0;
    int freed = 0;
    for (int i = 0; i < _numCollections; i++) {
        unused += _collections[i]->count;
        allocated += _collections[i]->allocated;
        freed += _collections[i]->freed;
    }
    int capacity = _objectsPerCollection * _numCollections;
    return [NSString stringWithFormat:@"<%@: %p class=%@ capacity=%d ever-allocated=%d currently-allocated=%d in-use=%d>",
            [self class], self, _class, capacity, allocated, allocated - freed, allocated - freed - unused];
}

- (iTermPooledObject *)pooledObject {
    int startIndex = atomic_fetch_add_explicit(&_counter, 1, memory_order_relaxed) % _numCollections;

    for (int j = startIndex; j < startIndex + _numCollections; j++) {
        int collectionIndex = j % _numCollections;
        ObjectCollection *collection = _collections[collectionIndex];

        __block iTermPooledObject *obj = nil;
        dispatch_sync(collection->queue, ^{
            if (collection->count > 0) {
                obj = collection->objects[--collection->count];
            }
        });
        if (obj) {
            return obj;
        }
    }

    ObjectCollection *collection = _collections[startIndex];
    dispatch_sync(collection->queue, ^{
        collection->allocated++;
    });

    // The analyzer complains here but it's actually correct because the pool implicitly owns the object.
    return [[_class alloc] initWithPool:self collectionNumber:startIndex];
}

- (void)synchronizedRecycleObject:(iTermPooledObject *)obj
                     toCollection:(ObjectCollection *)collection {
    if (collection->count < _objectsPerCollection) {
        [obj destroyPooledObject];
        collection->objects[collection->count++] = obj;
    } else {
        [obj release];
    }
}

- (void)recycleObject:(iTermPooledObject *)obj {
    int collectionIndex = [obj poolCollectionNumber];
    ObjectCollection *collection = _collections[collectionIndex];
    dispatch_sync(collection->queue, ^{
        [self synchronizedRecycleObject:obj toCollection:collection];
    });
}

@end
