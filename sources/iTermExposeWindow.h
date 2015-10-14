//
//  iTermExposeWindow.h
//  iTerm
//
//  Created by George Nachman on 1/19/14.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermExposeWindow : NSWindow

@property(nonatomic, readonly) BOOL disableFocusFollowsMouse;

- (void)keyDown:(NSEvent *)event;

@end

