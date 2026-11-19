// Fixture: a unit with two parse errors.
#import "widget.h"
@implementation Widget (Broken)
- (void)broken {
    [self doThing];
    int x = ;
    int y = ;
}
@end
