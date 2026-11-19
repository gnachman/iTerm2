// Fixture: a file that no unit compiles. Line numbers are part of the expectations.
#import "cs_base.h"
@interface Orphan : Root
@end
@interface Orphan () <Drawing>
@end
@implementation Orphan
- (void)lonely {
}
@end
