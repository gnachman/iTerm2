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
    BOOL _continuous;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    return [super initWithCoder:coder];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self loadSubviews];
    }
    return self;
}

- (void)awakeFromNib {
    [self loadSubviews];
}

- (void)loadSubviews {
    _view = [[CPKColorWell alloc] initWithFrame:self.bounds];
    [self addSubview:_view];
    _view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.autoresizesSubviews = YES;
    _view.alphaAllowed = _alphaAllowed;
    _view.disabled = !self.enabled;
    self.continuous = YES;
    _view.colorDidChange = ^(NSColor *color) {
        if (self.continuous) {
            [self sendAction:self.action to:self.target];
        }
    };
    _view.popoverWillClose = ^(NSColor *color) {
        if (!self.continuous) {
            [self sendAction:self.action to:self.target];
        }
    };
}

- (void)setContinuous:(BOOL)continuous {
    _continuous = continuous;
}

- (BOOL)isContinuous {
    return _continuous;
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

- (void)mouseDown:(NSEvent *)theEvent {
    [_view openPopOver];
}

@end
