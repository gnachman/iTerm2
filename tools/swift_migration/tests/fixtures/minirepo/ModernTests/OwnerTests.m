#import "Owner.h"

@interface OwnerTests : XCTestCase
@end

@implementation OwnerTests
- (void)callByName:(NSString *)name {
    [self performSelector:NSSelectorFromString(name)];
    Class a = NSClassFromString(@"Mixed");
    Class b = NSClassFromString(name);
}
extern int FixtureOnlyExternInM(void);
@end
