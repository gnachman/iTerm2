// expect: -Wimplicit-atomic-properties
#import "iTermStrictWarnings.h"
__attribute__((objc_root_class)) @interface Root
@property int value;
@end
@implementation Root
@synthesize value = _value;
@end
