//
//  iTermOpenQuicklyWindow.m
//  iTerm
//
//  Created by George Nachman on 7/13/14.
//
//

#import "iTermOpenQuicklyWindow.h"

@implementation iTermOpenQuicklyWindow

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (NSTimeInterval)animationResizeTime:(NSRect)newWindowFrame {
    return 0.15;
}

- (BOOL)autoHidesHotKeyWindow {
    return NO;
}

@end
