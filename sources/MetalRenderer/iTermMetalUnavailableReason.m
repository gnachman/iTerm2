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
            return ITLocalize(@"MetalUnavailableReason_Facing_NoUsableGpuFoundOnThisMachine", @"no usable GPU found on this machine.", @"User-visible message: no usable GPU found on this machine.");
        case iTermMetalUnavailableReasonDisabled:
            return ITLocalize(@"MetalUnavailableReason_Facing_GpuRendererIsDisabledInSettingsGeneral", @"GPU Renderer is disabled in Settings > General.", @"User-visible message: GPU Renderer is disabled in Settings > General.");
        case iTermMetalUnavailableReasonNotATerminal:
            return ITLocalize(@"MetalUnavailableReason_Facing_TheCurrentSessionIsNotATerminal", @"the current session is not a terminal.", @"User-visible message: the current session is not a terminal.");
        case iTermMetalUnavailableReasonLigatures:
            return ITLocalize(@"MetalUnavailableReason_Facing_LigaturesAreEnabledYouCanDisableThem", @"ligatures are enabled. You can disable them in Settings > Profiles > Text > Use ligatures.", @"User-visible message: ligatures are enabled. You can disable them in Settings > Profiles > Text > Use ligatures.");
        case iTermMetalUnavailableReasonInitializing:
            return ITLocalize(@"MetalUnavailableReason_Facing_TheGpuRendererIsInitializingItShould", @"the GPU renderer is initializing. It should be ready soon.", @"User-visible message: the GPU renderer is initializing. It should be ready soon.");
        case iTermMetalUnavailableReasonInvalidSize:
            return ITLocalize(@"MetalUnavailableReason_Facing_TheSessionIsTooLargeOrToo", @"the session is too large or too small.", @"User-visible message: the session is too large or too small.");
        case iTermMetalUnavailableReasonSessionInitializing:
            return ITLocalize(@"MetalUnavailableReason_Facing_TheSessionIsInitializing", @"the session is initializing.", @"User-visible message: the session is initializing.");
        case iTermMetalUnavailableReasonTransparency:
            return ITLocalize(@"MetalUnavailableReason_Facing_TransparentWindowsAreNotSupportedTheyCan", @"transparent windows are not supported. They can be disabled in Settings > Profiles > Window > Transparency.", @"User-visible message: transparent windows are not supported. They can be disabled in Settings > Profiles > Window > Transparency.");
        case iTermMetalUnavailableReasonVerticalSpacing:
            return ITLocalize(@"MetalUnavailableReason_Facing_TheFontSVerticalSpacingSetTo", @"the font's vertical spacing set to less than 100%. You can change it in Settings > Profiles > Text > Change Font.", @"User-visible message: the font's vertical spacing set to less than 100%. You can change it in Settings > Profiles > Text > Change Font.");
        case iTermMetalUnavailableReasonMarginSize:
            return ITLocalize(@"MetalUnavailableReason_Facing_TerminalWindowMarginsAreTooSmallYou", @"terminal window margins are too small. You can edit them in Settings > Advanced.", @"User-visible message: terminal window margins are too small. You can edit them in Settings > Advanced.");
        case iTermMetalUnavailableReasonAnnotations:
            return ITLocalize(@"MetalUnavailableReason_Facing_AnnotationsOrUrlShortcutsAreOpen", @"annotations or URL shortcuts are open.", @"User-visible message: annotations or URL shortcuts are open.");
        case iTermMetalUnavailableReasonPortholes:
            return ITLocalize(@"MetalUnavailableReason_Facing_ThisSessionHasNativelyRenderedItems", @"this session has natively rendered items.", @"User-visible message: this session has natively rendered items.");
        case iTermMetalUnavailableReasonFindPanel:
            return ITLocalize(@"MetalUnavailableReason_Facing_TheFindPanelIsOpen", @"the find panel is open.", @"User-visible message: the find panel is open.");
        case iTermMetalUnavailableReasonPasteIndicator:
            return ITLocalize(@"MetalUnavailableReason_Facing_ThePasteProgressIndicatorIsOpen", @"the paste progress indicator is open.", @"User-visible message: the paste progress indicator is open.");
        case iTermMetalUnavailableReasonAnnouncement:
            return ITLocalize(@"MetalUnavailableReason_Facing_AnAnnouncementYellowBarIsVisible", @"an announcement (yellow bar) is visible.", @"User-visible message: an announcement (yellow bar) is visible.");
        case iTermMetalUnavailableReasonURLPreview:
            return ITLocalize(@"MetalUnavailableReason_Facing_AUrlPreviewIsVisible", @"a URL preview is visible.", @"User-visible message: a URL preview is visible.");
        case iTermMetalUnavailableReasonWindowResizing:
            return ITLocalize(@"MetalUnavailableReason_Facing_TheWindowIsBeingResized", @"the window is being resized.", @"User-visible message: the window is being resized.");
        case iTermMetalUnavailableReasonDisconnectedFromPower:
            return ITLocalize(@"MetalUnavailableReason_Facing_TheComputerIsNotConnectedToPower",
                              @"the computer is not connected to power. You can enable GPU rendering while disconnected from "
                              @"power in Settings > General > Advanced GPU Settings.",
                              @"User-visible message: the computer is not connected to power. You can enable GPU rendering while disconnected from power in Settings > General > Advanced GPU Settings.");
        case iTermMetalUnavailableReasonIdle:
            return ITLocalize(@"MetalUnavailableReason_Facing_TheSessionIsIdleYouCanEnable", @"the session is idle. You can enable Metal while idle in Settings > Advanced.", @"User-visible message: the session is idle. You can enable Metal while idle in Settings > Advanced.");
        case iTermMetalUnavailableReasonTooManyPanesReason:
            return ITLocalize(@"MetalUnavailableReason_Facing_ThisTabHasTooManySplitPanes", @"This tab has too many split panes", @"User-visible message: This tab has too many split panes");
        case iTermMetalUnavailableReasonNoFocus:
            return ITLocalize(@"MetalUnavailableReason_Facing_TheWindowDoesNotHaveKeyboardFocus", @"the window does not have keyboard focus.", @"User-visible message: the window does not have keyboard focus.");
        case iTermMetalUnavailableReasonTabInactive:
            return ITLocalize(@"MetalUnavailableReason_Facing_ThisTabIsNotActive", @"this tab is not active.", @"User-visible message: this tab is not active.");
        case iTermMetalUnavailableReasonTabBarTemporarilyVisible:
            return ITLocalize(@"MetalUnavailableReason_Facing_TheTabBarIsTemporarilyVisible", @"the tab bar is temporarily visible.", @"User-visible message: the tab bar is temporarily visible.");
        case iTermMetalUnavailableReasonScreensChanging:
            return ITLocalize(@"MetalUnavailableReason_Facing_TheScreenConfigurationHasJustChanged", @"the screen configuration has just changed.", @"User-visible message: the screen configuration has just changed.");
        case iTermMetalUnavailableReasonContextAllocationFailure:
            return ITLocalize(@"MetalUnavailableReason_Facing_OfATemporaryFailureToAllocateA", @"of a temporary failure to allocate a graphics context.", @"User-visible message: of a temporary failure to allocate a graphics context.");
        case iTermMetalUnavailableReasonTabDragInProgress:
            return ITLocalize(@"MetalUnavailableReason_Facing_ATabIsBeingDragged", @"a tab is being dragged.", @"User-visible message: a tab is being dragged.");
        case iTermMetalUnavailableReasonSessionHasNoWindow:
            return ITLocalize(@"MetalUnavailableReason_Facing_TheCurrentSessionHasNoWindowThis", @"the current session has no window (this shouldn't happen).", @"User-visible message: the current session has no window (this shouldn't happen).");
        case iTermMetalUnavailableReasonDropTargetsVisible:
            return ITLocalize(@"MetalUnavailableReason_Facing_SecureCopyDropTargetsAreVisible", @"secure copy drop targets are visible.", @"User-visible message: secure copy drop targets are visible.");
        case iTermMetalUnavailableReasonSwipingBetweenTabs:
            return ITLocalize(@"MetalUnavailableReason_Facing_SwipingBetweenTabs", @"swiping between tabs", @"User-visible message: swiping between tabs");
        case iTermMetalUnavailableReasonSplitPaneBeingDragged:
            return ITLocalize(@"MetalUnavailableReason_Facing_ASplitPaneIsBeingDragged", @"a split pane is being dragged.", @"User-visible message: a split pane is being dragged.");
        case iTermMetalUnavailableReasonWindowObscured:
            return ITLocalize(@"MetalUnavailableReason_Facing_TheWindowIsMostlyUnderAnotherWindow", @"the window is mostly under another window.", @"User-visible message: the window is mostly under another window.");
        case iTermMetalUnavailableReasonLowerPowerMode:
            return ITLocalize(@"MetalUnavailableReason_Facing_MacOsIsInLowPowerMode", @"macOS is in low power mode.", @"User-visible message: macOS is in low power mode.");
    }

    return ITLocalize(@"MetalUnavailableReason_Facing_OfAnInternalErrorPleaseFileA", @"of an internal error. Please file a bug report!", @"User-visible message: of an internal error. Please file a bug report!");
}
