//
//  iTermFlexibleView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/2/18.
//

#import "iTermFlexibleView.h"

#import "DebugLogging.h"

@implementation iTermFlexibleView  {
    BOOL _isFlipped;
}

- (instancetype)initWithFrame:(NSRect)frame color:(NSColor*)color {
    self = [super initWithFrame:frame];
    if (self) {
        _color = color;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p frame=%@ isHidden=%@ alphaValue=%@>",
            [self class], self, NSStringFromRect(self.frame), @(self.isHidden), @(self.alphaValue)];
}

- (void)setColor:(NSColor*)color {
    _color = color;
    [self setNeedsDisplay:YES];
}

- (BOOL)isFlipped {
    return _isFlipped;
}

- (void)setFlipped:(BOOL)value {
    _isFlipped = value;
}

- (void)drawRect:(NSRect)insaneRect {
    if (!_color) {
        [super drawRect:insaneRect];
        return;
    }
    const NSRect dirtyRect = NSIntersectionRect(insaneRect, self.bounds);
    [_color setFill];
    NSRectFill(dirtyRect);

    // Draw around the root.
    NSView *rootView = self.rootView;
    if (rootView.superview == self) {
        [[NSColor clearColor] set];
        NSRectFillUsingOperation(rootView.frame, NSCompositingOperationCopy);
    }

    [super drawRect:insaneRect];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self layoutRootIfNeeded];
    if (self.sizeDidChange && !NSEqualSizes(oldSize, self.bounds.size)) {
        self.sizeDidChange(oldSize);
    }
}

- (void)layoutRootIfNeeded {
    NSView *rootView = self.rootView;
    if (!_rootFillsBounds || rootView.superview != self) {
        return;
    }
    if (!NSEqualRects(rootView.frame, self.bounds)) {
        rootView.frame = self.bounds;
    }
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize {
    DLog(@"%@ resized %@ -> %@:\n%@",
         self,
         NSStringFromSize(oldSize),
         NSStringFromSize(self.frame.size),
         [NSThread callStackSymbols]);
    [super resizeWithOldSuperviewSize:oldSize];
}

@end
