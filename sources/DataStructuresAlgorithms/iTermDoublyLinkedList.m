//
//  iTermDoublyLinkedList.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/5/19.
//

#import "iTermDoublyLinkedList.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermDoublyLinkedList

- (void)prepend:(iTermDoublyLinkedListEntry *)object {
    assert(object);
    assert(object.dll == nil);
    assert(object.dllNext == nil);
    assert(object.dllPrevious == nil);

    _count++;
    object.dll = self;
    if (!self.first) {
        assert(!self.last);
        _first = object;
        _last = object;
        return;
    }
    assert(self.last);

    _first.dllPrevious = object;
    object.dllNext = _first;
    _first = object;
}

- (void)remove:(iTermDoublyLinkedListEntry *)object {
    assert(object);
    assert(object.dll == self);
    _count--;
    if (self.first == object) {
        _first = object.dllNext;
    }
    if (self.last == object) {
        _last = object.dllPrevious;
    }
    object.dllPrevious.dllNext = object.dllNext;
    object.dllNext.dllPrevious = object.dllPrevious;
    object.dll = nil;
    object.dllNext = nil;
    object.dllPrevious = nil;
}

@end

@implementation iTermDoublyLinkedListEntry

- (instancetype)initWithObject:(id)object {
    self = [super init];
    if (self) {
        _object = object;
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END
