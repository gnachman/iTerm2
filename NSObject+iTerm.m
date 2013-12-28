//
//  NSObject+iTerm.m
//  iTerm
//
//  Created by George Nachman on 12/22/13.
//
//

#import "NSObject+iTerm.h"

@implementation NSObject (iTerm)

- (void)performSelectorWithObjects:(NSArray *)tuple {
    SEL selector = NSSelectorFromString(tuple[0]);
    NSArray *objects = tuple[1];

    NSMethodSignature *signature  = [self methodSignatureForSelector:selector];
    NSInvocation  *invocation = [NSInvocation invocationWithMethodSignature:signature];
    
    NSObject *temp[objects.count];
    
    [invocation setTarget:self];
    [invocation setSelector:selector];
    for (int i = 0; i < objects.count; i++) {
        temp[i] = objects[i];
        [invocation setArgument:&temp[i] atIndex:i + 2];
    }
    [invocation invoke];
}

- (void)performSelectorOnMainThread:(SEL)selector withObjects:(NSArray *)objects {
    [self performSelectorOnMainThread:@selector(performSelectorWithObjects:)
                           withObject:@[ NSStringFromSelector(selector), objects ]
                        waitUntilDone:NO];
}

@end
