//
//  NSObject+iTerm.m
//  iTerm
//
//  Created by George Nachman on 12/22/13.
//
//

#import "NSObject+iTerm.h"

#import "iTermWeakProxy.h"
#import "NSJSONSerialization+iTerm.h"

#import <objc/runtime.h>

@implementation iTermDelayedPerform
@end

@interface NSNumber(Approximate)
@end

@implementation NSNumber(Approximate)

- (BOOL)isApproximatelyEqual:(id)obj epsilon:(double)epsilon {
    if (self == obj) {
        return YES;
    }
    if ([self isEqual:obj]) {
        return YES;
    }
    NSNumber *other = [NSNumber castFrom:obj];
    if (!other) {
        return NO;
    }
    return fabs(self.doubleValue - other.doubleValue) < epsilon;
}

@end

@interface NSDictionary(Approximate)
@end

@implementation NSDictionary(Approximate)

- (BOOL)isApproximatelyEqual:(id)obj epsilon:(double)epsilon {
    if (self == obj) {
        return YES;
    }
    if ([self isEqual:obj]) {
        return YES;
    }
    NSDictionary *other = [NSDictionary castFrom:obj];
    if (!other) {
        return NO;
    }
    if (self.count != other.count) {
        return NO;
    }
    for (NSString *key in self.allKeys) {
        id myValue = self[key];
        id otherValue = other[key];
        if (!otherValue) {
            return NO;
        }
        if (![NSObject object:myValue isApproximatelyEqualToObject:otherValue epsilon:epsilon]) {
            return NO;
        }
    }
    return YES;
}

@end

@interface NSArray(Approximate)
@end

@implementation NSArray(Approximate)

- (BOOL)isApproximatelyEqual:(id)obj epsilon:(double)epsilon {
    if (self == obj) {
        return YES;
    }
    if ([self isEqual:obj]) {
        return YES;
    }
    NSArray *other = [NSArray castFrom:obj];
    if (!other) {
        return NO;
    }
    if (self.count != other.count) {
        return NO;
    }
    const NSInteger count = self.count;
    for (NSInteger i = 0; i < count; i++) {
        if (![NSObject object:self[i] isApproximatelyEqualToObject:other[i] epsilon:epsilon]) {
            return NO;
        }
    }
    return YES;
}

@end

@implementation NSObject (iTerm)

+ (BOOL)object:(NSObject *)a isEqualToObject:(NSObject *)b {
    if (a == b) {
        return YES;
    }
    return [a isEqual:b];
}

+ (BOOL)object:(__kindof NSObject *)a isApproximatelyEqualToObject:(__kindof NSObject *)b epsilon:(double)epsilon {
    if (a == b) {
        return YES;
    }
    if ([a respondsToSelector:@selector(isApproximatelyEqual:epsilon:)]) {
        return [a isApproximatelyEqual:b epsilon:epsilon];
    }
    if ([b respondsToSelector:@selector(isApproximatelyEqual:epsilon:)]) {
        return [b isApproximatelyEqual:a epsilon:epsilon];
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

+ (instancetype)forceCastFrom:(id)object {
    assert(object);
    id result = [self castFrom:object];
    assert(result);
    return result;
}

+ (void)it_enumerateDynamicProperties:(void (^)(NSString *name))block {
    unsigned int propcount = 0;
    objc_property_t *props = class_copyPropertyList(self, &propcount);
    for (unsigned int i = 0; i < propcount; i++) {
        objc_property_t prop = props[i];
        char *value = property_copyAttributeValue(prop, "D");
        if (value == nil) {
            continue;
        }
        free(value);
        const char *name = property_getName(prop);
        block([NSString stringWithUTF8String:name]);
    }
    free(props);
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

- (void)it_setAssociatedObject:(id)associatedObject forKey:(const void *)key {
    objc_setAssociatedObject(self,
                             key,
                             associatedObject,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)it_setWeakAssociatedObject:(id)associatedObject forKey:(const void *)key {
    objc_setAssociatedObject(self,
                             key,
                             associatedObject,
                             OBJC_ASSOCIATION_ASSIGN);
}

- (id)it_associatedObjectForKey:(const void *)key {
    return objc_getAssociatedObject(self, key);
}

- (void)it_performNonObjectReturningSelector:(SEL)selector withObject:(id)object {
    IMP imp = [self methodForSelector:selector];
    void (*func)(id, SEL, id) = (void *)imp;
    func(self, selector, object);
}

- (void)it_performNonObjectReturningSelector:(SEL)selector withObject:(id)object1 withObject:(id)object2 {
    IMP imp = [self methodForSelector:selector];
    void (*func)(id, SEL, id, id) = (void *)imp;
    func(self, selector, object1, object2);
}

- (void)it_performNonObjectReturningSelector:(SEL)selector withObject:(id)object1 object:(id)object2 object:(id)object3 {
    IMP imp = [self methodForSelector:selector];
    void (*func)(id, SEL, id, id, id) = (void *)imp;
    func(self, selector, object1, object2, object3);
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
            if (![key isKindOfClass:[NSString class]]) {
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
            if (![key isKindOfClass:[NSString class]]) {
                return [NSString stringWithFormat:@"key %@ in dictionary at %@ is %@, not NSString", key, path, NSStringFromClass([key class])];
            }
        }
        return nil;
    }

    return [NSString stringWithFormat:@"%@ has type %@", path, NSStringFromClass([self class])];
}

- (instancetype)it_weakProxy {
    return (id)[[iTermWeakProxy alloc] initWithObject:self];
}

- (NSString *)tastefulDescription {
    return [self description];
}

- (id)it_jsonSafeValue {
    return self;
}

- (NSString *)it_addressString {
    return [NSString stringWithFormat:@"%p", self];
}

- (NSData *)it_keyValueCodedData {
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:NO];
    [archiver encodeObject:self forKey:@"root"];
    [archiver finishEncoding];
    return [archiver encodedData];
}

+ (instancetype)it_fromKeyValueCodedData:(NSData *)data {
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:nil];
    if (!unarchiver) {
        return nil;
    }
    NSArray *classes = @[
        [NSArray class],
        [NSDictionary class],
        [NSString class],
        [NSNumber class],
        [NSDate class]
    ];
    id object = [self castFrom:[unarchiver decodeObjectOfClasses:[NSSet setWithArray:classes] forKey:@"root"]];
    [unarchiver finishDecoding];
    return object;
}

- (NSString *)jsonEncoded {
    return [NSJSONSerialization it_jsonStringForObject:self];
}

+ (instancetype)fromJsonEncodedString:(NSString *)string {
    return [self castFrom:[NSJSONSerialization it_objectForJsonString:string]];
}

@end
