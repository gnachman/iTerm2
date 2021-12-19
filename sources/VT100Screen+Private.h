//
//  VT100Screen+Private.h
//  iTerm2
//
//  Created by George Nachman on 12/9/21.
//

#import "IntervalTree.h"
#import "iTermTemporaryDoubleBufferedGridController.h"
#import "LineBuffer.h"
#import "VT100ScreenMark.h"
#import "VT100ScreenState.h"
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
iTermMarkDelegate,
VT100InlineImageHelperDelegate> {
    id<VT100ScreenState> _state;
    VT100ScreenMutableState *_mutableState;

    __weak id<VT100ScreenDelegate> delegate_;  // PTYSession implements this

    iTermExternalAttribute *_lastExternalAttribute;
    BOOL _lastCharacterIsDoubleWidth;

    BOOL saveToScrollbackInAlternateScreen_;
    BOOL _cursorVisible;
    BOOL _shellIntegrationInstalled;

    VT100TerminalProtectedMode _protectedMode;

    // Initial size before calling -restoreFromDictionary… or -1,-1 if invalid.
    VT100GridSize _initialSize;

    // A rarely reset count of the number of lines lost to scrollback overflow. Adding this to a
    // line number gives a unique line number that won't be reused when the linebuffer overflows.
    long long cumulativeScrollbackOverflow_;
}

@property(nonatomic, retain) VT100ScreenMark *lastCommandMark;
@property(nonatomic, retain) iTermTemporaryDoubleBufferedGridController *temporaryDoubleBuffer;
@property(nonatomic, readwrite) VT100GridAbsCoordRange lastCommandOutputRange;
@property(nonatomic, readwrite) VT100GridAbsCoord startOfRunningCommandOutput;

- (NSString *)compactLineDumpWithHistoryAndContinuationMarksAndLineNumbers;
- (Interval *)intervalForGridCoordRange:(VT100GridCoordRange)range;
- (VT100GridCoordRange)commandRange;
- (Interval *)intervalForGridCoordRange:(VT100GridCoordRange)range
                                  width:(int)width
                            linesOffset:(long long)linesOffset;
- (const screen_char_t *)getLineAtIndex:(int)theIndex;
- (void)commandDidStartAt:(VT100GridAbsCoord)coord;
- (void)commandDidStartAtScreenCoord:(VT100GridCoord)coord;
- (iTermIntervalTreeObjectType)intervalTreeObserverTypeForObject:(id<IntervalTreeObject>)object;
- (BOOL)cursorOutsideLeftRightMargin;
- (void)hideOnScreenNotesAndTruncateSpanners;
- (VT100GridRun)runByTrimmingNullsFromRun:(VT100GridRun)run;

@end


