//
//  iTermStatusBarSearchFieldComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/1/18.
//

#import "iTermStatusBarSearchFieldComponent.h"

#import "iTermMiniSearchFieldViewController.h"
#import "iTermPreferences.h"
#import "iTermStatusBarSetupKnobsViewController.h"
#import "NSAppearance+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

NSString *iTermStatusBarSearchComponentIsTemporaryKey = @"search: temporary";

@implementation iTermStatusBarSearchFieldComponent {
    iTermMiniSearchFieldViewController *_viewController;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return 125;
}

- (void)statusBarComponentSizeView:(NSView *)view toFitWidth:(CGFloat)width {
    assert(view == _viewController.view);
    [_viewController sizeToFitSize:NSMakeSize(width, view.frame.size.height)];
}

- (CGFloat)statusBarComponentPreferredWidth {
    return 200;
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

#pragma mark - iTermStatusBarComponent

- (NSString *)statusBarComponentShortDescription {
    return @"Search Tool";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Search tool to find text in the terminal window.";
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    return @[];
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return @"🔎 Search";
}

- (NSView *)statusBarComponentView {
    [self updateForTerminalBackgroundColor];
    return self.statusBarComponentSearchViewController.view;
}

- (void)statusBarTerminalBackgroundColorDidChange {
    [self updateForTerminalBackgroundColor];
}

- (void)updateForTerminalBackgroundColor {
    NSView *view = self.statusBarComponentSearchViewController.view;
    const iTermPreferencesTabStyle tabStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    NSColor *backgroundColor = [self.delegate statusBarComponentEffectiveBackgroundColor:self];
    const BOOL backgroundIsDark = backgroundColor.isDark;
    if (tabStyle == TAB_STYLE_MINIMAL) {
        if ([self.delegate statusBarComponentTerminalBackgroundColorIsDark:self]) {
            view.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        } else {
            view.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        }
    } else if (backgroundColor != nil &&
               view.effectiveAppearance != nil &&
               backgroundIsDark != view.effectiveAppearance.it_isDark) {
        view.appearance = backgroundIsDark ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] : [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    } else {
        view.appearance = nil;
    }
}

- (nullable NSViewController<iTermFindViewController> *)statusBarComponentSearchViewController {
    if (!_viewController) {
        _viewController = [[iTermMiniSearchFieldViewController alloc] initWithNibName:@"iTermMiniSearchFieldViewController"
                                                                               bundle:[NSBundle bundleForClass:self.class]];
        const BOOL canClose = [self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues][iTermStatusBarSearchComponentIsTemporaryKey] boolValue];
        _viewController.canClose = canClose;

        if (self.advancedConfiguration.font) {
            [_viewController setFont:self.advancedConfiguration.font];
        }
    }
    return _viewController;
}

- (CGFloat)statusBarComponentVerticalOffset {
    return 0;
}

@end

NS_ASSUME_NONNULL_END
