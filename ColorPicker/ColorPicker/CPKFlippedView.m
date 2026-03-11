#import "CPKFlippedView.h"

@implementation CPKFlippedView

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

@end
