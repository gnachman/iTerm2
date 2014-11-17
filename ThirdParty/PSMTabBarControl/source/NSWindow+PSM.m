#import "NSWindow+PSM.h"

@implementation NSWindow (PSM)

- (NSPoint)pointFromScreenCoords:(NSPoint)point {
    NSRect rectInWindowCoords = [self convertRectFromScreen:NSMakeRect(point.x, point.y, 0, 0)];
    return rectInWindowCoords.origin;
}

@end

