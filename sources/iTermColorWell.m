//
//  iTermColorWell.m
//  iTerm2
//
//  Created by George Nachman on 9/18/15.
//
//

#import "iTermColorWell.h"
#import <ColorPicker/ColorPicker.h>

@implementation iTermColorWell {
    CPKColorWell *_view;
}

- (void)awakeFromNib {
    _view = [[CPKColorWell alloc] initWithFrame:self.bounds];
    [self addSubview:_view];
    _view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.autoresizesSubviews = YES;
    _view.colorDidChange = ^(NSColor *color) {
        [self sendAction:self.action to:self.target];
    };
}

- (NSColor *)color {
    return _view.color;
}

- (void)setColor:(NSColor *)color {
    _view.color = color;
}

@end
