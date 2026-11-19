#import "Foo.h"

@interface FooSub : Foo
@end

@interface Foo (Extras)
- (void)extra;
@end
