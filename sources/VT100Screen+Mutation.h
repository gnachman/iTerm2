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

- (screen_char_t *)mutGetLineAtScreenIndex:(int)theIndex;
- (void)mutResetAllDirty;
- (void)mutSetLineDirtyAtY:(int)y;
- (void)mutSetCharDirtyAtCursorX:(int)x Y:(int)y;
- (void)mutResetDirty;
- (void)mutHighlightRun:(VT100GridRun)run
    withForegroundColor:(NSColor *)fgColor
        backgroundColor:(NSColor *)bgColor;
- (BOOL)mutGetAndResetHasScrolled;
- (void)mutRedrawGrid;
- (void)mutSetMaxScrollbackLines:(unsigned int)lines;
- (PTYTextViewSynchronousUpdateState * _Nullable)mutSetUseSavedGridIfAvailable:(BOOL)useSavedGrid;
- (void)mutSetUnlimitedScrollback:(BOOL)newValue;
- (void)mutResetScrollbackOverflow;
- (void)mutSetCommandStartCoord:(VT100GridAbsCoord)coord;
- (void)mutInvalidateCommandStartCoord;
- (void)mutSetSaveToScrollbackInAlternateScreen:(BOOL)value;
- (void)mutSetTrackCursorLineMovement:(BOOL)trackCursorLineMovement;
- (void)mutSetAppendToScrollbackWithStatusBar:(BOOL)value;
- (void)mutSetShellIntegrationInstalled:(BOOL)shellIntegrationInstalled;
- (void)mutSetNormalization:(iTermUnicodeNormalization)value;
- (void)mutSetIntervalTreeObserver:(id<iTermIntervalTreeObserver>)intervalTreeObserver;
- (void)mutSetMutingAmount:(double)value;
- (void)mutSetDimmingAmount:(double)value;
- (void)mutSetDelegate:(id<VT100ScreenDelegate>)delegate;
- (iTermTemporaryDoubleBufferedGridController * _Nullable)mutableTemporaryDoubleBuffer;
- (void)mutUpdateConfig;
- (void)mutSetLastPromptLine:(long long)value;
- (void)mutSetShouldExpectPromptMarks:(BOOL)value;
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

@end

NS_ASSUME_NONNULL_END
