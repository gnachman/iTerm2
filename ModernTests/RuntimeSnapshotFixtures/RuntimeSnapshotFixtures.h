//
//  RuntimeSnapshotFixtures.h
//  ModernTests
//
//  Small classes with a known runtime shape, used by RuntimeSnapshotTests.swift
//  to test the runtime snapshot tool (docs/swift-migration/phase0.md section 9).
//  RuntimeSnapshotFixtureExtensions.swift extends three of them from Swift:
//  RuntimeSnapshotFixture and RuntimeSnapshotDuplicateFixture with methods,
//  and RuntimeSnapshotAccessorFixture with a property.
//  Changing anything here changes the expected snapshots in the tests.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Deliberately does not inherit from the NSObject protocol, whose properties
// would otherwise appear in the adopting class's property list.
@protocol RuntimeSnapshotFixtureProtocol
- (void)protocolMethod;
@optional
@property (nonatomic, readonly) NSInteger optionalProtocolProperty;
@end

@interface RuntimeSnapshotFixtureBase : NSObject
+ (void)baseClassMethod;
// Overrides a class method of NSObject.
+ (void)initialize;
// Overrides an instance method of the root class NSObject, which class
// objects inherit because the root metaclass's superclass is NSObject.
+ (nullable id)valueForKey:(NSString *)key;
- (void)baseMethod;
- (NSInteger)overriddenMethod;
@end

@interface RuntimeSnapshotFixture : RuntimeSnapshotFixtureBase <RuntimeSnapshotFixtureProtocol>

@property (strong) NSObject *atomicStrong;
@property (nonatomic, strong) NSObject *nonatomicStrong;
@property (nonatomic, weak, nullable) NSObject *nonatomicWeak;
@property (nonatomic, copy) NSString *nonatomicCopy;
@property (nonatomic, unsafe_unretained) NSObject *nonatomicUnretained;
@property (nonatomic) NSInteger nonatomicAssign;
@property (atomic) double atomicAssign;
@property (nonatomic, readonly) NSInteger readonlyValue;
// Strong under ARC by default. Clang writes no ownership code for a readonly
// property that is strong, whether by default or by saying so, although it
// does write C, & and W for readonly copy, retain and weak ones, so the
// runtime cannot tell this property's ownership.
@property (nonatomic, readonly) NSObject *readonlyObject;
// Clang writes & for a strong readwrite Class property, and no code for a
// readonly one.
@property (nonatomic) Class readwriteClass;
@property (nonatomic, readonly) Class readonlyClass;
@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic, strong) NSObject *dynamicValue;
@property (nonatomic, direct) NSInteger directValue;
@property (class, nonatomic, copy) NSString *classProperty;

+ (NSString *)classMethodWithInteger:(int)value;
- (NSString *)instanceMethodWithInteger:(int)value object:(nullable id)object;
- (void)directMethod __attribute__((objc_direct));

@end

// The Objective-C half of two duplicate selectors. Its .m implements
// -duplicatedMethod and +duplicatedClassMethod without declaring them here,
// and RuntimeSnapshotFixtureExtensions.swift implements the same selectors in
// an extension. Neither compiler can see the
// other's definition, so the build succeeds and the runtime holds two methods
// with one selector: the hazard of docs/swift-migration/lifecycle.md section 2.
@interface RuntimeSnapshotDuplicateFixture : NSObject
@end

// Overrides methods that both its superclass and its superclass's superclass
// implement, so the nearest one is the one reported.
@interface RuntimeSnapshotFixtureSubclass : RuntimeSnapshotFixture
@end

// A class property that the compiler copies into the property list of every
// class and category adopting a protocol derived from this one.
@protocol RuntimeSnapshotFixtureClassPropertyProtocol
@optional
@property (class, nonatomic, readonly) NSInteger repeatedClassProperty;
@end

// Lists the NSObject protocol's properties twice, as PTYSession does: once
// for the protocol adopted by the class and once for the one adopted by the
// category, both of which inherit from the NSObject protocol. Its class
// property repeats the same way. The category also adopts the class's
// protocol again, so the class's protocol list holds that protocol twice.
@protocol RuntimeSnapshotFixtureObjectProtocol <NSObject, RuntimeSnapshotFixtureClassPropertyProtocol>
@end

@protocol RuntimeSnapshotFixtureOtherObjectProtocol <NSObject, RuntimeSnapshotFixtureClassPropertyProtocol>
@end

@interface RuntimeSnapshotPropertyRepeatFixture : NSObject <RuntimeSnapshotFixtureObjectProtocol>
@end

@interface RuntimeSnapshotPropertyRepeatFixture (RuntimeSnapshotCategory) <RuntimeSnapshotFixtureOtherObjectProtocol, RuntimeSnapshotFixtureObjectProtocol>
@end

// Accessor names and ownership codes. Clang writes an S code for a custom
// setter name, and no ownership code for an unsafe_unretained or assign
// Class property. RuntimeSnapshotFixtureExtensions.swift adds a property
// with a custom getter name, for which Swift writes no G code.
@interface RuntimeSnapshotAccessorFixture : NSObject
@property (nonatomic, setter=assignCustomSetter:) NSInteger customSetter;
@property (nonatomic, getter=isBoth, setter=assignBoth:) BOOL both;
@property (nonatomic, unsafe_unretained, nullable) Class unretainedClass;
@property (nonatomic, assign, nullable) Class assignedClass;
@end

// Has +load in both the class and a category. Both run, one after the other,
// so the two +load entries in its method list are not a conflict. Its +load
// also adds -borrowedDescription with the implementation of -[NSObject
// description], whose code lives in libobjc rather than in ModernTests.
@interface RuntimeSnapshotLoadFixture : NSObject
@end

@interface RuntimeSnapshotLoadFixture (RuntimeSnapshotCategory)
@end

// Has +initialize in both the class and a category. Unlike +load, only one
// of them runs, the category's, so the two +initialize entries in its method
// list are a duplicate.
@interface RuntimeSnapshotInitializeCategoryFixture : NSObject
@end

@interface RuntimeSnapshotInitializeCategoryFixture (RuntimeSnapshotCategory)
@end

// Sets RuntimeSnapshotInitializeFixtureInitialized in +initialize, so a test
// can tell whether taking a snapshot initialized the class.
extern BOOL RuntimeSnapshotInitializeFixtureInitialized;

@interface RuntimeSnapshotInitializeFixture : NSObject
@property (nonatomic, strong) NSObject *object;
@end

// Identical except for whether their ivar is strong or weak. Both ivars are
// encoded as @; only the ivar layouts, which the snapshot reads, tell them
// apart.
@interface RuntimeSnapshotStrongIvarFixture : NSObject {
@public
    __strong id _object;
}
@end

@interface RuntimeSnapshotWeakIvarFixture : NSObject {
@public
    __weak id _object;
}
@end

// A root class with no methods except +initialize, which sets
// RuntimeSnapshotRootFixtureInitialized. Sending it any other message
// crashes the process, so a test that snapshots it without crashing shows
// that the snapshot sends it nothing.
extern BOOL RuntimeSnapshotRootFixtureInitialized;

NS_ROOT_CLASS
@interface RuntimeSnapshotRootFixture
@end

@interface RuntimeSnapshotRootSubclassFixture : RuntimeSnapshotRootFixture
@end

NS_ASSUME_NONNULL_END
