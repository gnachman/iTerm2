//
//  iTermLRUDictionary.m
//  iTerm2
//
//  Created by George Nachman on 11/1/24.
//

#import "iTermLRUDictionary.h"

#import "iTerm2SharedARC-Swift.h"

@implementation iTermLRUDictionary {
    iTermUntypedLRUDictionary *_impl;
}

- (instancetype)initWithMaximumSize:(NSInteger)maximumSize {
    self = [super init];
    if (self) {
        _impl = [[iTermUntypedLRUDictionary alloc] initWithMaximumSize:maximumSize];
    }
    return self;
}

- (void)addObjectWithKey:(id)key value:(id)value cost:(NSInteger)cost {
    [_impl addObjectWithKey:key value:value cost:cost];
}

- (void)removeObjectForKey:(id)key {
    [_impl removeObjectForKey:key];
}

- (id)objectForKey:(id)key {
    return [_impl objectForKey:key];
}

- (void)removeAllObjects {
    [_impl removeAllObjects];
}

- (id)objectForKeyedSubscript:(id)key {
    return [_impl objectForKey:key];
}

@end
