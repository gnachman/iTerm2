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

- (void)viewDidMoveToWindow {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.window) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(redraw)
                                                     name:NSWindowDidBecomeKeyNotification
                                                   object:self.window];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(redraw)
                                                     name:NSWindowDidResignKeyNotification
                                                   object:self.window];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(redraw)
                                                 name:NSApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(redraw)
                                                 name:NSApplicationDidResignActiveNotification
                                               object:nil];
}

- (void)redraw {
    [self setNeedsDisplay:YES];
}

@end
