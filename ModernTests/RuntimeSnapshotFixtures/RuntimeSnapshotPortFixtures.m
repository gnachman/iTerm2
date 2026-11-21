//
//  RuntimeSnapshotPortFixtures.m
//  ModernTests
//
//  See RuntimeSnapshotPortFixtures.h.
//

#import "RuntimeSnapshotPortFixtures.h"

@implementation RuntimeSnapshotPortObjCFixture {
    // An ivar with no property, which key-value coding can reach by name.
    NSInteger _privateCounter;
}

+ (NSInteger)classValue {
    return 7;
}

+ (instancetype)fixtureWithCount:(NSInteger)count {
    return [[self alloc] initWithCount:count];
}

- (instancetype)initWithCount:(NSInteger)count {
    self = [super init];
    if (self) {
        _count = count;
        _copiedString = @"";
        _readonlyString = @"";
    }
    return self;
}

- (instancetype)init {
    return [self initWithCount:0];
}

- (NSString *)describeWithPrefix:(NSString *)prefix count:(NSInteger)count {
    return [NSString stringWithFormat:@"%@ %ld %ld", prefix, (long)count, (long)_privateCounter];
}

- (BOOL)isReady {
    return YES;
}

- (void)takeBlock:(void (^)(NSInteger))block {
    block(_count);
}

- (NSRect)rectByInsetting:(CGFloat)inset {
    return NSInsetRect(_frame, inset, inset);
}

- (int)intValue {
    return (int)_count;
}

- (char)charValue {
    return (char)_count;
}

- (void)protocolMethod {
}

- (id)copyWithZone:(NSZone *)zone {
    return [[RuntimeSnapshotPortObjCFixture alloc] initWithCount:_count];
}

@end

// A category written in Objective-C, which stays in Objective-C when the
// class moves to Swift. RuntimeSnapshotPortFixtures.swift's class gets the
// same category below.
@implementation RuntimeSnapshotPortObjCFixture (RuntimeSnapshotPortCategory)

- (NSString *)categoryMethod {
    return @"category";
}

@end

// The Swift port and its variants, declared here only so that a category
// can be written on each, as Objective-C code does on a ported class through
// the generated Swift header.
@interface RuntimeSnapshotPortSwiftFixture : NSObject
@end

@implementation RuntimeSnapshotPortSwiftFixture (RuntimeSnapshotPortCategory)

- (NSString *)categoryMethod {
    return @"category";
}

@end

@interface RuntimeSnapshotPortSwiftDroppedMethodFixture : NSObject
@end

@implementation RuntimeSnapshotPortSwiftDroppedMethodFixture (RuntimeSnapshotPortCategory)

- (NSString *)categoryMethod {
    return @"category";
}

@end

@interface RuntimeSnapshotPortSwiftChangedFixture : NSObject
@end

@implementation RuntimeSnapshotPortSwiftChangedFixture (RuntimeSnapshotPortCategory)

- (NSString *)categoryMethod {
    return @"category";
}

@end

@interface RuntimeSnapshotPortSwiftReadonlyFixture : NSObject
@end

@implementation RuntimeSnapshotPortSwiftReadonlyFixture (RuntimeSnapshotPortCategory)

- (NSString *)categoryMethod {
    return @"category";
}

@end

@implementation RuntimeSnapshotPortLoadObjCFixture

+ (void)load {
}

+ (void)initialize {
}

- (void)method {
}

@end

@implementation RuntimeSnapshotPortAtomicObjCFixture
@end

@implementation RuntimeSnapshotPortInitObjCFixture

- (instancetype)initWithCount:(NSInteger)count {
    self = [super init];
    if (self) {
        _count = count;
    }
    return self;
}

- (instancetype)init {
    return [self initWithCount:0];
}

@end
