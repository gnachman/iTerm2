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

@property (readonly) BOOL canBecomeKeyWindow;
- (void)keyDown:(NSEvent *)event;
@property (readonly) BOOL disableFocusFollowsMouse;

@end

