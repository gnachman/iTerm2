//
//  VT100Screen+Mutation.h
//  iTerm2Shared
//
//  Created by George Nachman on 12/9/21.
//

#import "VT100Screen.h"
#import "VT100Terminal.h"

@protocol iTermOrderedToken;

NS_ASSUME_NONNULL_BEGIN

@interface VT100Screen (Mutation)<VT100TerminalDelegate>

@property (nonatomic, readonly) VT100Grid *mutablePrimaryGrid;
@property (nonatomic, readonly) VT100Grid *mutableAltGrid;
@property (nonatomic, readonly) VT100Grid *mutableCurrentGrid;
@property (nonatomic, readonly) LineBuffer *mutableLineBuffer;

- (void)mutAddNote:(PTYNoteViewController *)note
           inRange:(VT100GridCoordRange)range;

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
- (void)mutAppendAsciiDataAtCursor:(AsciiData *)asciiData;
- (void)mutSetContentsFromLineBuffer:(LineBuffer *)lineBuffer;
- (void)mutSetHistory:(NSArray *)history;
- (void)mutSetAltScreen:(NSArray *)lines;
- (void)mutRestoreFromDictionary:(NSDictionary *)dictionary
        includeRestorationBanner:(BOOL)includeRestorationBanner
                   knownTriggers:(NSArray *)triggers
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
- (void)mutSetInitialTabStops;
- (void)mutHighlightRun:(VT100GridRun)run
    withForegroundColor:(NSColor *)fgColor
        backgroundColor:(NSColor *)bgColor;
- (void)mutLinkRun:(VT100GridRun)run
       withURLCode:(unsigned int)code;
- (BOOL)mutContinueFindResultsInContext:(FindContext *)context
                                toArray:(NSMutableArray *)results;
- (BOOL)mutGetAndResetHasScrolled;
- (void)mutRemoveObjectFromIntervalTree:(id<IntervalTreeObject>)obj;
- (void)mutDoBackspace;
- (void)mutAppendTabAtCursor:(BOOL)setBackgroundColors;
- (void)mutCursorLeft:(int)n;
- (void)mutCursorDown:(int)n andToStartOfLine:(BOOL)toStart;
- (void)mutCursorRight:(int)n;
- (void)mutCursorUp:(int)n andToStartOfLine:(BOOL)toStart;
- (void)mutCursorToX:(int)x Y:(int)y;
- (void)mutShowTestPattern;
- (void)mutSetScrollRegionTop:(int)top bottom:(int)bottom;
- (void)mutEraseInDisplayBeforeCursor:(BOOL)before afterCursor:(BOOL)after decProtect:(BOOL)dec;
- (void)mutEraseLineBeforeCursor:(BOOL)before afterCursor:(BOOL)after decProtect:(BOOL)dec;
- (void)mutCarriageReturn;
- (void)mutReverseIndex;
- (void)mutForwardIndex;
- (void)mutBackIndex;
- (void)mutResetPreservingPrompt:(BOOL)preservePrompt modifyContent:(BOOL)modifyContent;
- (void)mutSetLeftMargin:(int)scrollLeft rightMargin:(int)scrollRight;
- (void)mutSetWidth:(int)width preserveScreen:(BOOL)preserveScreen;
- (void)mutBackTab:(int)n;
- (void)mutCursorToX:(int)x;
- (void)mutCursorToY:(int)y;
- (void)mutAdvanceCursorPastLastColumn;
- (void)mutEraseCharactersAfterCursor:(int)j;
- (void)mutInsertEmptyCharsAtCursor:(int)n;
- (void)mutShiftLeft:(int)n;
- (void)mutShiftRight:(int)n;
- (void)mutInsertBlankLinesAfterCursor:(int)n;
- (void)mutDeleteCharactersAtCursor:(int)n;
- (void)mutDeleteLinesAtCursor:(int)n;
- (void)mutScrollDown:(int)n;
- (void)mutScrollUp:(int)n;
- (void)mutMarkWholeScreenDirty;
- (void)mutShowAltBuffer;
- (void)mutShowPrimaryBuffer;
- (void)mutEraseScreenAndRemoveSelection;
- (void)mutCommandWasAborted;
- (void)mutAppendScreenCharArrayAtCursor:(const screen_char_t *)buffer
                                  length:(int)len
                  externalAttributeIndex:(id<iTermExternalAttributeIndexReading>)externalAttributes;
