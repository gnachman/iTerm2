#import "Widget.h"

@implementation Widget

- (void)updateField {
    NSString *label = [self labelForCount:_count];
    [_field setStringValue:label];
    _count -= 1;
}

- (void)update {
    [self prepare];
    if (_count > 0) {
        [self updateField];
    }
    [self finish];
}

- (void)reset {
    _count = 0;
    [_field setStringValue:@""];
}

@end
