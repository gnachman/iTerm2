// Fixture: includes window_impl.m twice, with THE_CLASS and SPECIAL defined differently, as PTYWindow.m includes iTermWindowImpl.m. Line numbers are part of the expectations.
#import "cs_base.h"
#define THE_CLASS WindowA
#define SPECIAL 1
#include "window_impl.m"
#undef THE_CLASS
#undef SPECIAL
#define THE_CLASS WindowB
#define SPECIAL 0
#include "window_impl.m"
#undef THE_CLASS
#undef SPECIAL
// A category whose name is a macro, as Profile is for NSDictionary (Profile).
#define Flavor Thing
@interface Thing (Flavor)
@property (nonatomic, readonly) int flavor;
@end
#if 0
@interface Hidden : Root
@end
#endif
// A category named by a macro with two definitions, which cannot be resolved.
#define Mood Thing
#undef Mood
#define Mood Root
@interface Thing (Mood)
@property (nonatomic, readonly) int mood;
@end
// An ordinary class in a file that also names classes with macros.
@interface Gadget : Root
@end
@implementation Gadget
- (void)spin {
}
@end
