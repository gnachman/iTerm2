//
//  iTermExposeWindow.h
//  iTerm
//
//  Created by George Nachman on 1/19/14.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermExposeWindow : NSWindow
{
}

- (BOOL)canBecomeKeyWindow;
- (void)keyDown:(NSEvent *)event;
- (BOOL)disableFocusFollowsMouse;

@end

