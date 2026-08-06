//
//  VT100ScreenProgress.h
//  iTerm2
//
//  Created by George Nachman on 10/29/25.
//

#import <Foundation/Foundation.h>

// This must be kept in sync with PSMProgress
typedef NS_ENUM(NSInteger, VT100ScreenProgress) {
    VT100ScreenProgressStopped = 0,
    VT100ScreenProgressError = -1,
    VT100ScreenProgressIndeterminate = -2,
    VT100ScreenProgressSuccessBase = 1000,  // values base...base+100 are percentages.
    VT100ScreenProgressErrorBase = 2000,  // same as .successBase
    VT100ScreenProgressWarningBase = 3000  // same as .successBase
};

// Returns the percentage encoded in progress, whichever base it uses, or -1 if it doesn't
// encode a percentage (i.e., it's stopped or one of the sentinel states).
NS_INLINE int VT100ScreenProgressPercentage(VT100ScreenProgress progress) {
    if (progress >= VT100ScreenProgressSuccessBase && progress <= VT100ScreenProgressSuccessBase + 100) {
        return (int)(progress - VT100ScreenProgressSuccessBase);
    }
    if (progress >= VT100ScreenProgressErrorBase && progress <= VT100ScreenProgressErrorBase + 100) {
        return (int)(progress - VT100ScreenProgressErrorBase);
    }
    if (progress >= VT100ScreenProgressWarningBase && progress <= VT100ScreenProgressWarningBase + 100) {
        return (int)(progress - VT100ScreenProgressWarningBase);
    }
    return -1;
}

NS_INLINE BOOL VT100ScreenProgressIsVisible(VT100ScreenProgress progress) {
    if (progress == VT100ScreenProgressError || progress == VT100ScreenProgressIndeterminate) {
        return YES;
    }
    return VT100ScreenProgressPercentage(progress) >= 0;
}

