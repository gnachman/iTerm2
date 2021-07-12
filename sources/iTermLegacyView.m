//
//  iTermLegacyView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/5/21.
//

#import "iTermLegacyView.h"

@implementation iTermLegacyView

- (void)drawRect:(NSRect)dirtyRect {
    // This is good! The reason is the compositing operation. We don't want to punch a hole.
//    [[NSColor colorWithSRGBRed:0.25 green:0.25 blue:0.25 alpha:1] set];
//    NSRectFill(dirtyRect);
//
//    [[NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:0.5] set];
//    NSRectFillUsingOperation(dirtyRect, NSCompositingOperationSourceOver);
//    return;
    [self.delegate legacyView:self drawRect:dirtyRect];
}

- (BOOL)isFlipped {
    return YES;
}

@end
