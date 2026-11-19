//
//  RuntimeSnapshotFixtures.m
//  ModernTests
//

#import "RuntimeSnapshotFixtures.h"

#import <objc/runtime.h>

@implementation RuntimeSnapshotFixtureBase

+ (void)baseClassMethod {
}

+ (void)initialize {
}

+ (id)valueForKey:(NSString *)key {
    return nil;
}

- (void)baseMethod {
}

- (NSInteger)overriddenMethod {
    return 1;
}

@end

@implementation RuntimeSnapshotFixture

@dynamic dynamicValue;

static NSString *sRuntimeSnapshotFixtureClassProperty = @"";

+ (NSString *)classProperty {
    return sRuntimeSnapshotFixtureClassProperty;
}

+ (void)setClassProperty:(NSString *)classProperty {
    sRuntimeSnapshotFixtureClassProperty = [classProperty copy];
}

// Overrides a class method of a superclass that is not the root class.
+ (void)baseClassMethod {
}

+ (NSString *)classMethodWithInteger:(int)value {
    return [@(value) stringValue];
}

- (NSString *)instanceMethodWithInteger:(int)value object:(id)object {
    return [NSString stringWithFormat:@"%d %@", value, object];
}

- (NSInteger)overriddenMethod {
    return 2;
}

- (NSInteger)readonlyValue {
    return 3;
}

- (void)protocolMethod {
}

- (void)directMethod {
}

@end

@implementation RuntimeSnapshotDuplicateFixture

- (NSString *)duplicatedMethod {
    return @"Objective-C";
}

+ (NSString *)duplicatedClassMethod {
    return @"Objective-C";
}

@end

@implementation RuntimeSnapshotPropertyRepeatFixture
@end

@implementation RuntimeSnapshotPropertyRepeatFixture (RuntimeSnapshotCategory)
@end

@implementation RuntimeSnapshotLoadFixture

+ (void)load {
    // An implementation made at run time from a block, whose code is not in
    // any loaded image.
    class_addMethod(self,
                    NSSelectorFromString(@"blockMethod"),
                    imp_implementationWithBlock(^(id me) {}),
                    "v16@0:8");
    Method description = class_getInstanceMethod([NSObject class], @selector(description));
    class_addMethod(self,
                    NSSelectorFromString(@"borrowedDescription"),
                    method_getImplementation(description),
                    method_getTypeEncoding(description));
}

@end

@implementation RuntimeSnapshotLoadFixture (RuntimeSnapshotCategory)

+ (void)load {
}

@end

@implementation RuntimeSnapshotInitializeCategoryFixture

+ (void)initialize {
}

@end

@implementation RuntimeSnapshotInitializeCategoryFixture (RuntimeSnapshotCategory)

+ (void)initialize {
}

@end

BOOL RuntimeSnapshotInitializeFixtureInitialized;

@implementation RuntimeSnapshotInitializeFixture

+ (void)initialize {
    RuntimeSnapshotInitializeFixtureInitialized = YES;
}

@end

@implementation RuntimeSnapshotFixtureSubclass

+ (void)baseClassMethod {
}

- (NSInteger)overriddenMethod {
    return 4;
}

@end

@implementation RuntimeSnapshotAccessorFixture
@end

BOOL RuntimeSnapshotRootFixtureInitialized;

@implementation RuntimeSnapshotRootFixture

+ (void)initialize {
    RuntimeSnapshotRootFixtureInitialized = YES;
}

@end

@implementation RuntimeSnapshotRootSubclassFixture
@end

@implementation RuntimeSnapshotStrongIvarFixture
@end

@implementation RuntimeSnapshotWeakIvarFixture
@end
