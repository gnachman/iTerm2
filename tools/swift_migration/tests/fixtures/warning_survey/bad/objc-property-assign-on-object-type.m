// expect: -Wobjc-property-assign-on-object-type
#import "iTermStrictWarnings.h"
__attribute__((objc_root_class)) @interface Root
@property (nonatomic, assign) Root *other;
@end
