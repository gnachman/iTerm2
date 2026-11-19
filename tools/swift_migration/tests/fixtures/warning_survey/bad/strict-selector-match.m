// expect: -Wstrict-selector-match
#import "iTermStrictWarnings.h"
__attribute__((objc_root_class)) @interface A
- (void)take:(A *)x;
@end
__attribute__((objc_root_class)) @interface B
- (void)take:(B *)x;
@end
void f(id x, A *a) { [x take:a]; }
