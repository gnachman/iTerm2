//
//  iTermFlippedView.m
//  iTerm
//
//  Created by George Nachman on 5/3/14.
//
//

#import "iTermFlippedView.h"

@implementation iTermFlippedView

- (BOOL)isFlipped {
    return YES;
}

- (void)flipSubviews {
    for (NSView *view in [self subviews]) {
        NSRect frame = [view frame];
        frame.origin.y = NSMaxY([self bounds]) - NSMaxY([view frame]);
        [view setFrame:frame];
    }
}

@end
