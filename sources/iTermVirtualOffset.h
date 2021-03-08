//
//  iTermVirtualOffset.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/5/21.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// See the long comment in -[PTYTextView init] for how this came to be.

NSRect NSRectSubtractingVirtualOffset(NSRect rect, CGFloat offset);
void iTermFrameRect(NSRect rect, CGFloat offset);
void iTermRectFill(NSRect rect, CGFloat offset);
void iTermRectFillUsingOperation(NSRect rect, NSCompositingOperation op, CGFloat virtualOffset);
void iTermFrameRectWithWidthUsingOperation(NSRect rect, CGFloat frameWidth, NSCompositingOperation op, CGFloat virtualOffset);
void iTermRectClip(NSRect rect, CGFloat offset);

@interface NSImage(VirtualOffset)
- (void)it_drawInRect:(NSRect)dstSpacePortionRect
             fromRect:(NSRect)srcSpacePortionRect
            operation:(NSCompositingOperation)op
             fraction:(CGFloat)requestedAlpha
       respectFlipped:(BOOL)respectContextIsFlipped
                hints:(nullable NSDictionary<NSImageHintKey, id> *)hints
        virtualOffset:(CGFloat)virtualOffset;
@end

@interface NSString(VirtualOffset)
- (void)it_drawAtPoint:(NSPoint)point
        withAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attrs
         virtualOffset:(CGFloat)virtualOffset;

- (void)it_drawInRect:(NSRect)rect
       withAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attrs
        virtualOffset:(CGFloat)virtualOffset;
@end

@interface NSBezierPath(VirtualOffset)
- (void)it_moveToPoint:(NSPoint)point virtualOffset:(CGFloat)virtualOffset;
- (void)it_lineToPoint:(NSPoint)point virtualOffset:(CGFloat)virtualOffset;
@end

NS_ASSUME_NONNULL_END
