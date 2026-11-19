#import "Bar.h"

@interface BarSpy : Bar
@end

@implementation BarSpy

- (void)setTitle:(NSString *)title {
}

@end

@interface Foo (Testing)
- (void)testOnly;
@end

@interface Bar ()
@property (nonatomic) int testOnlyProp;
@end

@interface Base (Spying)
- (void)spy;
@end
