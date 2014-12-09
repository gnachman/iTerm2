#import <Cocoa/Cocoa.h>

@interface NSWindow (PSM)
- (NSPoint)pointFromScreenCoords:(NSPoint)point;
- (NSPoint)pointToScreenCoords:(NSPoint)point;
@end
