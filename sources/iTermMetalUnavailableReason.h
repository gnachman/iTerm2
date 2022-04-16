//
//  iTermMetalUnavailableReason.h
//  iTerm2
//
//  Created by George Nachman on 9/29/18.
//

#import <Foundation/Foundation.h>

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
    iTermMetalUnavailableReasonPortholes,
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
    iTermMetalUnavailableReasonSwipingBetweenTabs,
    iTermMetalUnavailableReasonSplitPaneBeingDragged,
    iTermMetalUnavailableReasonWindowObscured,
    iTermMetalUnavailableReasonLowerPowerMode
};

NSString *iTermMetalUnavailableReasonDescription(iTermMetalUnavailableReason reason);
