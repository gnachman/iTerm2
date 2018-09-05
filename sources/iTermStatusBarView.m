//
//  iTermStatusBarView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import "iTermStatusBarView.h"
#import "PTYWindow.h"

@implementation iTermStatusBarView

- (CGFloat)drawSeparatorsInRect:(NSRect)dirtyRect {
    CGFloat x = 1;
    const CGFloat separatorTopBottomInset = 3;

    if (self.separatorColor) {
        [self.separatorColor set];
        for (NSNumber *offsetNumber in _separatorOffsets) {
            CGFloat offset = offsetNumber.doubleValue;
            NSRect rect = NSMakeRect(offset, separatorTopBottomInset, 1, dirtyRect.size.height - separatorTopBottomInset * 2);
            NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
            x = offset + 1;
        }
    }
    return x;
}

- (void)drawBackgroundColorsInRect:(NSRect)dirtyRect {
    CGFloat lastX = 0;
    CGFloat x = 0;
    for (iTermTuple<NSColor *, NSNumber *> *tuple in self.backgroundColors) {
        if (tuple.firstObject) {
            [tuple.firstObject set];
            x = tuple.secondObject.doubleValue;
            NSRectFill(NSMakeRect(lastX,
                                  1,
                                  x - lastX,
                                  dirtyRect.size.height - 1));
            lastX = x;
        }
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    [self drawBackgroundColorsInRect:dirtyRect];
    [self drawSeparatorsInRect:dirtyRect];

    if (self.separatorColor) {
        [self.separatorColor set];
        [[NSColor colorWithWhite:0 alpha:0.1] set];
        NSRect rect = NSMakeRect(0, 1, 1, dirtyRect.size.height - 1);
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
    }
}

@end
