//
//  iTermStatusBarFixedSpacerComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import "iTermStatusBarFixedSpacerComponent.h"

#import "NSDictionary+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermStatusBarFixedSpacerComponent {
    NSView *_view;
}

- (id)statusBarComponentExemplar {
    return @"";
}

- (NSString *)statusBarComponentShortDescription {
    return @"Fixed-size Spacer";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Adds ten points of space";
}

- (NSView *)statusBarComponentCreateView {
    if (!_view) {
        _view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, self.statusBarComponentMinimumWidth, 0)];
        _view.wantsLayer = YES;
        _view.layer.backgroundColor = [self color].CGColor;
    }
    return _view;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return 5;
}

- (NSColor *)color {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobValues[iTermStatusBarSharedBackgroundColorKey] colorValue] ?: [self statusBarBackgroundColor];
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *backgroundColorKnob =
    [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Color"
                                                      type:iTermStatusBarComponentKnobTypeColor
                                               placeholder:nil
                                              defaultValue:nil
                                                       key:iTermStatusBarSharedBackgroundColorKey];
    return @[ backgroundColorKnob ];
}


@end

NS_ASSUME_NONNULL_END
