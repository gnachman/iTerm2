//
//  iTermStatusBarContainerView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import "iTermStatusBarContainerView.h"

#import "NSDictionary+iTerm.h"
#import "NSTimer+iTerm.h"

const CGFloat iTermStatusBarViewControllerIconWidth = 16;

NS_ASSUME_NONNULL_BEGIN

@implementation iTermStatusBarContainerView {
    NSSet<NSString *> *_dependencies;
    NSTimer *_timer;
    BOOL _needsUpdate;
    NSView *_view;
    NSImageView *_iconImageView;
}

- (nullable instancetype)initWithComponent:(id<iTermStatusBarComponent>)component {
    self = [super initWithFrame:NSMakeRect(0, 0, 200, 21)];
    if (self) {
        self.wantsLayer = YES;
        _component = component;
        _dependencies = [component statusBarComponentVariableDependencies];
        _backgroundColor = [component.configuration[iTermStatusBarComponentConfigurationKeyKnobValues][iTermStatusBarSharedBackgroundColorKey] colorValue];
        _view = component.statusBarComponentCreateView;
        [self addSubview:_view];
        NSImage *icon = component.statusBarComponentIcon;
        const BOOL hasIcon = (icon != nil);
        const CGFloat x = hasIcon ? iTermStatusBarViewControllerIconWidth : 0;
        if (hasIcon) {
            _iconImageView = [NSImageView imageViewWithImage:icon];
            [_iconImageView sizeToFit];
            [self addSubview:_iconImageView];
            _iconImageView.layer.borderWidth =1;
            _iconImageView.layer.borderColor = [[NSColor blackColor] CGColor];
            NSRect area = NSMakeRect(0, 0, iTermStatusBarViewControllerIconWidth, 21);
            NSRect frame;
            frame.size = NSMakeSize(icon.size.width, icon.size.height);
            frame.origin.x = (area.size.width - frame.size.width) / 2.0;
            frame.origin.y = (area.size.height - frame.size.height) / 2.0;
            _iconImageView.frame = frame;
        }
        _view.frame = NSMakeRect(x, 0, self.frame.size.width - x, self.frame.size.height);
        _timer = [NSTimer scheduledWeakTimerWithTimeInterval:_component.statusBarComponentUpdateCadence
                                                      target:self
                                                    selector:@selector(reevaluateTimer:)
                                                    userInfo:nil
                                                     repeats:YES];
        [component statusBarComponentUpdate];
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p frame=%@ component=%@>", self.class, self, NSStringFromRect(self.frame), self.component];
}

- (void)reevaluateTimer:(NSTimer *)timer {
    [self setNeedsUpdate];
}

- (void)variablesDidChange:(NSSet<NSString *> *)paths {
    if ([paths intersectsSet:_dependencies]) {
        [self setNeedsUpdate];
    }
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
    CGFloat width = self.frame.size.width;
    CGFloat x = 0;
    if (self.component.statusBarComponentIcon) {
        width -= iTermStatusBarViewControllerIconWidth;
        x += iTermStatusBarViewControllerIconWidth;
    }

    [self.component statusBarComponentSizeView:_view toFitWidth:width];
    const CGFloat viewHeight = _view.frame.size.height;
    const CGFloat myHeight = self.frame.size.height;
    const CGFloat myWidth = width;
    const CGFloat viewWidth = _view.frame.size.width;
    _view.frame = NSMakeRect(x + (myWidth - viewWidth) / 2,
                             (myHeight - viewHeight) / 2 + _component.statusBarComponentVerticalOffset,
                             viewWidth,
                             viewHeight);
}

@end

NS_ASSUME_NONNULL_END
