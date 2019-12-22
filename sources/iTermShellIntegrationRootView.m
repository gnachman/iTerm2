//
//  iTermShellIntegrationRootView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/22/19.
//

#import "iTermShellIntegrationRootView.h"

@implementation iTermShellIntegrationRootView {
    NSTrackingArea *_area;
}

- (void)viewDidMoveToWindow {
    if (!_area) {
        [self createTrackingArea];
    }
    
}
- (void)createTrackingArea {
    NSTrackingAreaOptions options = NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways;
    _area = [[NSTrackingArea alloc] initWithRect:self.bounds options:options owner:self userInfo:nil];
    [self addTrackingArea:_area];
}

- (void)cursorUpdate:(NSEvent *)event {
    [[NSCursor pointingHandCursor] set];
}

@end
