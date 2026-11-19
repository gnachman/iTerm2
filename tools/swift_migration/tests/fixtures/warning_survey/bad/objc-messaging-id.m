// expect: -Wobjc-messaging-id
#import "iTermStrictWarnings.h"
__attribute__((objc_root_class)) @interface Root
- (int)foo;
@end
int f(id x) { return [x foo]; }
