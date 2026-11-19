// One declaration of each kind the code database records, and one of each
// reason Swift does not import a declaration
// (tests/test_codedb_swiftimports.py).
#import <Foundation/Foundation.h>

#define PROBE_LIMIT 42
#define PROBE_NAME @"probe"
#define PROBE_EMPTY
#define PROBE_TWICE(x) ((x) + (x))
#define PROBE_CLASS [NSObject class]

extern NSString *const ProbeTitleKey;
extern _Atomic int ProbeAtomicCounter;

NS_ASSUME_NONNULL_BEGIN

@protocol ProbeDelegate <NSObject>
- (void)probeDidChange:(id)probe;
@optional
- (void)probeWillChange:(id)probe;
@end

@interface Probe : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, readonly) NSInteger count;
@property (nonatomic, weak, nullable) id<ProbeDelegate> delegate;
- (NSInteger)count;
- (instancetype)initWithTitle:(NSString *)title;
+ (instancetype)probeWithTitle:(NSString *)title;
- (void)logFormat:(NSString *)format, ...;
- (void)hiddenFromSwift NS_SWIFT_UNAVAILABLE("use something else");
- (instancetype)init NS_UNAVAILABLE;
- (NSInteger)refinedValue NS_REFINED_FOR_SWIFT;
- (void)setTags:(NSArray<NSString *> *)tags;
@end

@interface Probe (Extras)
- (void)extraThing;
@end

@interface ProbeAtomicHolder : NSObject
@property (atomic) _Atomic(int) atomicValue;
@property (atomic) int plainValue;
@end

NS_SWIFT_UNAVAILABLE("gone")
@interface ProbeGone : NSObject
- (void)goneMethod;
@end

NS_ASSUME_NONNULL_END

// Functions and types the database has no table of: found by name only.
static inline NSInteger ProbeInlineDouble(NSInteger x) { return x * 2; }
NSInteger ProbePlainFunction(NSInteger x);
NSInteger ProbeRenamedFunction(void) NS_SWIFT_NAME(probeRenamed());
typedef NS_ENUM(NSInteger, ProbeMode) { ProbeModeOff, ProbeModeOn };
typedef NS_OPTIONS(NSUInteger, ProbeFlags) { ProbeFlagsNone = 0, ProbeFlagsBold = 1 << 0 };
typedef void (^ProbeHandler)(NSInteger value);
typedef struct { int x; int y; } ProbePoint;

@class ProbeHidden;

// A property whose Swift name collides with a method its superclass
// declares, and members whose type names a class Swift cannot see.
@interface ProbeFileBase : NSObject
- (NSString *)localPath;
@end

@interface ProbeFile : ProbeFileBase
@property (nonatomic, readonly) NSString *localPath;
@property (nonatomic, strong) ProbeHidden *hiddenThing;
- (ProbeHidden *)makeHidden;
@end

// Compiled only by units that define PROBE_EXTRA (OtherUser.m), not by the
// module SIF's configuration.
#if PROBE_EXTRA
@interface ProbeExtra : NSObject
- (void)extraOnly;
@end
#endif
