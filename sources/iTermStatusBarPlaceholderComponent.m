//
//  iTermStatusBarPlaceholderComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 09/03/19.
//

#import "iTermStatusBarPlaceholderComponent.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermStatusBarPlaceholderComponent

- (NSString *)statusBarComponentShortDescription {
    return @"Placeholder";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Placeholder";
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    assert(NO);
    return @"";
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (nullable NSString *)stringValue {
    return @"Tap to configure status bar";
}

- (nullable NSString *)stringValueForCurrentWidth {
    return self.stringValue;
}

- (nullable NSArray<NSString *> *)stringVariants {
    return @[ self.stringValue ?: @"" ];
}

- (BOOL)statusBarComponentHandlesClicks {
    return YES;
}

- (void)statusBarComponentDidClickWithView:(NSView *)view {
    [self.delegate statusBarComponentOpenStatusBarPreferences:self];
}

@end

NS_ASSUME_NONNULL_END
