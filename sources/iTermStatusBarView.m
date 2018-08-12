//
//  iTermStatusBarView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import "iTermStatusBarView.h"
#import "PTYWindow.h"

@implementation iTermStatusBarView

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    CGFloat alpha = 0.25;
    if (self.window.ptyWindow.it_terminalWindowUseMinimalStyle) {
        alpha = 0.1;
    }

    __block CGFloat x = 1;
    [_sections enumerateObjectsUsingBlock:^(iTermTuple<NSColor *, NSNumber *> * _Nonnull tuple, NSUInteger idx, BOOL * _Nonnull stop) {
        CGFloat offset = tuple.secondObject.doubleValue;

        if (tuple.firstObject) {
            [tuple.firstObject set];
            NSRectFill(NSMakeRect(x, 1, offset - x, dirtyRect.size.height - 1));
        }

        [[NSColor colorWithWhite:0 alpha:alpha] set];
        NSRect rect = NSMakeRect(offset, 1, 1, dirtyRect.size.height - 1);
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);

        x = offset + 1;
    }];
    
    [[NSColor colorWithWhite:0 alpha:alpha] set];
    NSRect rect = NSMakeRect(0, 1, 1, dirtyRect.size.height - 1);
    NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
}

@end
