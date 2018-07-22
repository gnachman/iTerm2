//
//  iTermStatusBarFixedSpacerComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import "iTermStatusBarFixedSpacerComponent.h"

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
    }
    return _view;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return 5;
}

@end

NS_ASSUME_NONNULL_END
