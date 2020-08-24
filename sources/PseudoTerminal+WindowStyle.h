//
//  PseudoTerminal+WindowStyle.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/21/20.
//

#import "PseudoTerminal.h"

NS_ASSUME_NONNULL_BEGIN

BOOL iTermWindowTypeIsCompact(iTermWindowType windowType);
iTermWindowType iTermWindowTypeNormalized(iTermWindowType windowType);

@interface PseudoTerminal (WindowStyle)

+ (NSWindowStyleMask)styleMaskForWindowType:(iTermWindowType)windowType
                            savedWindowType:(iTermWindowType)savedWindowType
                           hotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType;

- (NSWindow *)setWindowWithWindowType:(iTermWindowType)windowType
                      savedWindowType:(iTermWindowType)savedWindowType
               windowTypeForStyleMask:(iTermWindowType)windowTypeForStyleMask
                     hotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType
                         initialFrame:(NSRect)initialFrame;

+ (BOOL)windowTypeHasFullSizeContentView:(iTermWindowType)windowType;

- (void)changeToWindowType:(iTermWindowType)newWindowType;
- (void)setWindowType:(iTermWindowType)windowType;
- (NSRect)traditionalFullScreenFrameForScreen:(NSScreen *)screen;
- (iTermWindowType)savedWindowType;
- (void)didFinishFullScreenTransitionSuccessfully:(BOOL)success;
- (void)toggleTraditionalFullScreenModeImpl;
- (BOOL)fullScreenImpl;
- (iTermWindowType)windowTypeImpl;
- (IBAction)toggleFullScreenModeImpl:(id)sender;
- (void)toggleFullScreenModeImpl:(id)sender
                      completion:(void (^)(BOOL))completion;
- (BOOL)togglingLionFullScreenImpl;
- (void)delayedEnterFullscreenImpl;
- (void)windowWillEnterFullScreenImpl:(NSNotification *)notification;
- (void)windowDidEnterFullScreenImpl:(NSNotification *)notification;
- (void)windowWillExitFullScreenImpl:(NSNotification *)notification;
- (void)windowDidExitFullScreenImpl:(NSNotification *)notification;
- (void)windowDidFailToEnterFullScreenImpl:(NSWindow *)window;
- (void)updateWindowType;
- (void)clearForceFrame;
- (NSWindowStyleMask)styleMask;
- (void)safelySetStyleMask:(NSWindowStyleMask)styleMask;
- (NSRect)traditionalFullScreenFrame;

@end

NS_ASSUME_NONNULL_END
