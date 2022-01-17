//
//  VT100Screen+Mutation.h
//  iTerm2Shared
//
//  Created by George Nachman on 12/9/21.
//

#import "VT100Screen.h"
#import "VT100Terminal.h"

#import "VT100ScreenMark.h"

@class iTermTemporaryDoubleBufferedGridController;

@protocol iTermOrderedToken;

NS_ASSUME_NONNULL_BEGIN

@interface VT100Screen (Mutation)

@property (nonatomic, readonly) VT100Grid *mutablePrimaryGrid;
@property (nonatomic, readonly) VT100Grid *mutableAltGrid;
@property (nonatomic, readonly) LineBuffer *mutableLineBuffer;

- (void)mutRestoreSavedPositionToFindContext:(FindContext *)context;
- (void)mutSetFindString:(NSString*)aString
     forwardDirection:(BOOL)direction
                 mode:(iTermFindMode)mode
          startingAtX:(int)x
          startingAtY:(int)y
           withOffset:(int)offset
            inContext:(FindContext*)context
         multipleResults:(BOOL)multipleResults;
- (screen_char_t *)mutGetLineAtScreenIndex:(int)theIndex;
- (void)mutResetAllDirty;
- (void)mutSetLineDirtyAtY:(int)y;
- (void)mutSetCharDirtyAtCursorX:(int)x Y:(int)y;
- (void)mutResetDirty;
- (void)mutHighlightRun:(VT100GridRun)run
    withForegroundColor:(NSColor *)fgColor
        backgroundColor:(NSColor *)bgColor;
- (BOOL)mutContinueFindResultsInContext:(FindContext *)context
                                toArray:(NSMutableArray *)results;
- (BOOL)mutGetAndResetHasScrolled;
- (void)mutPopScrollbackLines:(int)linesPushed;
- (void)mutRedrawGrid;
- (void)mutSetMaxScrollbackLines:(unsigned int)lines;
- (PTYTextViewSynchronousUpdateState * _Nullable)mutSetUseSavedGridIfAvailable:(BOOL)useSavedGrid;
- (void)mutSetUnlimitedScrollback:(BOOL)newValue;
- (void)mutResetScrollbackOverflow;
- (void)mutSetCommandStartCoord:(VT100GridAbsCoord)coord;
- (void)mutInvalidateCommandStartCoord;
- (void)mutSaveFindContextPosition;
- (void)mutStoreLastPositionInLineBufferAsFindContextSavedPosition;
- (void)mutSetSaveToScrollbackInAlternateScreen:(BOOL)value;
- (void)mutSaveFindContextAbsPos;
- (void)mutSetTrackCursorLineMovement:(BOOL)trackCursorLineMovement;
- (void)mutSetAppendToScrollbackWithStatusBar:(BOOL)value;
- (void)mutSetShellIntegrationInstalled:(BOOL)shellIntegrationInstalled;
- (void)mutSetNormalization:(iTermUnicodeNormalization)value;
- (void)mutSetIntervalTreeObserver:(id<iTermIntervalTreeObserver>)intervalTreeObserver;
- (void)mutSetDimOnlyText:(BOOL)dimOnlyText;
- (void)mutSetDarkMode:(BOOL)darkMode;
- (void)mutSetUseSeparateColorsForLightAndDarkMode:(BOOL)value;
- (void)mutSetMinimumContrast:(float)value;
- (void)mutSetMutingAmount:(double)value;
- (void)mutSetDimmingAmount:(double)value;
- (void)mutSetDelegate:(id<VT100ScreenDelegate>)delegate;
- (iTermTemporaryDoubleBufferedGridController * _Nullable)mutableTemporaryDoubleBuffer;
- (void)mutUpdateConfig;
- (void)mutSetLastPromptLine:(long long)value;
- (void)mutSetShouldExpectPromptMarks:(BOOL)value;
- (void)mutRestorePreferredCursorPositionIfPossible;
- (void)mutLinkTextInRange:(NSRange)range
basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                   URLCode:(unsigned int)code;
- (void)mutHighlightTextInRange:(NSRange)range
      basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                         colors:(NSDictionary *)colors;
- (void)mutAddTokens:(CVector)vector length:(int)length highPriority:(BOOL)highPriority;
- (void)mutScheduleTokenExecution;
- (void)mutInjectData:(NSData *)data;
- (void)mutPerformPeriodicTriggerCheck;
- (void)mutForceCheckTriggers;
- (void)mutSetExited:(BOOL)exited;
- (void)mutLoadInitialColorTable;

@end

NS_ASSUME_NONNULL_END
