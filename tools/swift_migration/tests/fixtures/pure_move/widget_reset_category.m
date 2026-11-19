#import "Widget.h"

@implementation Widget (Reset)

- (void)reset {
    _count = 0;
    [_field setStringValue:@""];
}

@end
