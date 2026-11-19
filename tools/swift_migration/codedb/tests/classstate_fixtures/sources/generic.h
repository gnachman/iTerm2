// Fixture: generic classes, whose type arguments are not protocols. Line numbers are part of the expectations.
#import "cs_base.h"
@interface Box<T> : Root
@end
@interface BoxOfThings : Box<Thing *>
@end
@interface Pair<A> : Box<A>
@end
@interface Drawn : Box<Thing *> <Drawing>
@end
