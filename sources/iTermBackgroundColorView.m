//
//  iTermBackgroundColorView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/24/20.
//

#import "iTermBackgroundColorView.h"

#import "iTermAlphaBlendingHelper.h"

@implementation iTermBackgroundColorView {
    NSColor *_backgroundColor;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p frame=%@ hidden=%@ alpha=%@ backgroundColor=%@>",
            NSStringFromClass([self class]), self, NSStringFromRect(self.frame),
            self.hidden ? @"YES": @"no", @(self.alphaValue), _backgroundColor];
}

- (NSColor *)backgroundColor {
    return _backgroundColor;
}

- (void)setBackgroundColor:(NSColor *)backgroundColor {
    _backgroundColor = backgroundColor;
    [self updateBackgroundColor];
}

- (CGFloat)desiredAlphaValue {
    return iTermAlphaValueForTopView(_transparency, _blend);
}

- (void)updateBackgroundColor {
    self.layer.backgroundColor = [_backgroundColor colorWithAlphaComponent:self.desiredAlphaValue].CGColor;
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

