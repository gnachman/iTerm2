//
//  NSObject+iTerm.m
//  iTerm
//
//  Created by George Nachman on 12/22/13.
//
//

#import "NSObject+iTerm.h"

@implementation iTermDelayedPerform
@end

@implementation NSObject (iTerm)

+ (BOOL)object:(NSObject *)a isEqualToObject:(NSObject *)b {
    if (a == b) {
        return YES;
    }
    return [a isEqual:b];
}

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

- (iTermDelayedPerform *)performBlock:(void (^)(void))block afterDelay:(NSTimeInterval)delay {
    [self retain];
    iTermDelayedPerform *delayedPerform = [[iTermDelayedPerform alloc] init];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       if (!delayedPerform.canceled) {
                           delayedPerform.completed = YES;
                           block();
                       }
                       [self release];
                       [delayedPerform release];
                   });
    return delayedPerform;
}

- (instancetype)nilIfNull {
    if ([self isKindOfClass:[NSNull class]]) {
        return nil;
    } else {
        return self;
    }
}

@end
