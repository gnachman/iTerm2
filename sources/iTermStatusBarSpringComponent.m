//
//  iTermStatusBarSpringComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import "iTermStatusBarSpringComponent.h"

#import "NSDictionary+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const iTermStatusBarSpringComponentSpringConstantKey = @"iTermStatusBarSpringComponentSpringConstantKey";

@implementation iTermStatusBarSpringComponent {
    NSView *_view;
}

+ (instancetype)springComponentWithCompressionResistance:(double)compressionResistance {
    NSDictionary *knobs = @{ iTermStatusBarSpringComponentSpringConstantKey: @(compressionResistance) };
    NSDictionary *configuration = @{ iTermStatusBarComponentConfigurationKeyKnobValues: knobs };
    return [[iTermStatusBarSpringComponent alloc] initWithConfiguration:configuration];
}

- (id)statusBarComponentExemplar {
    return @"║┄┄║";
}

- (NSString *)statusBarComponentShortDescription {
    return @"Spring";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Pushes items apart. Use one spring to right-align status bar elements that follow it. Use two to center those inbetween.";
}

- (NSView *)statusBarComponentCreateView {
    if (!_view) {
        _view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, self.statusBarComponentMinimumWidth, 0)];
        _view.wantsLayer = YES;
        _view.layer.backgroundColor = [self color].CGColor;
    }
    return _view;
}

- (void)statusBarComponentSizeView:(NSView *)view toFitWidth:(CGFloat)width {
    NSRect rect = view.frame;
    rect.size.width = width;
    rect.size.height = view.superview.frame.size.height;
    view.frame = rect;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return 0;
}

- (NSColor *)color {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobValues[iTermStatusBarSharedBackgroundColorKey] colorValue] ?: [self statusBarBackgroundColor];
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *springConstantKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Compression Resistance:"
                                                          type:iTermStatusBarComponentKnobTypeDouble
                                                   placeholder:@""
                                                  defaultValue:@0.01
                                                           key:iTermStatusBarSpringComponentSpringConstantKey];
    iTermStatusBarComponentKnob *backgroundColorKnob =
    [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Color"
                                                      type:iTermStatusBarComponentKnobTypeColor
                                               placeholder:nil
                                              defaultValue:nil
                                                       key:iTermStatusBarSharedBackgroundColorKey];
    return @[ springConstantKnob, backgroundColorKnob ];
}

+ (NSDictionary *)statusBarComponentDefaultKnobs {
    NSDictionary *fromSuper = [super statusBarComponentDefaultKnobs];
    return [fromSuper dictionaryByMergingDictionary:@{ iTermStatusBarSpringComponentSpringConstantKey: @0.01 }];
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

- (BOOL)statusBarComponentHasMargins {
    return NO;
}

@end

NS_ASSUME_NONNULL_END
