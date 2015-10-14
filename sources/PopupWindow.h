//
//  PopupWindow.h
//  iTerm
//
//  Created by George Nachman on 12/27/13.
//
//

#import <Cocoa/Cocoa.h>

@interface PopupWindow : NSWindow

- (instancetype)initWithContentRect:(NSRect)contentRect
                styleMask:(NSUInteger)aStyle
                  backing:(NSBackingStoreType)bufferingType
                    defer:(BOOL)flag;
- (void)setParentWindow:(NSWindow*)parentWindow;
- (void)keyDown:(NSEvent *)event;
- (void)shutdown;

@end
