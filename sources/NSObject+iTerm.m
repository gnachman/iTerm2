//
//  NSObject+iTerm.m
//  iTerm
//
//  Created by George Nachman on 12/22/13.
//
//

#import "NSObject+iTerm.h"

#import <objc/runtime.h>

@implementation iTermDelayedPerform
@end

@implementation NSObject (iTerm)

+ (BOOL)object:(NSObject *)a isEqualToObject:(NSObject *)b {
    if (a == b) {
        return YES;
    }
    return [a isEqual:b];
}

+ (instancetype)castFrom:(id)object {
    if ([object isKindOfClass:[self class]]) {
        return object;
    } else {
        return nil;
    }
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
    iTermDelayedPerform *delayedPerform = [[iTermDelayedPerform alloc] init];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       if (!delayedPerform.canceled) {
                           delayedPerform.completed = YES;
                           block();
                       }
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

- (void)it_setAssociatedObject:(id)associatedObject forKey:(void *)key {
    objc_setAssociatedObject(self,
                             key,
                             associatedObject,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)it_setWeakAssociatedObject:(id)associatedObject forKey:(void *)key {
    objc_setAssociatedObject(self,
                             key,
                             associatedObject,
                             OBJC_ASSOCIATION_ASSIGN);
}

- (id)it_associatedObjectForKey:(void *)key {
    return objc_getAssociatedObject(self, key);
}

- (void)it_performNonObjectReturningSelector:(SEL)selector withObject:(id)object {
    IMP imp = [self methodForSelector:selector];
    void (*func)(id, SEL, id) = (void *)imp;
    func(self, selector, object);
}

- (id)it_performAutoreleasedObjectReturningSelector:(SEL)selector withObject:(id)object {
    IMP imp = [self methodForSelector:selector];
    id (*func)(id, SEL, id) = (void *)imp;
    return func(self, selector, object);
}

- (BOOL)it_isSafeForPlist {
    if ([self isKindOfClass:[NSString class]]) {
        return YES;
    }
    if ([self isKindOfClass:[NSNumber class]]) {
        return YES;
    }
    if ([self isKindOfClass:[NSDate class]]) {
        return YES;
    }
    if ([self isKindOfClass:[NSData class]]) {
        return YES;
    }
    NSArray *array = [NSArray castFrom:self];
    if (array) {
        for (NSObject *obj in array) {
            if (![obj it_isSafeForPlist]) {
                return NO;
            }
        }
        return YES;
    }

    NSDictionary *dictionary = [NSDictionary castFrom:self];
    if (dictionary) {
        for (NSObject *key in dictionary) {
            if (![key it_isSafeForPlist]) {
                return NO;
            }
            if (![dictionary[key] it_isSafeForPlist]) {
                return NO;
            }
        }
        return YES;
    }

    return NO;
}

- (NSString *)it_invalidPathInPlist {
    return [self it_invalidPathInPlist:@"/"];
}

- (NSString *)it_invalidPathInPlist:(NSString *)path {
    if ([self isKindOfClass:[NSString class]]) {
        return nil;
    }
    if ([self isKindOfClass:[NSNumber class]]) {
        return nil;
    }
    if ([self isKindOfClass:[NSDate class]]) {
        return nil;
    }
    if ([self isKindOfClass:[NSData class]]) {
        return nil;
    }
    NSArray *array = [NSArray castFrom:self];
    if (array) {
        int i = 0;
        for (NSObject *obj in array) {
            NSString *oops = [obj it_invalidPathInPlist:[NSString stringWithFormat:@"%@array[%@]/", path, @(i)]];
            if (oops) {
                return oops;
            }
            i++;
        }
        return nil;
    }

    NSDictionary *dictionary = [NSDictionary castFrom:self];
    if (dictionary) {
        for (NSObject *key in dictionary) {
            NSString *oops = [key it_invalidPathInPlist:[NSString stringWithFormat:@"%@dict key=%@ class=%@", path, key, NSStringFromClass([key class])]];
            if (oops) {
                return oops;
            }
            id value = dictionary[key];
            oops = [value it_invalidPathInPlist:[NSString stringWithFormat:@"%@dict[%@]/", path, key]];
            if (oops) {
                return oops;
            }
        }
        return nil;
    }

    return [NSString stringWithFormat:@"%@ has type %@", path, NSStringFromClass([self class])];
}

@end
