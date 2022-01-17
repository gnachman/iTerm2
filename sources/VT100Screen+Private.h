//
//  VT100Screen+Private.h
//  iTerm2
//
//  Created by George Nachman on 12/9/21.
//

#import "IntervalTree.h"
#import "iTermTemporaryDoubleBufferedGridController.h"
#import "LineBuffer.h"
#import "VT100ScreenConfiguration.h"
#import "VT100ScreenMark.h"
#import "VT100ScreenMutableState.h"
#import "VT100Terminal.h"

extern NSString *const kScreenStateKey;
extern NSString *const kScreenStateTabStopsKey;
extern NSString *const kScreenStateTerminalKey;
extern NSString *const kScreenStateLineDrawingModeKey;
extern NSString *const kScreenStateNonCurrentGridKey;
extern NSString *const kScreenStateCurrentGridIsPrimaryKey;
extern NSString *const kScreenStateIntervalTreeKey;
extern NSString *const kScreenStateSavedIntervalTreeKey;
extern NSString *const kScreenStateCommandStartXKey;
extern NSString *const kScreenStateCommandStartYKey;
extern NSString *const kScreenStateNextCommandOutputStartKey;
extern NSString *const kScreenStateCursorVisibleKey;
extern NSString *const kScreenStateTrackCursorLineMovementKey;
extern NSString *const kScreenStateLastCommandOutputRangeKey;
extern NSString *const kScreenStateShellIntegrationInstalledKey;
extern NSString *const kScreenStateLastCommandMarkKey;
extern NSString *const kScreenStatePrimaryGridStateKey;
extern NSString *const kScreenStateAlternateGridStateKey;
extern NSString *const kScreenStateCursorCoord;
extern NSString *const kScreenStateProtectedMode;

@interface VT100Screen () <
iTermTemporaryDoubleBufferedGridControllerDelegate,
iTermLineBufferDelegate,
VT100ScreenSideEffectPerforming> {
    VT100ScreenState *_state;
    VT100ScreenMutableState *_mutableState;

    __weak id<VT100ScreenDelegate> delegate_;  // PTYSession implements this
}

- (NSString *)compactLineDumpWithHistoryAndContinuationMarksAndLineNumbers;
- (VT100GridCoordRange)commandRange;
- (const screen_char_t *)getLineAtIndex:(int)theIndex;
- (id)objectOnOrBeforeLine:(int)line ofClass:(Class)cls;

@end


