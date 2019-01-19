//
//  iTermStatusBarContainerView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import "iTermStatusBarContainerView.h"

#import "DebugLogging.h"
#import "NSDictionary+iTerm.h"
#import "NSImageView+iTerm.h"
#import "NSTimer+iTerm.h"

const CGFloat iTermStatusBarViewControllerIconWidth = 17;

NS_ASSUME_NONNULL_BEGIN

@implementation iTermStatusBarContainerView {
    NSTimer *_timer;
    BOOL _needsUpdate;
    NSView *_view;
}

- (nullable instancetype)initWithComponent:(id<iTermStatusBarComponent>)component {
    CGFloat preferredWidth = MAX(1, [component statusBarComponentMinimumWidth]);
    NSImage *icon = component.statusBarComponentIcon;
    if (icon) {
        preferredWidth += iTermStatusBarViewControllerIconWidth;
    }
    self = [super initWithFrame:NSMakeRect(0, 0, preferredWidth, 21)];
    if (self) {
        self.wantsLayer = YES;
        _component = component;
        _backgroundColor = [component.configuration[iTermStatusBarComponentConfigurationKeyKnobValues][iTermStatusBarSharedBackgroundColorKey] colorValue];
        _view = component.statusBarComponentView;
        [self addSubview:_view];
        const BOOL hasIcon = (icon != nil);
        const CGFloat x = self.minX;
        if (hasIcon) {
            icon.template = YES;
            _iconImageView = [NSImageView imageViewWithImage:icon];
            [_iconImageView it_setTintColor:[NSColor labelColor]];
            [_iconImageView sizeToFit];
            [self addSubview:_iconImageView];
            _iconImageView.layer.borderWidth =1;
            _iconImageView.layer.borderColor = [[NSColor blackColor] CGColor];
            NSRect area = NSMakeRect(0, 0, iTermStatusBarViewControllerIconWidth, 21);
            NSRect frame;
            frame.size = NSMakeSize(icon.size.width, icon.size.height);
            frame.origin.x = 0;
            frame.origin.y = (area.size.height - frame.size.height) / 2.0;
            _iconImageView.frame = frame;
        }
        _view.frame = NSMakeRect(x, 0, self.preferredWidthForComponentView, self.frame.size.height);
        _timer = [NSTimer scheduledWeakTimerWithTimeInterval:_component.statusBarComponentUpdateCadence
                                                      target:self
                                                    selector:@selector(reevaluateTimer:)
                                                    userInfo:nil
                                                     repeats:YES];
        [component statusBarComponentUpdate];

        if ([component statusBarComponentHandlesClicks]) {
            NSClickGestureRecognizer *recognizer = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(clickRecognized:)];
            [_view addGestureRecognizer:recognizer];
        }
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

- (void)clickRecognized:(id)sender {
    [_component statusBarComponentDidClickWithView:_view];
}

- (void)mouseDown:(NSEvent *)event {
    if ([_component statusBarComponentHandlesClicks]) {
        [_component statusBarComponentMouseDownWithView:_view];
    }
}

- (CGFloat)minX {
    NSImage *icon = _component.statusBarComponentIcon;
    const BOOL hasIcon = (icon != nil);
    return hasIcon ? iTermStatusBarViewControllerIconWidth : 0;

}

- (CGFloat)preferredWidthForComponentView {
    return self.frame.size.width - self.minX;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p frame=%@ component=%@>", self.class, self, NSStringFromRect(self.frame), self.component];
}

- (void)reevaluateTimer:(NSTimer *)timer {
    [self setNeedsUpdate];
}

- (void)setNeedsUpdate {
    if (_needsUpdate) {
        return;
    }
    _needsUpdate = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateIfNeeded];
    });
}

- (void)updateIfNeeded {
    if (!_needsUpdate) {
        return;
    }
    _needsUpdate = NO;
    [self.component statusBarComponentUpdate];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self layoutSubviews];
}

- (void)layoutSubviews {
    CGFloat width = self.frame.size.width;
    CGFloat x = 0;
    if (self.component.statusBarComponentIcon) {
        width -= iTermStatusBarViewControllerIconWidth;
        x += iTermStatusBarViewControllerIconWidth;
    }

    [self.component statusBarComponentSizeView:_view toFitWidth:width];
    const CGFloat viewHeight = _view.frame.size.height;
    const CGFloat myHeight = self.frame.size.height;
    const CGFloat viewWidth = _view.frame.size.width;
    DLog(@"set frame of view %@ for component %@ width to %@", _view, self.component, @(viewWidth));
    _view.frame = NSMakeRect(self.minX,
                             (myHeight - viewHeight) / 2 + _component.statusBarComponentVerticalOffset,
                             self.preferredWidthForComponentView,
                             viewHeight);
}

- (void)viewDidMoveToWindow {
    [_component statusBarComponentDidMoveToWindow];
}

@end

NS_ASSUME_NONNULL_END
