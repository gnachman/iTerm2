//
//  RuntimeSnapshotPortFixtures.h
//  ModernTests
//
//  An Objective-C class and, in RuntimeSnapshotPortFixtures.swift, its
//  faithful stage-one Swift port (docs/swift-migration/translation-rules.md
//  section 7), used to find by experiment which differences a change of
//  language makes in a runtime snapshot, and to test the comparison's
//  classification of them (docs/swift-migration/phase0.md section 9). The
//  two classes have different runtime names only because both must exist in
//  one process; the checked-in snapshot pairs under
//  tools/swift_migration/tests/fixtures/runtime_snapshot_compare/ give the
//  Swift one the Objective-C one's name, as a real port does with
//  @objc(Name).
//
//  Changing anything here changes those snapshots: regenerate them with
//  tools/swift_migration/tests/make_runtime_snapshot_compare_fixtures.sh.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol RuntimeSnapshotPortFixtureProtocol <NSObject>
- (void)protocolMethod;
@end

@interface RuntimeSnapshotPortObjCFixture : NSObject <RuntimeSnapshotPortFixtureProtocol, NSCopying>

@property (nonatomic, strong, nullable) NSObject *strongObject;
@property (nonatomic, weak, nullable) NSObject *weakObject;
@property (nonatomic, copy) NSString *copiedString;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, readonly) NSString *readonlyString;
@property (nonatomic) BOOL enabled;
@property (nonatomic, getter=isVisible) BOOL visible;
@property (nonatomic, copy, nullable) void (^handler)(void);
@property (nonatomic) NSRect frame;
@property (class, nonatomic, readonly) NSInteger classValue;

+ (instancetype)fixtureWithCount:(NSInteger)count;
- (instancetype)initWithCount:(NSInteger)count NS_DESIGNATED_INITIALIZER;
- (instancetype)init;
- (NSString *)describeWithPrefix:(NSString *)prefix count:(NSInteger)count;
- (BOOL)isReady;
- (void)takeBlock:(void (^)(NSInteger))block;
- (NSRect)rectByInsetting:(CGFloat)inset;
- (int)intValue;
- (char)charValue;

@end

// Has +load and +initialize, which a Swift class cannot implement.
@interface RuntimeSnapshotPortLoadObjCFixture : NSObject
@end

// Has atomic properties: an object, a struct, and a scalar that is atomic
// by default. Every Swift property is nonatomic; the faithful port stores
// each in a MutableAtomicObject (docs/swift-migration/concurrency.md
// section 3).
@interface RuntimeSnapshotPortAtomicObjCFixture : NSObject
@property (atomic, strong, nullable) NSObject *atomicObject;
@property (atomic) NSRect atomicRect;
@property NSInteger atomicCount;
@end

// Implements -init and -initWithCount:. Its Swift port,
// RuntimeSnapshotPortInitSwiftFixture, declares only init(count:), so the
// -init that Swift lists for it is a stub that traps, although the two
// snapshots have the same -init line.
@interface RuntimeSnapshotPortInitObjCFixture : NSObject
@property (nonatomic) NSInteger count;
- (instancetype)initWithCount:(NSInteger)count NS_DESIGNATED_INITIALIZER;
- (instancetype)init;
@end

NS_ASSUME_NONNULL_END
