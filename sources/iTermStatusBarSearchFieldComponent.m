//
//  iTermStatusBarSearchFieldComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/1/18.
//

#import "iTermStatusBarSearchFieldComponent.h"

#import "iTermStatusBarSetupKnobsViewController.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermStatusBarSearchFieldComponent

- (CGFloat)statusBarComponentMinimumWidth {
    return 125;
}

- (void)statusBarComponentSizeView:(NSView *)view toFitWidth:(CGFloat)width {
    [[NSSearchField castFrom:view] sizeToFit];
    view.frame = NSMakeRect(0, 0, width, view.frame.size.height);
}

- (CGFloat)statusBarComponentPreferredWidth {
    return 200;
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

#pragma mark - iTermStatusBarComponent

+ (NSString *)statusBarComponentShortDescription {
    return @"Search Tool";
}

+ (NSString *)statusBarComponentDetailedDescription {
    return @"Search tool to find text in the terminal window.";
}

+ (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    return @[];
}

- (id)statusBarComponentExemplar {
    return @"🔎 Search";
}

- (NSView *)statusBarComponentCreateView {
    NSSearchField *view = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    view.controlSize = NSControlSizeSmall;
    view.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeSmall]];
    return view;
}

@end

NS_ASSUME_NONNULL_END
