// expect: -Warc-repeated-use-of-weak
// arc
#import "iTermStrictWarnings.h"
__attribute__((objc_root_class)) @interface Root
@property (nonatomic, weak) Root *other;
- (int)foo;
@end
int f(Root *r) { return [r.other foo] + [r.other foo]; }
