//
//  iTermMetalUnavailableReason.h
//  iTerm2
//
//  Created by George Nachman on 9/29/18.
//

typedef NS_ENUM(NSUInteger, iTermMetalUnavailableReason) {
    iTermMetalUnavailableReasonNone,
    iTermMetalUnavailableReasonNoGPU,
    iTermMetalUnavailableReasonDisabled,
    iTermMetalUnavailableReasonLigatures,
    iTermMetalUnavailableReasonInitializing,
    iTermMetalUnavailableReasonInvalidSize,
    iTermMetalUnavailableReasonSessionInitializing,
    iTermMetalUnavailableReasonTransparency,
    iTermMetalUnavailableReasonVerticalSpacing,
    iTermMetalUnavailableReasonMarginSize,
    iTermMetalUnavailableReasonAnnotations,
    iTermMetalUnavailableReasonFindPanel,
    iTermMetalUnavailableReasonPasteIndicator,
    iTermMetalUnavailableReasonAnnouncement,
    iTermMetalUnavailableReasonURLPreview,
    iTermMetalUnavailableReasonWindowResizing,
    iTermMetalUnavailableReasonDisconnectedFromPower,
    iTermMetalUnavailableReasonIdle,
    iTermMetalUnavailableReasonTooManyPanesReason,
    iTermMetalUnavailableReasonNoFocus,
    iTermMetalUnavailableReasonTabInactive,
    iTermMetalUnavailableReasonTabBarTemporarilyVisible,
    iTermMetalUnavailableReasonScreensChanging,
    iTermMetalUnavailableReasonContextAllocationFailure,
    iTermMetalUnavailableReasonTabDragInProgress,
    iTermMetalUnavailableReasonSessionHasNoWindow,
    iTermMetalUnavailableReasonDropTargetsVisible,
    iTermMetalUnavailableReasonSharedBackgroundImage,
    iTermMetalUnavailableReasonSwipingBetweenTabs,
    iTermMetalUnavailableReasonSplitPaneBeingDragged,
    iTermMetalUnavailableReasonWindowObscured
};

static inline NSString *iTermMetalUnavailableReasonDescription(iTermMetalUnavailableReason reason) {
    switch (reason) {
        case iTermMetalUnavailableReasonNone:
            return nil;
        case iTermMetalUnavailableReasonNoGPU:
            return @"no usable GPU found on this machine.";
        case iTermMetalUnavailableReasonDisabled:
            return @"GPU Renderer is disabled in Preferences > General.";
        case iTermMetalUnavailableReasonLigatures:
            return @"ligatures are enabled. You can disable them in Preferences > Profiles > Text > Use ligatures.";
        case iTermMetalUnavailableReasonInitializing:
            return @"the GPU renderer is initializing. It should be ready soon.";
        case iTermMetalUnavailableReasonInvalidSize:
            return @"the session is too large or too small.";
        case iTermMetalUnavailableReasonSessionInitializing:
            return @"the session is initializing.";
        case iTermMetalUnavailableReasonTransparency:
            return @"transparent windows are not supported. They can be disabled in Preferences > Profiles > Window > Transparency.";
        case iTermMetalUnavailableReasonVerticalSpacing:
            return @"the font's vertical spacing set to less than 100%. You can change it in Preferences > Profiles > Text > Change Font.";
        case iTermMetalUnavailableReasonMarginSize:
            return @"terminal window margins are too small. You can edit them in Preferences > Advanced.";
        case iTermMetalUnavailableReasonAnnotations:
            return @"annotations are open. Find the session with visible annotations and close them with View > Show Annotations.";
        case iTermMetalUnavailableReasonFindPanel:
            return @"the find panel is open.";
        case iTermMetalUnavailableReasonPasteIndicator:
            return @"the paste progress indicator is open.";
        case iTermMetalUnavailableReasonAnnouncement:
            return @"an announcement (yellow bar) is visible.";
        case iTermMetalUnavailableReasonURLPreview:
            return @"a URL preview is visible.";
        case iTermMetalUnavailableReasonWindowResizing:
            return @"the window is being resized.";
        case iTermMetalUnavailableReasonDisconnectedFromPower:
            return @"the computer is not connected to power. You can enable GPU rendering while disconnected from "
            @"power in Preferences > General > Advanced GPU Settings.";
        case iTermMetalUnavailableReasonIdle:
            return @"the session is idle. You can enable Metal while idle in Preferences > Advanced.";
        case iTermMetalUnavailableReasonTooManyPanesReason:
            return @"This tab has too many split panes";
        case iTermMetalUnavailableReasonNoFocus:
            return @"the window does not have keyboard focus.";
        case iTermMetalUnavailableReasonTabInactive:
            return @"this tab is not active.";
        case iTermMetalUnavailableReasonTabBarTemporarilyVisible:
            return @"the tab bar is temporarily visible.";
        case iTermMetalUnavailableReasonScreensChanging:
            return @"the screen configuration has just changed.";
        case iTermMetalUnavailableReasonContextAllocationFailure:
            return @"of a temporary failure to allocate a graphics context.";
        case iTermMetalUnavailableReasonTabDragInProgress:
            return @"a tab is being dragged.";
        case iTermMetalUnavailableReasonSessionHasNoWindow:
            return @"the current session has no window (this shouldn't happen).";
        case iTermMetalUnavailableReasonDropTargetsVisible:
            return @"secure copy drop targets are visible.";
        case iTermMetalUnavailableReasonSharedBackgroundImage:
#warning TODO: Try to relax this restriction. Also make sure to update metal availability when it changes.
            return @"background images are not per-pane";
        case iTermMetalUnavailableReasonSwipingBetweenTabs:
            return @"swiping between tabs";
        case iTermMetalUnavailableReasonSplitPaneBeingDragged:
            return @"a split pane is being dragged.";
        case iTermMetalUnavailableReasonWindowObscured:
            return @"the window is mostly under another window.";
    }

    return @"of an internal error. Please file a bug report!";
}
