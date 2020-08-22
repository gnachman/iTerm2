//
//  PseudoTerminal+Private.h
//  iTerm2
//
//  Created by George Nachman on 2/20/17.
//
//

#import "PseudoTerminal.h"

@class iTermRootTerminalView;
@class iTermWindowShortcutLabelTitlebarAccessoryViewController;

@interface PseudoTerminal() {
    // Is this a full screen window?
    BOOL _fullScreen;

    // This is set while toggling full screen. It prevents windowDidResignMain
    // from trying to exit fullscreen mode in the midst of toggling it.
    BOOL togglingFullScreen_;

    // True while entering lion fullscreen (the animation is going on)
    BOOL togglingLionFullScreen_;

    // In 10.7 style full screen mode
    BOOL lionFullScreen_;

    BOOL exitingLionFullscreen_;

    NSInteger _fullScreenRetryCount;

    NSMutableArray<void (^)(BOOL)> *_toggleFullScreenModeCompletionBlocks;

    // Is there a pending delayed-perform of enterFullScreen:? Used to figure
    // out if it's safe to toggle Lion full screen since only one can go at a time.
    BOOL _haveDelayedEnterFullScreenMode;

    // In the process of zooming in Lion or later.
    BOOL zooming_;

    // When you enter full-screen mode the old frame size is saved here. When
    // full-screen mode is exited that frame is restored.
    NSRect oldFrame_;
    BOOL oldFrameSizeIsBogus_;  // If set, the size in oldFrame_ shouldn't be used.
    NSRect _forceFrame;
    NSTimeInterval _forceFrameUntil;
    NSArray *_screenConfigurationAtTimeOfForceFrame;

    BOOL _willClose;

    // DO NOT ACCESS DIRECTLY - USE ACCESSORS INSTEAD
    iTermWindowType _windowType;

    // DO NOT ACCESS DIRECTLY - USE ACCESSORS INSTEAD
    // Window type before entering fullscreen. Only relevant if in/entering fullscreen.
    iTermWindowType _savedWindowType;
    BOOL _updatingWindowType;  // updateWindowType is not reentrant

    iTermWindowShortcutLabelTitlebarAccessoryViewController *_shortcutAccessoryViewController;

    // When you enter fullscreen mode, the old use transparency setting is
    // saved, and then restored when you exit FS unless it was changed
    // by the user.
    BOOL oldUseTransparency_;
    BOOL restoreUseTransparency_;
    // Is the transparency setting respected?
    BOOL useTransparency_;

    BOOL _settingStyleMask;
}

@property (nonatomic, retain) NSCustomTouchBarItem *tabsTouchBarItem;
@property (nonatomic, retain) NSCandidateListTouchBarItem<NSString *> *autocompleteCandidateListItem;
@property(nonatomic, readonly) BOOL wellFormed;
@property(nonatomic, readwrite) BOOL isReplacingWindow;
@property(nonatomic, copy) NSString *swipeIdentifier;

// Called when entering fullscreen has finished.
// Used to make restoring fullscreen windows work on 10.11.
@property(nonatomic, copy) void (^didEnterLionFullscreen)(PseudoTerminal *);

// This is a reference to the window's content view, here for convenience because it has
// the right type.
@property (nonatomic, readonly) __unsafe_unretained iTermRootTerminalView *contentView;

- (void)returnTabBarToContentView;
- (void)updateForTransparency:(NSWindow<PTYWindow> *)window;
- (void)updateVariables;
- (NSSize)preferredWindowFrameToPerfectlyFitCurrentSessionInInitialConfiguration;
- (void)addShortcutAccessorViewControllerToTitleBarIfNeeded;
- (void)updateTabBarControlIsTitlebarAccessory;
- (NSSize)windowDecorationSize;
- (void)fitTabsToWindow;
- (void)updateUseTransparency;
- (BOOL)updateSessionScrollbars;
- (void)saveTmuxWindowOrigins;
- (void)updateUseMetalInAllTabs;
- (void)updateWindowMenu;
- (void)notifyTmuxOfWindowResize;
- (BOOL)shouldRevealStandardWindowButtons;
- (void)hideStandardWindowButtonsAndTitlebarAccessories;
- (NSArray *)screenConfiguration;

@end


