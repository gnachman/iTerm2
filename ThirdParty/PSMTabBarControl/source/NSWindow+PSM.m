#import "NSWindow+PSM.h"

@implementation NSWindow (PSM)

- (NSPoint)pointFromScreenCoords:(NSPoint)point {
    NSRect rectInWindowCoords = [self convertRectFromScreen:NSMakeRect(point.x, point.y, 0, 0)];
    return rectInWindowCoords.origin;
}

- (NSPoint)pointToScreenCoords:(NSPoint)point {
    NSRect rectInWindowCoords = NSMakeRect(point.x, point.y, 0, 0);
    return [self convertRectToScreen:rectInWindowCoords].origin;
}

@end