- (void)mutInsertColumns:(int)n;
- (void)mutDeleteColumns:(int)n;
- (void)mutSetAttribute:(int)sgrAttribute inRect:(VT100GridRect)rect;
- (void)mutToggleAttribute:(int)sgrAttribute inRect:(VT100GridRect)rect;
- (void)mutCopyFrom:(VT100GridRect)source to:(VT100GridCoord)dest;
- (void)mutFillRectangle:(VT100GridRect)rect with:(screen_char_t)c externalAttributes:(iTermExternalAttribute * _Nullable)ea;
- (void)mutSelectiveEraseRectangle:(VT100GridRect)rect;
- (BOOL)mutSelectiveEraseRange:(VT100GridCoordRange)range eraseAttributes:(BOOL)eraseAttributes;
- (void)mutSetUseColumnScrollRegion:(BOOL)mode;
- (void)mutPopScrollbackLines:(int)linesPushed;
- (int)mutNumberOfLinesDroppedWhenEncodingContentsIncludingGrid:(BOOL)includeGrid
                                                        encoder:(id<iTermEncoderAdapter>)encoder
                                                 intervalOffset:(long long *)intervalOffsetPtr;
- (void)mutRedrawGrid;
- (void)mutSetSize:(VT100GridSize)proposedSize;
- (void)mutSetMaxScrollbackLines:(unsigned int)lines;
- (PTYTextViewSynchronousUpdateState * _Nullable)mutSetUseSavedGridIfAvailable:(BOOL)useSavedGrid;
- (void)mutRemoveNote:(PTYNoteViewController *)note;
- (void)mutSetTerminal:(VT100Terminal *)terminal;
- (void)mutStopTerminalReceivingFile;
- (void)mutFileReceiptEndedUnexpectedly;
- (void)mutSetWraparoundMode:(BOOL)newValue;
- (void)mutUpdateTerminalType;
- (void)mutSetInsert:(BOOL)newValue;
- (void)mutSetUnlimitedScrollback:(BOOL)newValue;
- (void)mutResetScrollbackOverflow;
- (void)mutSetCommandStartCoord:(VT100GridAbsCoord)coord;
- (void)mutSetCommandStartCoordWithoutSideEffects:(VT100GridAbsCoord)coord;
- (void)mutInvalidateCommandStartCoord;
- (void)mutInvalidateCommandStartCoordWithoutSideEffects;
- (id<iTermMark> _Nullable)mutAddMarkStartingAtAbsoluteLine:(long long)line
                                                    oneLine:(BOOL)oneLine
                                                    ofClass:(Class)markClass;
- (void)mutSaveFindContextPosition;
- (void)mutStoreLastPositionInLineBufferAsFindContextSavedPosition;
- (void)mutSetTabStopAtCursor;
- (void)mutRemoveAllTabStops;
- (void)mutRemoveTabStopAtCursor;
- (void)mutSetTabStops:(NSArray<NSNumber *> *)tabStops;
- (void)mutSetCharacterSet:(int)charset usesLineDrawingMode:(BOOL)lineDrawingMode;
- (void)mutSetSaveToScrollbackInAlternateScreen:(BOOL)value;
- (void)mutSetCursorVisible:(BOOL)visible;
- (void)mutPromptDidStartAt:(VT100GridAbsCoord)coord;
- (void)mutSetLastCommandOutputRange:(VT100GridAbsCoordRange)lastCommandOutputRange;
- (void)mutCommandDidStart;
- (void)mutCommandDidEnd;
- (BOOL)mutCommandDidEndAtAbsCoord:(VT100GridAbsCoord)coord;
- (void)mutRestoreInitialSize;
- (void)mutSetProtectedMode:(VT100TerminalProtectedMode)mode;
- (void)mutSaveFindContextAbsPos;
- (void)mutSetTrackCursorLineMovement:(BOOL)trackCursorLineMovement;
- (void)mutSetAppendToScrollbackWithStatusBar:(BOOL)value;
- (void)mutSetShellIntegrationInstalled:(BOOL)shellIntegrationInstalled;
- (void)mutSetNormalization:(iTermUnicodeNormalization)value;
- (void)mutSetIntervalTreeObserver:(id<iTermIntervalTreeObserver>)intervalTreeObserver;
- (void)mutSetLastCommandMark:(VT100ScreenMark *)mark;
- (void)mutSetColor:(NSColor *)color forKey:(int)key;
- (void)mutSetDimOnlyText:(BOOL)dimOnlyText;
- (void)mutSetDarkMode:(BOOL)darkMode;
- (void)mutSetUseSeparateColorsForLightAndDarkMode:(BOOL)value;
- (void)mutSetMinimumContrast:(float)value;
- (void)mutSetMutingAmount:(double)value;
- (void)mutSetDimmingAmount:(double)value;
- (void)mutSetDelegate:(id<VT100ScreenDelegate>)delegate;
- (void)mutSynchronizedUpdate:(BOOL)begin;
- (void)mutAppendNativeImageAtCursorWithName:(NSString *)name width:(int)width;
- (void)mutSetWorkingDirectory:(NSString *)workingDirectory
                        onLine:(int)line
                        pushed:(BOOL)pushed
                         token:(id<iTermOrderedToken> _Nullable)token;
- (void)mutSetRemoteHost:(NSString *)remoteHost;
- (void)mutCurrentDirectoryDidChangeTo:(NSString *)dir;

@end

NS_ASSUME_NONNULL_END
