//
//  NSWindow+iTerm.h
//  iTerm2
//
//  Created by George Nachman on 7/10/16.
//
//

#import <Cocoa/Cocoa.h>

extern NSString *const iTermWindowAppearanceDidChange;
extern void *const iTermDeclineFirstResponderAssociatedObjectKey;

@interface NSWindow(iTerm)

// Is window Lion fullscreen?
@property(nonatomic, readonly) BOOL isFullScreen;
- (BOOL)isTerminalWindow;

@property (nonatomic, readonly) NSArray<__kindof NSTitlebarAccessoryViewController *> *it_titlebarAccessoryViewControllers;
@property (nonatomic, readonly) NSString *it_styleMaskDescription;

// Use this when making a panel key so it won't dismiss the hotkey window. It works around a problem
// in Cocoa where windowDidResginKey gets called before the new window is key, which I observed
// with the open quickly window.
- (void)it_makeKeyAndOrderFront;

- (NSView *)it_titlebarViewOfClassWithName:(NSString *)className;
- (void)it_titleBarDoubleClick;
- (void)it_shakeNo;

// Usage:
// - (BOOL)makeFirstResponder:(NSResponder *)responder {
//     return [self it_makeFirstResponderIfNotDeclined:responder callSuper:^(NSResponder *newResponder) { return [super makeFirstResponder:newResponder] }];
// }
- (BOOL)it_makeFirstResponderIfNotDeclined:(NSResponder *)responder
                                 callSuper:(BOOL (^ NS_NOESCAPE)(NSResponder *))callSuper;

@end
