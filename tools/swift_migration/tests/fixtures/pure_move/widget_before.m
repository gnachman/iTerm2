#import "Widget.h"

@implementation Widget

- (void)update {
    [self prepare];
    if (_count > 0) {
        NSString *label = [self labelForCount:_count];
        [_field setStringValue:label];
        _count -= 1;
    }
    [self finish];
}

- (void)reset {
    _count = 0;
    [_field setStringValue:@""];
}

@end
