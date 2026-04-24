//
//  iTermTaskQueue.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/29/24.
//
// NOTE: This file assumes manual reference counting to minimze overhead due to ARC.

extern "C" {
#import "iTermTaskQueue.h"
#import "AtomicHelpers.h"
}

#import <os/lock.h>
#import <vector>

class iTermTaskArray {
public:
    iTermTaskArray() : _head(0) {
    }

    ~iTermTaskArray() {
        for (auto task : _tasks) {
            [task release];
        }
    }

    iTermQueueableTask _Nullable dequeue() {
        if (_head >= _tasks.size()) {
            return nil;
        }
        auto value = _tasks[_head];
        _tasks[_head] = nullptr;
        _head += 1;
        return [value autorelease];
    }

    void enqueue(iTermQueueableTask task) {
        _tasks.push_back([task retain]);
    }

    NSUInteger count() {
        return _tasks.size() - _head;
    }

    BOOL canAppend() {
        return _head == 0;
    }

    // I don't feel like dealing with reference counting pain so no copy or move for you.
    iTermTaskArray(const iTermTaskArray&) = delete;
    iTermTaskArray& operator=(const iTermTaskArray&) = delete;
    iTermTaskArray(iTermTaskArray&&) = delete;
    iTermTaskArray& operator=(iTermTaskArray&&) = delete;

private:
    std::vector<iTermQueueableTask> _tasks;

    // _head is the first not-yet-dequeued index in _tasks.
    NSUInteger _head;
};

@implementation iTermTaskQueue {
    std::vector<iTermTaskArray *> _arrays;
    os_unfair_lock _mutex;
    iTermAtomicInt64 *_flags;
    NSUInteger _count;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _arrays.push_back(new iTermTaskArray());
        _mutex = OS_UNFAIR_LOCK_INIT;
        _flags = iTermAtomicInt64Create();
    }
    return self;
}

- (void)dealloc {
    iTermAtomicInt64Free(_flags);
    for (auto a : _arrays) {
        delete a;
    }
    [super dealloc];
}

- (NSUInteger)count {
    os_unfair_lock_lock(&_mutex);
    const NSUInteger value = _count;
    os_unfair_lock_unlock(&_mutex);
    return value;
}

// Caller must lock mutex
- (iTermTaskArray *)lastArray {
    if (_arrays.size() == 0) {
        return nil;
    } else {
        return _arrays.back();
    }
}

- (void)appendTask:(iTermQueueableTask)task {
    os_unfair_lock_lock(&_mutex);
    iTermTaskArray *array = self.lastArray;
    if (array != nullptr && array->canAppend()) {
        array->enqueue(task);
    } else {
        auto array = new iTermTaskArray();
        array->enqueue(task);
        _arrays.push_back(array);
    }
    _count += 1;
    os_unfair_lock_unlock(&_mutex);
}

- (void)appendTasks:(NSArray<iTermQueueableTask> *)tasks {
    const NSUInteger count = tasks.count;

    os_unfair_lock_lock(&_mutex);

    _count += count;
    iTermTaskArray *existingArray = self.lastArray;
    if (existingArray != nullptr && existingArray->canAppend()) {
        for (void (^task)(void) in tasks) {
            existingArray->enqueue(task);
        }
    } else {
        auto array = new iTermTaskArray();
        for (void (^task)(void) in tasks) {
            array->enqueue(task);
        }
        _arrays.push_back(array);
    }
    os_unfair_lock_unlock(&_mutex);
}

// Dequeue from the first array with a nonnil member. Rather than deleting the item, which gives
// quadratic performance, just nil it out. When a TaskArray becomes empty it can be removed from the
// list of task arrays. Since the list of task arrays will never have more than 2 elements, it's fast.
// Appends always go to the last task array. If the last task array has already been dequeued from
// then a new TaskArray is crated and appends to go it.
//
// taskArray = [ [] ]
// append(t1)
// taskARray = [ [t1] ]
// append(t2)
// taskArray = [ [t1, t2] ]
// dequeue() -> t1
// taskArray = [ [nil, t2] ]
// append(t3)
// taskArray = [ [nil, t2], [ t3 ] ]
// dequeue() -> t2
// taskArray = [ [], [ t3 ] ]
// append(t4)
// taskArray = [ [], [ t3, t4 ] ]
// dequeue() -> t3
// taskArray = [ [t4] ]
- (iTermQueueableTask)dequeue {
    os_unfair_lock_lock(&_mutex);

    void (^task)(void) = nil;
    while (_arrays.size() > 1) {
        task = _arrays[0]->dequeue();
        if (task != nullptr) {
            break;
        }
        auto a = _arrays.front();
        _arrays.erase(_arrays.begin());
        delete a;
    }
    if (task == nullptr && _arrays.size() > 0) {
        task = _arrays[0]->dequeue();
    }
    if (task != nullptr) {
        _count -= 1;
    }
    os_unfair_lock_unlock(&_mutex);
    return task;
}

- (int64_t)setFlag:(int64_t)flag {
    return iTermAtomicInt64BitwiseOr(_flags, flag);
}

- (int64_t)resetFlags {
    return iTermAtomicInt64GetAndReset(_flags);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p count=%@>",
            NSStringFromClass([self class]), self, @(self.count)];
}
@end
