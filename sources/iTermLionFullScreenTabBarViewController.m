//
//  iTermLionFullScreenTabBarViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/21/18.
//

#import "iTermLionFullScreenTabBarViewController.h"

@interface iTermLionFullScreenTabBarViewController ()

@end

@implementation iTermLionFullScreenTabBarViewController {
    NSView *_view;
}

- (instancetype)initWithView:(NSView *)view {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _view = view;
    }
    return self;
}

- (void)loadView {
    self.view = _view;
}

@end
