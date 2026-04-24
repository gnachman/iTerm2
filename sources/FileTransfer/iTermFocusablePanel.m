//
//  iTermFocusablePanel.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/3/20.
//

#import "iTermFocusablePanel.h"

@implementation iTermFocusablePanel

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}
@end

