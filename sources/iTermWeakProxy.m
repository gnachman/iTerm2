//
//  iTermWeakProxy.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/17/19.
//

#import "iTermWeakProxy.h"

@implementation iTermWeakProxy

- (id)initWithObject:(id)object {
    _object = object;
    return self;
}

- (BOOL)isKindOfClass:(Class)aClass {
    return [super isKindOfClass:aClass] || [_object isKindOfClass:aClass];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    invocation.target = _object;
    [invocation invoke];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    return [_object methodSignatureForSelector:sel];
}

@end
