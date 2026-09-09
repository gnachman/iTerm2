//
//  iTermMetalUnavailableReason.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/15/21.
//

#import "iTermMetalUnavailableReason.h"

NSString *iTermMetalUnavailableReasonDescription(iTermMetalUnavailableReason reason) {
    switch (reason) {
        case iTermMetalUnavailableReasonNone:
            return nil;
        case iTermMetalUnavailableReasonNoGPU:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.NoGPU", nil, [NSBundle mainBundle], @"no usable GPU found on this machine.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonDisabled:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.Disabled", nil, [NSBundle mainBundle], @"GPU Renderer is disabled in Settings > General.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonNotATerminal:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.NotATerminal", nil, [NSBundle mainBundle], @"the current session is not a terminal.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonLigatures:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.Ligatures", nil, [NSBundle mainBundle], @"ligatures are enabled. You can disable them in Settings > Profiles > Text > Use ligatures.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonInitializing:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.Initializing", nil, [NSBundle mainBundle], @"the GPU renderer is initializing. It should be ready soon.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonInvalidSize:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.InvalidSize", nil, [NSBundle mainBundle], @"the session is too large or too small.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonSessionInitializing:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.SessionInitializing", nil, [NSBundle mainBundle], @"the session is initializing.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonTransparency:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.Transparency", nil, [NSBundle mainBundle], @"transparent windows are not supported. They can be disabled in Settings > Profiles > Window > Transparency.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonVerticalSpacing:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.VerticalSpacing", nil, [NSBundle mainBundle], @"the font's vertical spacing set to less than 100%. You can change it in Settings > Profiles > Text > Change Font.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonMarginSize:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.MarginSize", nil, [NSBundle mainBundle], @"terminal window margins are too small. You can edit them in Settings > Advanced.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonAnnotations:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.Annotations", nil, [NSBundle mainBundle], @"annotations or URL shortcuts are open.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonPortholes:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.Portholes", nil, [NSBundle mainBundle], @"this session has natively rendered items.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonFindPanel:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.FindPanel", nil, [NSBundle mainBundle], @"the find panel is open.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonPasteIndicator:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.PasteIndicator", nil, [NSBundle mainBundle], @"the paste progress indicator is open.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonAnnouncement:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.Announcement", nil, [NSBundle mainBundle], @"an announcement (yellow bar) is visible.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonURLPreview:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.URLPreview", nil, [NSBundle mainBundle], @"a URL preview is visible.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonWindowResizing:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.WindowResizing", nil, [NSBundle mainBundle], @"the window is being resized.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonDisconnectedFromPower:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.DisconnectedFromPower", nil, [NSBundle mainBundle], @"the computer is not connected to power. You can enable GPU rendering while disconnected from "
            @"power in Settings > General > Advanced GPU Settings.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonIdle:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.Idle", nil, [NSBundle mainBundle], @"the session is idle. You can enable Metal while idle in Settings > Advanced.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonTooManyPanesReason:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.TooManyPanes", nil, [NSBundle mainBundle], @"This tab has too many split panes", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonNoFocus:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.NoFocus", nil, [NSBundle mainBundle], @"the window does not have keyboard focus.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonTabInactive:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.TabInactive", nil, [NSBundle mainBundle], @"this tab is not active.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonTabBarTemporarilyVisible:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.TabBarVisible", nil, [NSBundle mainBundle], @"the tab bar is temporarily visible.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonScreensChanging:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.ScreensChanging", nil, [NSBundle mainBundle], @"the screen configuration has just changed.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonContextAllocationFailure:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.ContextAllocationFailure", nil, [NSBundle mainBundle], @"of a temporary failure to allocate a graphics context.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonTabDragInProgress:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.TabDragInProgress", nil, [NSBundle mainBundle], @"a tab is being dragged.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonSessionHasNoWindow:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.SessionHasNoWindow", nil, [NSBundle mainBundle], @"the current session has no window (this shouldn't happen).", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonDropTargetsVisible:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.DropTargetsVisible", nil, [NSBundle mainBundle], @"secure copy drop targets are visible.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonSwipingBetweenTabs:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.SwipingBetweenTabs", nil, [NSBundle mainBundle], @"swiping between tabs", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonSplitPaneBeingDragged:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.SplitPaneBeingDragged", nil, [NSBundle mainBundle], @"a split pane is being dragged.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonWindowObscured:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.WindowObscured", nil, [NSBundle mainBundle], @"the window is mostly under another window.", @"GPU renderer unavailable reason");
        case iTermMetalUnavailableReasonLowerPowerMode:
            return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.LowPowerMode", nil, [NSBundle mainBundle], @"macOS is in low power mode.", @"GPU renderer unavailable reason");
    }

    return NSLocalizedStringWithDefaultValue(@"MetalUnavailable.InternalError", nil, [NSBundle mainBundle], @"of an internal error. Please file a bug report!", @"GPU renderer unavailable reason");
}
