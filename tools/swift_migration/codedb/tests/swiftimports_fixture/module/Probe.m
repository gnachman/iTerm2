#import "Probe.h"
#import "Hidden.h"

NSString *const ProbeTitleKey = @"title";
_Atomic int ProbeAtomicCounter;

@interface Probe ()
- (void)privateHelper;
@end

@implementation Probe {
    NSInteger _count;
}
- (NSInteger)count {
    return _count;
}
- (instancetype)initWithTitle:(NSString *)title {
    self = [super init];
    if (self) {
        _title = [title copy];
    }
    return self;
}
+ (instancetype)probeWithTitle:(NSString *)title {
    return [[self alloc] initWithTitle:title];
}
- (void)logFormat:(NSString *)format, ... {
}
- (void)hiddenFromSwift {
}
- (NSInteger)refinedValue {
    return PROBE_LIMIT + PROBE_TWICE(1);
}
- (void)setTags:(NSArray<NSString *> *)tags {
}
- (void)privateHelper {
    (void)PROBE_CLASS;
    (void)PROBE_NAME;
}
@end

@implementation Probe (Extras)
- (void)extraThing {
}
@end

@implementation ProbeAtomicHolder
@end

@implementation ProbeGone
- (void)goneMethod {
}
@end

@implementation ProbeHidden
- (void)secret {
}
@end
