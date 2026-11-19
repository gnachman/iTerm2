// A decoy standing in for this tool's own fixture files: every scan of the
// whole repository must leave tools/swift_migration out.
// SWIFT-MIGRATION-SHIM
#import "FooSub.h"

@interface DecoySub : FooSub
@end

@implementation DecoySub
- (void)f:(NSString *)name {
    self.ivar_decoy = 1;
    [self performSelector:NSSelectorFromString(name)];
}
@end
