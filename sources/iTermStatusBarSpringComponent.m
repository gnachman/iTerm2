//
//  iTermStatusBarSpringComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import "iTermStatusBarSpringComponent.h"

NS_ASSUME_NONNULL_BEGIN

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

@end

NS_ASSUME_NONNULL_END
