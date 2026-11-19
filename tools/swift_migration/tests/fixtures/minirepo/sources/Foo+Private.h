#import "Foo.h"

@interface Foo () {
    FooMode _mode;
}
@property (nonatomic, readonly) FooMode mode;
@end
