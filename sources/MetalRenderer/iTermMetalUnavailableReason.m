//
//  iTermMetalUnavailableReason.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/15/21.
//

#import "iTermMetalUnavailableReason.h"

// Each reason is a complete sentence so translations can word it freely.
NSString *iTermMetalUnavailableReasonDescription(iTermMetalUnavailableReason reason) {
    switch (reason) {
        case iTermMetalUnavailableReasonNone:
            return nil;
        case iTermMetalUnavailableReasonNoGPU:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.NoGPU", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because no usable GPU was found on this machine.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonDisabled:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.Disabled", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because the GPU Renderer is disabled in Settings > General.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonNotATerminal:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.NotATerminal", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because the current session is not a terminal.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonLigatures:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.Ligatures", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because ligatures are enabled. You can disable them in Settings > Profiles > Text > Use ligatures.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonInitializing:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.Initializing", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because the GPU renderer is initializing. It should be ready soon.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonInvalidSize:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.InvalidSize", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because the session is too large or too small.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonSessionInitializing:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.SessionInitializing", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because the session is initializing.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonTransparency:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.Transparency", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because transparent windows are not supported. They can be disabled in Settings > Profiles > Window > Transparency.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonVerticalSpacing:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.VerticalSpacing", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because the font’s vertical spacing is set to less than 100%. You can change it in Settings > Profiles > Text > Change Font.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonMarginSize:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.MarginSize", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because terminal window margins are too small. You can edit them in Settings > Advanced.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonAnnotations:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.Annotations", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because annotations or URL shortcuts are open.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonPortholes:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.Portholes", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because this session has natively rendered items.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonFindPanel:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.FindPanel", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because the find panel is open.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonPasteIndicator:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.PasteIndicator", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because the paste progress indicator is open.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonAnnouncement:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.Announcement", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because an announcement (yellow bar) is visible.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonURLPreview:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.URLPreview", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because a URL preview is visible.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonWindowResizing:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.WindowResizing", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because the window is being resized.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonDisconnectedFromPower:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.DisconnectedFromPower", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because the computer is not connected to power. You can enable GPU rendering while disconnected from power in Settings > General > Advanced GPU Settings.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonIdle:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.Idle", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because the session is idle. You can enable Metal while idle in Settings > Advanced.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonTooManyPanesReason:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.TooManyPanes", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because this tab has too many split panes.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonNoFocus:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.NoFocus", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because the window does not have keyboard focus.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonTabInactive:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.TabInactive", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because this tab is not active.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonTabBarTemporarilyVisible:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.TabBarVisible", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because the tab bar is temporarily visible.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonScreensChanging:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.ScreensChanging", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because the screen configuration has just changed.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonContextAllocationFailure:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.ContextAllocationFailure", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because of a temporary failure to allocate a graphics context.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonTabDragInProgress:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.TabDragInProgress", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because a tab is being dragged.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonSessionHasNoWindow:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.SessionHasNoWindow", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because the current session has no window (this shouldn’t happen).", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonDropTargetsVisible:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.DropTargetsVisible", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because secure copy drop targets are visible.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonSwipingBetweenTabs:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.SwipingBetweenTabs", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because you are swiping between tabs.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonSplitPaneBeingDragged:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.SplitPaneBeingDragged", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because a split pane is being dragged.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonWindowObscured:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.WindowObscured", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because the window is mostly under another window.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
        case iTermMetalUnavailableReasonLowerPowerMode:
            return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.LowPowerMode", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because macOS is in low power mode.", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
    }

    return NSLocalizedStringWithDefaultValue(@"GPURenderer.Off.InternalError", nil, [NSBundle mainBundle], @"GPU rendering is off in the current session because of an internal error. Please file a bug report!", @"Shown in Help > GPU Renderer Availability: why GPU rendering is off in the current session");
}
