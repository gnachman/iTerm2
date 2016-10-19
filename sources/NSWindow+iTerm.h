//
//  NSWindow+iTerm.h
//  iTerm2
//
//  Created by George Nachman on 7/10/16.
//
//

#import <Cocoa/Cocoa.h>

@interface NSWindow(iTerm)

// Is window Lion fullscreen?
@property(nonatomic, readonly) BOOL isFullScreen;
- (BOOL)isTerminalWindow;

@end
