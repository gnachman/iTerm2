//
//  iTermTabBarAccessoryViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/21/18.
//

#import "iTermTabBarAccessoryViewController.h"
#import "iTermAdvancedSettingsModel.h"

@interface iTermTabBarAccessoryViewController ()
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
    self.view = _view;
}

- (__kindof NSView *)realView {
    return _view;
}

@end
