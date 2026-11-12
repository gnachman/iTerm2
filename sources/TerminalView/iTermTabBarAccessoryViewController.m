//
//  iTermTabBarAccessoryViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/21/18.
//

#import "iTermTabBarAccessoryViewController.h"

#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"

@interface iTermTabBarAccessoryViewController ()<iTermTitleBarAccessoryViewController>
@end

@implementation iTermTabBarAccessoryViewController {
    NSView *_view;
}

- (instancetype)initWithView:(NSView *)view {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _view = view;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p fullScreenMinHeight=%@ frame=%@ window=%p alpha=%@ hidden=%@>",
            NSStringFromClass([self class]),
            self,
            @(self.fullScreenMinHeight),
            NSStringFromRect(self.view.frame),
            self.view.window,
            @(self.view.alphaValue),
            @(self.view.isHidden)];
}

- (void)loadView {
    // Keep corner controls outside the tab bar's overflow and new-tab hit regions.
    NSView *container = [[NSView alloc] initWithFrame:_view.frame];
    _view.frame = container.bounds;
    _view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [container addSubview:_view];
    self.view = container;
}

- (__kindof NSView *)realView {
    return _view;
}

- (BOOL)needsFullScreenMinHeight {
    return YES;
}

@end
