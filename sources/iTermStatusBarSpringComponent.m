//
//  iTermStatusBarSpringComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import "iTermStatusBarSpringComponent.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const iTermStatusBarSpringComponentSpringConstantKey = @"iTermStatusBarSpringComponentSpringConstantKey";

@implementation iTermStatusBarSpringComponent {
    NSView *_view;
}

- (id)statusBarComponentExemplar {
    return @"║┄┄║";
}

+ (NSString *)statusBarComponentShortDescription {
    return @"Spring";
}

+ (NSString *)statusBarComponentDetailedDescription {
    return @"Pushes items apart. Use one spring to right-align status bar elements that follow it. Use two to center those inbetween.";
}

- (NSView *)statusBarComponentCreateView {
    if (!_view) {
        _view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, self.statusBarComponentMinimumWidth, 0)];
    }
    return _view;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return 0;
}

+ (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *expressionKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Spring Constant:"
                                                          type:iTermStatusBarComponentKnobTypeDouble
                                                   placeholder:@""
                                                  defaultValue:@1
                                                           key:iTermStatusBarSpringComponentSpringConstantKey];
    return @[ expressionKnob ];
}

- (CGFloat)statusBarComponentSpringConstant {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    NSNumber *number = knobValues[iTermStatusBarSpringComponentSpringConstantKey];
    return MAX(0.01, number ? number.doubleValue : 1);
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (CGFloat)statusBarComponentPreferredWidth {
    return INFINITY;
}

@end

NS_ASSUME_NONNULL_END
