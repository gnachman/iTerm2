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

- (instancetype)initWithCoder:(NSCoder *)coder {
    return [super initWithCoder:coder];
}

- (void)awakeFromNib {
    _view = [[CPKColorWell alloc] initWithFrame:self.bounds];
    [self addSubview:_view];
    _view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.autoresizesSubviews = YES;
    _view.alphaAllowed = _alphaAllowed;
    _view.disabled = !self.enabled;
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

- (void)setAlphaAllowed:(BOOL)alphaAllowed {
    _alphaAllowed = alphaAllowed;
    _view.alphaAllowed = alphaAllowed;
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    _view.disabled = !enabled;
}

@end
