// Fixture: compiled with manual reference counting.
#import "cbase.h"
@interface Manual : CRoot
@end
@implementation Manual
- (void)keep:(CRoot *)r {
    [[r retain] autorelease];
    [r release];
    CRoot *n = [CRoot new];
    [n poke];
}
@end
