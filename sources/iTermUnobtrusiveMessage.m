//
//  iTermUnobtrusiveMessage.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/11/20.
//

#import "iTermUnobtrusiveMessage.h"
#import "NSTextField+iTerm.h"
#import "NSView+iTerm.h"

NS_CLASS_AVAILABLE_MAC(10_14)
@implementation iTermUnobtrusiveMessage {
    NSVisualEffectView *_vev;
    NSTextField *_textField;
    BOOL _animating;
}

- (instancetype)initWithMessage:(NSString *)message {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _vev = [[NSVisualEffectView alloc] initWithFrame:NSInsetRect(self.bounds, 9, 9)];
        _vev.wantsLayer = YES;
        _vev.blendingMode = NSVisualEffectBlendingModeWithinWindow;
        _vev.material = NSVisualEffectMaterialSheet;
        _vev.state = NSVisualEffectStateActive;
        _vev.layer.cornerRadius = 6;
        _vev.layer.borderColor = [[NSColor grayColor] CGColor];
        _vev.layer.borderWidth = 1;

        _textField = [NSTextField newLabelStyledTextField];
        _textField.stringValue = message;
        [_textField sizeToFit];

        const CGFloat margin = 8;
        self.frame = NSMakeRect(0, 0, _textField.frame.size.width + margin * 2, _textField.frame.size.height + margin * 2);
        [self addSubview:_vev];
        _vev.frame = self.bounds;
        [_vev addSubview:_textField];
        _textField.frame = NSMakeRect(margin, margin, _textField.frame.size.width, _textField.frame.size.height);
        self.alphaValue = 0;
    }
    return self;
}

- (void)animateFromTopRightWithCompletion:(void (^)(void))completion {
    if (_animating) {
        return;
    }
    _animating = YES;

    const CGFloat margin = 8;
    NSRect frame = self.frame;
    frame.origin.x = NSMaxX(self.superview.bounds);
    frame.origin.y = NSMaxY(self.superview.bounds) - frame.size.height - margin;

    const NSRect outsideFrame = frame;
    self.frame = frame;
    self.alphaValue = 1;
    NSRect destination = frame;
    destination.origin.x -= frame.size.width + margin;
    [NSView animateWithDuration:0.2
                     animations:^{
        self.animator.frame = destination;
    } completion:^(BOOL finished) {
        [NSView animateWithDuration:0.2
                              delay:1
                         animations:^{
            self.animator.frame = outsideFrame;
            self.animator.alphaValue = 0;
        } completion:^(BOOL finished) {
            self->_animating = NO;
            completion();
        }];
    }];
}

@end
