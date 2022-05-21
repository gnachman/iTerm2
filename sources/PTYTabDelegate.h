//
//  PTYTabDelegate.h
//  iTerm2
//
//  Created by George Nachman on 6/9/15.
//
//

#import "iTermMetalUnavailableReason.h"

#import "iTermSwipeHandler.h"

@class iTermImageWrapper;
@class iTermVariables;
@class NSImage;
@class PTYSession;
@class PTYTab;

// States
typedef NS_OPTIONS(NSUInteger, PTYTabState) {
    // Bell has rung.
    kPTYTabBellState = (1 << 0),

    // Background tab is idle; it's been a while since new output arrived.
    kPTYTabIdleState = (1 << 1),

    // Background tab just got new output.
    kPTYTabNewOutputState = (1 << 2),

    // A session has ended.
    kPTYTabDeadState = (1 << 3)
};

@protocol PTYTabDelegate<iTermSwipeHandler, NSObject>

- (void)tab:(PTYTab *)tab didChangeProcessingStatus:(BOOL)isProcessing;
- (void)tab:(PTYTab *)tab didChangeIcon:(NSImage *)icon;
- (void)tab:(PTYTab *)tab didChangeObjectCount:(NSInteger)objectCount;
- (void)tabKeyLabelsDidChangeForSession:(PTYSession *)session;
- (void)tabInvalidateProxyIcon:(PTYTab *)tab;
- (void)tabRemoveTab:(PTYTab *)tab;
- (void)tab:(PTYTab *)tab didChangeToState:(PTYTabState)newState;
- (void)tabDidChangeTmuxLayout:(PTYTab *)tab;
- (void)tab:(PTYTab *)tab didSetMetalEnabled:(BOOL)useMetal;
- (void)tabSessionDidChangeBackgroundColor:(PTYTab *)tab;
- (void)tabDidChangeGraphic:(PTYTab *)tab
                 shouldShow:(BOOL)shouldShow
                      image:(NSImage *)image;
- (BOOL)tabCanUseMetal:(PTYTab *)tab reason:(out iTermMetalUnavailableReason *)reason;
- (void)tabDidChangeMetalViewVisibility:(PTYTab *)tab;
- (BOOL)tabShouldUseTransparency:(PTYTab *)tab;
- (void)numberOfSessionsDidChangeInTab:(PTYTab *)tab;
- (BOOL)tabAnyDragInProgress:(PTYTab *)tab;
- (void)tabDidInvalidateStatusBar:(PTYTab *)tab;
- (iTermVariables *)tabWindowVariables:(PTYTab *)tab;
- (void)tabDidSetWindowTitle:(PTYTab *)tab to:(NSString *)title;
- (void)tabHasNontrivialJobDidChange:(PTYTab *)tab;
- (void)tabEditActions:(PTYTab *)tab;
- (void)tabEditSnippets:(PTYTab *)tab;
- (void)tab:(PTYTab *)tab
setBackgroundImage:(iTermImageWrapper *)image
       mode:(iTermBackgroundImageMode)imageMode
backgroundColor:(NSColor *)backgroundColor;
- (iTermImageWrapper *)tabBackgroundImage;
- (iTermBackgroundImageMode)tabBackgroundImageMode;
- (CGFloat)tabBlend;
- (void)tabActiveSessionDidUpdatePreferencesFromProfile:(PTYTab *)tab;
- (BOOL)tabIsSwiping;
- (NSSize)tabExpectedSize;
- (void)tabActiveSessionDidResize:(PTYTab *)tab;
- (BOOL)tabPasswordManagerWindowIsOpen;
- (BOOL)tabCanDragByPaneTitleBar;
- (void)tabEndSyntheticSession:(PTYSession *)syntheticSession;
- (void)tab:(PTYTab *)tab sessionDidRestart:(PTYSession *)session;
- (void)tab:(PTYTab *)tab closeSession:(PTYSession *)session;
- (void)tabProcessInfoProviderDidChange:(PTYTab *)tab;

@end
