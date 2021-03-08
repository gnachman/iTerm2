//
//  iTermVirtualOffset.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/5/21.
//

#import "iTermVirtualOffset.h"

NSRect NSRectSubtractingVirtualOffset(NSRect rect, CGFloat offset) {
    NSRect temp = rect;
    temp.origin.y -= offset;
    return temp;
}

NSPoint NSPointSubtractingVirtualOffset(NSPoint point, CGFloat offset) {
    return NSMakePoint(point.x, point.y - offset);
}

void iTermFrameRect(NSRect rect, CGFloat offset) {
    NSFrameRect(NSRectSubtractingVirtualOffset(rect, offset));
}

void iTermRectFill(NSRect rect, CGFloat offset) {
    NSRectFill(NSRectSubtractingVirtualOffset(rect, offset));
}

void iTermRectClip(NSRect rect, CGFloat offset) {
    NSRectClip(NSRectSubtractingVirtualOffset(rect, offset));
}

void iTermRectFillUsingOperation(NSRect rect, NSCompositingOperation op, CGFloat virtualOffset) {
    NSRectFillUsingOperation(NSRectSubtractingVirtualOffset(rect, virtualOffset), op);
}

void iTermFrameRectWithWidthUsingOperation(NSRect rect, CGFloat frameWidth, NSCompositingOperation op, CGFloat virtualOffset) {
    NSFrameRectWithWidthUsingOperation(NSRectSubtractingVirtualOffset(rect, virtualOffset),
                                       frameWidth,
                                       op);
}

@implementation NSImage(VirtualOffset)

- (void)it_drawInRect:(NSRect)dstSpacePortionRect
             fromRect:(NSRect)srcSpacePortionRect
            operation:(NSCompositingOperation)op
             fraction:(CGFloat)requestedAlpha
       respectFlipped:(BOOL)respectContextIsFlipped
                hints:(nullable NSDictionary<NSImageHintKey, id> *)hints
        virtualOffset:(CGFloat)virtualOffset {
    [self drawInRect:NSRectSubtractingVirtualOffset(dstSpacePortionRect, virtualOffset)
            fromRect:srcSpacePortionRect
           operation:op
            fraction:requestedAlpha
      respectFlipped:respectContextIsFlipped
               hints:hints];
}

@end

@implementation NSString(VirtualOffset)

- (void)it_drawAtPoint:(NSPoint)point
        withAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attrs
         virtualOffset:(CGFloat)virtualOffset {
    [self drawAtPoint:NSPointSubtractingVirtualOffset(point, virtualOffset)
       withAttributes:attrs];
}

- (void)it_drawInRect:(NSRect)rect
       withAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attrs
        virtualOffset:(CGFloat)virtualOffset {
    [self drawInRect:NSRectSubtractingVirtualOffset(rect, virtualOffset) withAttributes:attrs];
}

@end

@implementation NSBezierPath(VirtualOffset)
- (void)it_moveToPoint:(NSPoint)point virtualOffset:(CGFloat)virtualOffset {
    [self moveToPoint:NSPointSubtractingVirtualOffset(point, virtualOffset)];
}

- (void)it_lineToPoint:(NSPoint)point virtualOffset:(CGFloat)virtualOffset {
    [self lineToPoint:NSPointSubtractingVirtualOffset(point, virtualOffset)];
}
@end
