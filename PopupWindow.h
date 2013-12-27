//
//  PopupWindow.h
//  iTerm
//
//  Created by George Nachman on 12/27/13.
//
//

#import <Cocoa/Cocoa.h>

@interface PopupWindow : NSWindow

- (id)initWithContentRect:(NSRect)contentRect
                styleMask:(NSUInteger)aStyle
                  backing:(NSBackingStoreType)bufferingType
                    defer:(BOOL)flag;
- (void)setParentWindow:(NSWindow*)parentWindow;
- (BOOL)canBecomeKeyWindow;
- (void)keyDown:(NSEvent *)event;
- (void)shutdown;

@end
