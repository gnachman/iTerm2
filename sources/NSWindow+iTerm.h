//
//  NSWindow+iTerm.h
//  iTerm2
//
//  Created by George Nachman on 7/10/16.
//
//

#import <Cocoa/Cocoa.h>

extern NSString *const iTermWindowAppearanceDidChange;

@interface NSWindow(iTerm)

// Is window Lion fullscreen?
@property(nonatomic, readonly) BOOL isFullScreen;
- (BOOL)isTerminalWindow;

@property (nonatomic, readonly) NSArray<__kindof NSTitlebarAccessoryViewController *> *it_titlebarAccessoryViewControllers;
@property (nonatomic, readonly) NSString *it_styleMaskDescription;

@end
