//
//  iTermBottomMarginView.m
//  iTerm2
//
//  Created by George Nachman on 11/16/16.
//
//

#import "iTermBottomMarginView.h"

@implementation iTermBottomMarginView

- (void)drawRect:(NSRect)dirtyRect {
    if (self.drawRect) {
        self.drawRect(dirtyRect);
    }
}

@end
