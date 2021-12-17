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

    VT100Terminal *terminal_;

    // This flag overrides maxScrollbackLines_:
    BOOL unlimitedScrollback_;

    // Current find context.
    FindContext *findContext_;

    // How many scrollback lines have been lost due to overflow. Periodically reset with
    // -resetScrollbackOverflow.
    int scrollbackOverflow_;

    // Location of the start of the current command, or -1 for none. Y is absolute.
    int commandStartX_;
    long long commandStartY_;

    // Maps an absolute line number to a VT100ScreenMark.
    NSMutableDictionary *markCache_;
    VT100GridCoordRange markCacheRange_;

    // Max size of scrollback buffer
    unsigned int maxScrollbackLines_;

    // Where we left off searching.
    long long savedFindContextAbsPos_;

    NSMutableSet* tabStops_;

    // BOOLs indicating, for each of the characters sets, which ones are in line-drawing mode.
    BOOL charsetUsesLineDrawingMode_[4];

    // For REP
    screen_char_t _lastCharacter;
    iTermExternalAttribute *_lastExternalAttribute;
    BOOL _lastCharacterIsDoubleWidth;

    // Cached copies of terminal attributes
    BOOL _wraparoundMode;
    BOOL _ansi;
    BOOL _insert;

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


