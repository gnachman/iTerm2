//
//  iTermBijection.m
//  iTerm2
//
//  Created by George Nachman on 11/1/24.
//

#import "iTermBijection.h"
#import "iTerm2SharedARC-Swift.h"

@implementation iTermBijection {
    iTermUntypedBijection *_impl;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _impl = [[iTermUntypedBijection alloc] init];
    }
    return self;
}

- (void)link:(id)left to:(id)right {
    [_impl link:left to:right];
}

- (id)objectForLeft:(id)left {
    return [_impl objectForLeft:left];
}

- (id)objectForRight:(id)right {
    return [_impl objectForRight:right];
}

@end
