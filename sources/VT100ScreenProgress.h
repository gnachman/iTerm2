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
    VT100ScreenProgressBase = 1000,  // values base...base+100 are percentages.
};

