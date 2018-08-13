//
//  iTermGenericStatusBarContainer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/12/18.
//

#import "iTermGenericStatusBarContainer.h"

@implementation iTermGenericStatusBarContainer

@synthesize statusBarViewController = _statusBarViewController;

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self layoutStatusBar];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self layoutStatusBar];
}

- (void)setStatusBarViewController:(iTermStatusBarViewController *)statusBarViewController {
    [_statusBarViewController.view removeFromSuperview];
    _statusBarViewController = statusBarViewController;
    if (statusBarViewController) {
        [self addSubview:statusBarViewController.view];
    }
    [self layoutStatusBar];
}

- (void)layoutStatusBar {
    _statusBarViewController.view.frame = NSMakeRect(0,
                                                     0,
                                                     self.frame.size.width,
                                                     iTermStatusBarHeight);
}

- (void)drawRect:(NSRect)dirtyRect {
    [[self.delegate genericStatusBarContainerBackgroundColor] set];
    NSRectFill(dirtyRect);
}

@end
