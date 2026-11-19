// Fixture: an extension, implementations, and methods made by macros. Line numbers are part of the expectations.
#import "methods.h"
#define DEFINE_SETTING(name) \
    + (int)load_##name { return 0; } \
    + (id)key_##name { return [self valueForKey:@#name]; }
#define DECLARE_WEAK - (id)weakSelf;
@interface Gadget ()
@property (nonatomic, readwrite) int size;
- (void)hidden;
DECLARE_WEAK
@end
@implementation Gadget
@synthesize sides = _sides;
@dynamic dyn;
+ (int)shared { return 0; }
+ (void)setShared:(int)s {}
- (id)label { return 0; }
- (void)draw {}
- (void)hidden {}
- (void)reset:(int)a with:(int)b {}
- (id)weakSelf { return self; }
DEFINE_SETTING(alpha)
@end
@implementation Gadget (Extras)
- (void)extra {}
- (int)extraCount { return 1; }
@end
