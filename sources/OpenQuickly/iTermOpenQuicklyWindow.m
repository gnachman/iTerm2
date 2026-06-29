//
//  iTermOpenQuicklyWindow.m
//  iTerm
//
//  Created by George Nachman on 7/13/14.
//
//

#import "iTermOpenQuicklyWindow.h"

#import "iTermAdvancedSettingsModel.h"

@implementation iTermOpenQuicklyWindow

- (instancetype)initWithContentRect:(NSRect)contentRect
                          styleMask:(NSWindowStyleMask)style
                            backing:(NSBackingStoreType)backingStoreType
                              defer:(BOOL)flag {
    // NSWindowStyleMaskNonactivatingPanel lets the panel become key without
    // activating iTerm2, which is required for the global Open Quickly hotkey
    // (the panel must accept keystrokes while another app remains in front).
    self = [super initWithContentRect:contentRect
                            styleMask:style | NSWindowStyleMaskNonactivatingPanel
                              backing:backingStoreType
                                defer:flag];
    if (self) {
        // Belt and suspenders: also set the underlying state so AppKit can't
        // fall back to the panel default when our override isn't consulted.
        [super setHidesOnDeactivate:NO];
    }
    return self;
}

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)hidesOnDeactivate {
    // The global hotkey can show this panel while iTerm2 is in the background.
    // The NSPanel default of YES makes the window-server drop the panel on the
    // second invocation (it's already in the "should hide because app inactive"
    // state from the previous orderOut), so override to NO. We still dismiss
    // the panel ourselves via windowDidResignKey: when the user clicks away.
    return NO;
}

- (NSTimeInterval)animationResizeTime:(NSRect)newWindowFrame {
    return MAX(0, [iTermAdvancedSettingsModel openQuicklyAnimationDuration]);
}

- (BOOL)autoHidesHotKeyWindow {
    return NO;
}

- (BOOL)disableFocusFollowsMouse {
    return YES;
}

- (BOOL)implementsDisableFocusFollowsMouse {
    return YES;
}

@end
