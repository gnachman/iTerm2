//
//  iTermStatusBarContainerView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import "iTermStatusBarContainerView.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermStatusBarBaseComponent.h"
#import "iTermUnreadCountView.h"
#import "NSDictionary+iTerm.h"
#import "NSEvent+iTerm.h"
#import "NSImageView+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTimer+iTerm.h"
#import "NSView+iTerm.h"

const CGFloat iTermStatusBarViewControllerIconWidth = 17;

NS_ASSUME_NONNULL_BEGIN

const CGFloat iTermGetStatusBarHeight() {
    static CGFloat height;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        height = [iTermAdvancedSettingsModel statusBarHeight];
    });
    return height;
}

@implementation iTermStatusBarContainerView {
    NSTimer *_timer;
    BOOL _needsUpdate;
    NSView *_view;
    iTermUnreadCountView *_unreadCountView;
}

- (nullable instancetype)initWithComponent:(id<iTermStatusBarComponent>)component {
    CGFloat preferredWidth = MAX(1, [component statusBarComponentMinimumWidth]);
    NSImage *icon = component.statusBarComponentIcon;
    if (icon) {
        preferredWidth += iTermStatusBarViewControllerIconWidth;
    }
    self = [super initWithFrame:NSMakeRect(0, 0, preferredWidth, iTermGetStatusBarHeight())];
    if (self) {
        self.wantsLayer = YES;
        self.layer.masksToBounds = NO;
        _component = component;
        _backgroundColor = [component.configuration[iTermStatusBarComponentConfigurationKeyKnobValues][iTermStatusBarSharedBackgroundColorKey] colorValue];
        _view = component.statusBarComponentView;
        [self addSubview:_view];
        _view.frame = NSMakeRect(self.minX, 0, self.preferredWidthForComponentView, self.frame.size.height);
        _timer = [NSTimer scheduledWeakTimerWithTimeInterval:_component.statusBarComponentUpdateCadence
                                                      target:self
                                                    selector:@selector(reevaluateTimer:)
                                                    userInfo:nil
                                                     repeats:YES];
        [component statusBarComponentUpdate];

        if ([component statusBarComponentHandlesClicks]) {
            NSClickGestureRecognizer *recognizer = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(clickRecognized:)];
            if ([component statusBarComponentHandlesMouseDown]) {
                recognizer.delaysPrimaryMouseButtonEvents = NO;
            }
            [self addGestureRecognizer:recognizer];
        }
        [self updateIconIfNeeded];
        _unreadCountView = [[iTermUnreadCountView alloc] init];
        [self addSubview:_unreadCountView];
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

- (void)updateIconIfNeeded {
    NSImage *icon = _component.statusBarComponentIcon;
    if (icon == _iconImageView.image) {
        return;
    }
    [_iconImageView removeFromSuperview];
    _iconImageView = nil;
    const BOOL hasIcon = (icon != nil);
    if (hasIcon) {
        icon.template = YES;
        _iconImageView = [NSImageView imageViewWithImage:icon];
        NSColor *tintColor = [self.component statusBarTextColor] ?: [self.component.delegate statusBarComponentDefaultTextColor];
        [_iconImageView it_setTintColor:tintColor];
        [_iconImageView sizeToFit];
        [self addSubview:_iconImageView];
        NSRect area = NSMakeRect(0, 0, iTermStatusBarViewControllerIconWidth, iTermGetStatusBarHeight());
        NSRect frame;
        frame.size = NSMakeSize(icon.size.width, icon.size.height);
        frame.origin.x = 0;
        frame.origin.y = (area.size.height - frame.size.height) / 2.0;
        _iconImageView.frame = frame;
    }
}

- (void)setUnreadCount:(NSInteger)count {
    if (count == _unreadCount) {
        return;
    }
    _unreadCount = count;
    _unreadCountView.count = count;
}

- (CGFloat)minimumWidthIncludingIcon {
    const CGFloat minPreferred = self.component.statusBarComponentMinimumWidth;
    NSDictionary *knobValues = self.component.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    NSNumber *knobValue = knobValues[iTermStatusBarMinimumWidthKey];
    const CGFloat minExIcon = knobValue ? MAX(minPreferred, knobValue.doubleValue) : minPreferred;
    if (self.component.statusBarComponentIcon) {
        return minExIcon + iTermStatusBarViewControllerIconWidth + iTermStatusBarViewControllerMargin;
    } else {
        return minExIcon + iTermStatusBarViewControllerMargin;
    }
}

- (void)clickRecognized:(id)sender {
    [_component statusBarComponentDidClickWithView:_view];
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
    DLog(@"Timer fired with interval %@", @(timer.timeInterval));
    [self setNeedsUpdate];
}

- (void)setNeedsUpdate {
    if (_needsUpdate) {
        return;
    }
    DLog(@"setNeedsUpdate:%@\n%@", self.component, [NSThread callStackSymbols]);
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
    [self updateIconIfNeeded];
    [self.component statusBarComponentUpdate];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self layoutSubviews];
}

