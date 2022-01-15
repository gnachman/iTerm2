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

@interface VT100Screen (Mutation)<iTermMarkDelegate, VT100TerminalDelegate>

@property (nonatomic, readonly) VT100Grid *mutablePrimaryGrid;
@property (nonatomic, readonly) VT100Grid *mutableAltGrid;
@property (nonatomic, readonly) LineBuffer *mutableLineBuffer;

- (void)mutAddNote:(PTYAnnotation *)note
           inRange:(VT100GridCoordRange)range
             focus:(BOOL)focus;
- (void)mutRemoveAnnotation:(PTYAnnotation *)annotation;

- (void)mutClearBuffer;
- (void)mutClearBufferSavingPrompt:(BOOL)savePrompt;
- (void)mutClearScrollbackBuffer;
- (void)mutResetTimestamps;
- (void)mutRemoveLastLine;
- (void)mutClearFromAbsoluteLineToEnd:(long long)absLine;
- (void)mutAppendStringAtCursor:(NSString *)string;
- (void)mutAppendScreenChars:(const screen_char_t *)line
                   length:(int)length
   externalAttributeIndex:(id<iTermExternalAttributeIndexReading>)externalAttributeIndex
                continuation:(screen_char_t)continuation;
- (void)mutSetContentsFromLineBuffer:(LineBuffer *)lineBuffer;
- (void)mutSetHistory:(NSArray *)history;
- (void)mutSetAltScreen:(NSArray *)lines;
- (void)mutRestoreFromDictionary:(NSDictionary *)dictionary
        includeRestorationBanner:(BOOL)includeRestorationBanner
                      reattached:(BOOL)reattached;
- (void)mutSetTmuxState:(NSDictionary *)state;
- (void)mutCrlf;
- (void)mutLinefeed;
- (void)mutSetFromFrame:(screen_char_t*)s
                    len:(int)len
               metadata:(NSArray<NSArray *> *)metadataArrays
                   info:(DVRFrameInfo)info;
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
- (int)mutNumberOfLinesDroppedWhenEncodingContentsIncludingGrid:(BOOL)includeGrid
                                                        encoder:(id<iTermEncoderAdapter>)encoder
                                                 intervalOffset:(long long *)intervalOffsetPtr;
- (void)mutRedrawGrid;
- (void)mutSetMaxScrollbackLines:(unsigned int)lines;
- (PTYTextViewSynchronousUpdateState * _Nullable)mutSetUseSavedGridIfAvailable:(BOOL)useSavedGrid;
- (void)mutSetUnlimitedScrollback:(BOOL)newValue;
- (void)mutResetScrollbackOverflow;
- (void)mutSetCommandStartCoord:(VT100GridAbsCoord)coord;
- (void)mutInvalidateCommandStartCoord;
- (id<iTermMark> _Nullable)mutAddMarkStartingAtAbsoluteLine:(long long)line
                                                    oneLine:(BOOL)oneLine
                                                    ofClass:(Class)markClass;
- (void)mutSaveFindContextPosition;
- (void)mutStoreLastPositionInLineBufferAsFindContextSavedPosition;
- (void)mutRemoveAllTabStops;
- (void)mutSetSaveToScrollbackInAlternateScreen:(BOOL)value;
- (void)mutPromptDidStartAt:(VT100GridAbsCoord)coord;
- (void)mutSetLastCommandOutputRange:(VT100GridAbsCoordRange)lastCommandOutputRange;
- (void)mutRestoreInitialSize;
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
- (void)mutSetWorkingDirectory:(NSString *)workingDirectory
                     onAbsLine:(long long)line
                        pushed:(BOOL)pushed
                         token:(id<iTermOrderedToken> _Nullable)token;
- (void)mutReloadMarkCache;
- (iTermTemporaryDoubleBufferedGridController * _Nullable)mutableTemporaryDoubleBuffer;
- (void)mutUpdateConfig;
- (void)mutSetFakePromptDetectedAbsLine:(long long)value;
- (void)mutUserDidPressReturn;
- (void)mutSetLastPromptLine:(long long)value;
- (id<iTermMark>)mutAddMarkOnLine:(int)line ofClass:(Class)markClass;
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
- (PTYAnnotation *)mutAddNoteWithText:(NSString *)text inAbsoluteRange:(VT100GridAbsCoordRange)absRange;
- (void)mutInjectData:(NSData *)data;
- (void)mutPerformPeriodicTriggerCheck;
- (void)mutForceCheckTriggers;
- (void)mutSetExited:(BOOL)exited;
- (void)mutLoadInitialColorTable;

@end

NS_ASSUME_NONNULL_END
