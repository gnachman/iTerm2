//
//  iTermBackgroundColorView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/24/20.
//

#import "iTermBackgroundColorView.h"

#import "DebugLogging.h"
#import "iTermAlphaBlendingHelper.h"

@implementation iTermBackgroundColorView {
    NSColor *_backgroundColor;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(fullScreenDidChange:)
                                                     name:NSWindowDidEnterFullScreenNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(fullScreenDidChange:)
                                                     name:NSWindowDidExitFullScreenNotification
                                                   object:nil];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p frame=%@ hidden=%@ alpha=%@ backgroundColor=%@>",
            NSStringFromClass([self class]), self, NSStringFromRect(self.frame),
            self.hidden ? @"YES": @"no", @(self.alphaValue), _backgroundColor];
}

- (void)fullScreenDidChange:(NSNotification *)notification {
    [self updateBackgroundColor];
}

- (NSColor *)backgroundColor {
    return _backgroundColor;
}

- (void)setBackgroundColor:(NSColor *)backgroundColor {
    _backgroundColor = backgroundColor;
    [self updateBackgroundColor];
}

- (BOOL)inFullScreenWindow {
    return (self.window.styleMask & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen;
}

- (CGFloat)desiredAlphaValue {
    if (self.inFullScreenWindow &&
        self.blend == 0) {
        // Am full screen without a background image.
        return 1;
    }
    return iTermAlphaValueForTopView(self.inFullScreenWindow ? 0 : _transparency, _blend);
}

- (void)updateBackgroundColor {
    NSColor *color = [_backgroundColor colorWithAlphaComponent:self.desiredAlphaValue];
    DLog(@"Set background color to %@", color);
    self.layer.backgroundColor = color.CGColor;
}

- (void)setBlend:(CGFloat)blend {
    _blend = blend;
    [self updateBackgroundColor];
}

- (void)setTransparency:(CGFloat)transparency {
    _transparency = transparency;
    [self updateBackgroundColor];
}

@end

@implementation iTermSessionBackgroundColorView

- (CGFloat)desiredAlphaValue {
    CGFloat a = [super desiredAlphaValue];
    DLog(@"%@ alpha=%@, transparency=%@, blend=%@, fullscreen=%@", 
         self, @(a), @(self.transparency), @(self.blend), @(self.inFullScreenWindow));
    return a;
}

@end

@implementation iTermScrollerBackgroundColorView
@end
