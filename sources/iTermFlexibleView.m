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

- (void)drawRect:(NSRect)dirtyRect {
    [_color setFill];
    NSRectFill(dirtyRect);

    // Draw around the subviews.
    [[NSColor clearColor] set];
    for (NSView *view in self.subviews) {
        NSRectFillUsingOperation(view.frame, NSCompositingOperationCopy);
    }

    [super drawRect:dirtyRect];
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
