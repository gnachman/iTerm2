// expect: -Wselector
#import "iTermStrictWarnings.h"
@protocol Declared
- (void)declaredOnly;
@end
__attribute__((objc_root_class)) @interface Root
@end
@implementation Root
@end
SEL f(void) { return @selector(declaredOnly); }