- (void)layoutSubviews {
    CGFloat width = self.frame.size.width;
    if (self.component.statusBarComponentIcon) {
        width -= iTermStatusBarViewControllerIconWidth;
    }

    [self.component statusBarComponentSizeView:_view toFitWidth:width];
    [self updateIconIfNeeded];
    const CGFloat viewHeight = _view.frame.size.height;
    const CGFloat myHeight = self.frame.size.height;
    const CGFloat viewWidth = _view.frame.size.width;
    DLog(@"set frame of view %@ for component %@ width to %@", _view, self.component, @(viewWidth));
    _view.frame = NSMakeRect([self retinaRound:self.minX],
                             [self retinaRound:(myHeight - viewHeight) / 2 + _component.statusBarComponentVerticalOffset],
                             [self retinaRoundUp:self.preferredWidthForComponentView],
                             [self retinaRoundUp:viewHeight]);
    CGFloat margin = -2;
    _unreadCountView.frame = NSMakeRect(NSMaxX(self.bounds) - NSWidth(_unreadCountView.frame) - margin,
                                        [self retinaRound:NSMidY(self.bounds) - NSHeight(_unreadCountView.frame) / 2.0],
                                        NSWidth(_unreadCountView.frame),
                                        NSHeight(_unreadCountView.frame));
}

- (BOOL)wantsDefaultClipping {
    return NO;
}

- (void)viewDidMoveToWindow {
    [_component statusBarComponentDidMoveToWindow];
}

- (nullable NSView *)hitTest:(NSPoint)point {
    NSEvent *event = NSApp.currentEvent;
    if (NSPointInRect(point, self.frame)) {
        if (event.type == NSEventTypeRightMouseUp ||
            event.type == NSEventTypeRightMouseDown) {
            return self;
        }
        if (event.type == NSEventTypeLeftMouseUp ||
            event.type == NSEventTypeLeftMouseDown) {
            if (event.it_modifierFlags & NSEventModifierFlagControl) {
                return self;
            }
        }
    }
    return [super hitTest:point];
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (void)mouseDown:(NSEvent *)event {
    if ([_component statusBarComponentHandlesMouseDown]) {
        [_component statusBarComponentMouseDownWithView:_view];
    } else {
        [super mouseDown:event];
    }
}

- (void)mouseUp:(NSEvent *)event {
    if (event.clickCount != 1 || !(event.it_modifierFlags & NSEventModifierFlagControl)) {
        [super mouseUp:event];
        return;
    }
    [self showContextMenuForEvent:event];
}

- (void)rightMouseUp:(NSEvent *)event {
    if (event.clickCount != 1) {
        [super rightMouseUp:event];
        return;
    }
    [self showContextMenuForEvent:event];
}

- (void)mouseDragged:(NSEvent *)event {
    if ([self shouldDragWindowForEvent:event]) {
        [self.window makeKeyAndOrderFront:nil];
        [self.window performWindowDragWithEvent:event];
        return;
    }
    [super mouseDragged:event];
}

- (BOOL)shouldDragWindowForEvent:(NSEvent *)event {
    if ((event.modifierFlags & NSEventModifierFlagOption) != 0) {
        return YES;
    }
    if ([_component statusBarComponentHandlesMouseDown]) {
        return NO;
    }
    return [self.delegate statusBarContainerViewCanDragWindow:self];
}

- (void)showContextMenuForEvent:(NSEvent *)event {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Contextual Menu"];
    if (![_component statusBarComponentIsInternal]) {
        if ([[_component statusBarComponentKnobs] count]) {
            [menu addItemWithTitle:[NSString stringWithFormat:@"Configure %@", [self.component statusBarComponentShortDescription]]
                            action:@selector(configureComponent:)
                     keyEquivalent:@""];
        }
        [menu addItemWithTitle:[NSString stringWithFormat:@"Hide %@", [self.component statusBarComponentShortDescription]]
                        action:@selector(hideComponent:)
                 keyEquivalent:@""];
    }
    [menu addItemWithTitle:@"Configure Status Bar"
                    action:@selector(configureStatusBar:)
             keyEquivalent:@""];
    [menu addItemWithTitle:@"Disable Status Bar"
                    action:@selector(disableStatusBar:)
             keyEquivalent:@""];
    NSDictionary<NSString *, id> *values = [self.component statusBarComponentKnobValues];
    __block BOOL haveAddedSeparator = NO;
    [[self.component statusBarComponentKnobs] enumerateObjectsUsingBlock:^(iTermStatusBarComponentKnob * _Nonnull knob, NSUInteger idx, BOOL * _Nonnull stop) {
        if (knob.type == iTermStatusBarComponentKnobTypeCheckbox) {
            if (!haveAddedSeparator) {
                haveAddedSeparator = YES;
                [menu addItem:[NSMenuItem separatorItem]];
            }
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:knob.labelText action:@selector(toggleKnob:) keyEquivalent:@""];
            item.identifier = knob.key;
            item.state = [[NSNumber castFrom:values[knob.key]] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
            [menu addItem:item];
        }
    }];
    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

- (void)configureComponent:(id)sender {
    [self.delegate statusBarContainerView:self configureComponent:self.component];
}

- (void)hideComponent:(id)sender {
    [self.delegate statusBarContainerView:self hideComponent:self.component];
}

- (void)configureStatusBar:(id)sender {
    [self.delegate statusBarContainerViewConfigureStatusBar:self];
}

- (void)disableStatusBar:(id)sender {
    [self.delegate statusBarContainerViewDisableStatusBar:self];
}

- (void)toggleKnob:(NSMenuItem *)sender {
    NSString *key = sender.identifier;
    NSMutableDictionary *knobValues = [[self.component statusBarComponentKnobValues] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSNumber *number = [NSNumber castFrom:knobValues[key]];
    knobValues[key] = @(!number.boolValue);
    [self.component statusBarComponentSetKnobValues:knobValues];
}

@end

NS_ASSUME_NONNULL_END
