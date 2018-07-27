//
//  iTermStatusBarContainerView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import "iTermStatusBarContainerView.h"

#import "NSDictionary+iTerm.h"
#import "NSTimer+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermStatusBarContainerView {
    NSSet<NSString *> *_dependencies;
    NSTimer *_timer;
    BOOL _needsUpdate;
    NSView *_view;
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
        _view.frame = NSMakeRect(0, 0, self.frame.size.width, self.frame.size.height);
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
    [self.component statusBarComponentSizeView:_view toFitWidth:self.frame.size.width];
    const CGFloat viewHeight = _view.frame.size.height;
    const CGFloat myHeight = self.frame.size.height;
    const CGFloat myWidth = self.frame.size.width;
    const CGFloat viewWidth = _view.frame.size.width;
    _view.frame = NSMakeRect((myWidth - viewWidth) / 2,
                             (myHeight - viewHeight) / 2 + _component.statusBarComponentVerticalOffset,
                             viewWidth,
                             viewHeight);
}

@end

NS_ASSUME_NONNULL_END
