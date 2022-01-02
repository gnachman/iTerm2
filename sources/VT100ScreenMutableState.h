//
//  VT100ScreenMutableState.h
//  iTerm2
//
//  Created by George Nachman on 12/28/21.
//

#import <Foundation/Foundation.h>
#import "VT100ScreenState.h"

@class Trigger;
@protocol VT100ScreenConfiguration;
@protocol iTermOrderedToken;
@class iTermSlownessDetector;

NS_ASSUME_NONNULL_BEGIN

@protocol VT100ScreenSideEffectPerforming<NSObject>
- (id<VT100ScreenDelegate>)sideEffectPerformingScreenDelegate;
- (id<iTermIntervalTreeObserver>)sideEffectPerformingIntervalTreeObserver;
@end

@interface VT100ScreenMutableState: VT100ScreenState<VT100ScreenMutableState, NSCopying>
@property (nonatomic, strong, readwrite) iTermOrderEnforcer *currentDirectoryDidChangeOrderEnforcer;
@property (nullable, nonatomic, strong) VT100InlineImageHelper *inlineImageHelper;
@property (nonatomic, strong, readwrite) iTermOrderEnforcer *setWorkingDirectoryOrderEnforcer;
@property (atomic, weak) id<VT100ScreenSideEffectPerforming> sideEffectPerformer;
@property (nonatomic, copy) id<VT100ScreenConfiguration> config;

// Mutations made here on the main thread are copied into the trigger evaluator's expect.
@property (nonatomic, readonly) iTermExpect *expectSource;

- (instancetype)initWithSideEffectPerformer:(id<VT100ScreenSideEffectPerforming>)performer NS_DESIGNATED_INITIALIZER;
- (id<VT100ScreenState>)copy;

#pragma mark - Internal

// This is how mutation code schedules work to be done on the main thread later. In particular, this
// is the only way for it to call delegate methods. It will be performed asynchronously at some
// later time.
- (void)addSideEffect:(void (^)(id<VT100ScreenDelegate> delegate))sideEffect;
- (void)addIntervalTreeSideEffect:(void (^)(id<iTermIntervalTreeObserver> observer))sideEffect;

- (void)setNeedsRedraw;

#pragma mark - Scrollback

- (void)incrementOverflowBy:(int)overflowCount;

#pragma mark - Terminal Fundamentals

- (void)appendLineFeed;
- (void)appendCarriageReturnLineFeed;

#pragma mark - URLs

- (void)linkTextInRange:(NSRange)range
basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                URLCode:(unsigned int)code;

- (void)linkRun:(VT100GridRun)run
    withURLCode:(unsigned int)code;

#pragma mark - Highlighting

- (void)highlightTextInRange:(NSRange)range
   basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                      colors:(NSDictionary *)colors;
- (void)highlightRun:(VT100GridRun)run
 withForegroundColor:(NSColor *)fgColor
     backgroundColor:(NSColor *)bgColor;

#pragma mark - Interval Tree

- (id<iTermMark>)addMarkStartingAtAbsoluteLine:(long long)line
                                       oneLine:(BOOL)oneLine
                                       ofClass:(Class)markClass;

#pragma mark - Shell Integration

- (void)assignCurrentCommandEndDate;

// This is like addMarkStartingAtAbsoluteLine:oneLine:ofClass: but it notifies the delegate of a new mark.
- (id<iTermMark>)addMarkOnLine:(int)line ofClass:(Class)markClass;

- (void)didUpdatePromptLocation;

- (void)setPromptStartLine:(int)line;

// This is like setPromptStartLine: but with lots of side effects that are desirable for the
// regular shell integration flow.
- (void)promptDidStartAt:(VT100GridAbsCoord)coord;

// Update the commandRange in the current prompt's mark, if present. Asynchronously 
- (void)commandRangeDidChange;

- (void)saveCursorLine;

- (void)setReturnCodeOfLastCommand:(int)returnCode;

- (void)setCoordinateOfCommandStart:(VT100GridAbsCoord)coord;

- (void)currentDirectoryDidChangeTo:(NSString *)dir;

- (void)setWorkingDirectory:(NSString *)workingDirectory
                     onLine:(int)line
                     pushed:(BOOL)pushed
                      token:(id<iTermOrderedToken>)token;

- (void)setRemoteHostFromString:(NSString *)remoteHost;

- (void)setHost:(NSString *)host user:(NSString *)user;

- (VT100RemoteHost *)setRemoteHost:(NSString *)host user:(NSString *)user onLine:(int)line;

#pragma mark - Annotations

- (void)removeAnnotation:(PTYAnnotation *)annotation;

- (void)addAnnotation:(PTYAnnotation *)annotation
              inRange:(VT100GridCoordRange)range
        andStealFocus:(BOOL)focus;

#pragma mark - Triggers

- (NSArray<Trigger *> *)triggers;

- (void)setTriggerParametersUseInterpolatedStrings:(BOOL)value;

// This is in the triggers section because it is currently only used to decide if triggers should
// measure their performance penalty and synchronization with PTYSession is not important.
- (void)setExited:(BOOL)exited;

- (void)loadTriggersFromProfileArray:(NSArray *)array
              useInterpolatedStrings:(BOOL)useInterpolatedStrings;

#pragma mark - Interthread Synchronization

- (void)willUpdateDisplay;

#pragma mark - Temporary

- (iTermSlownessDetector *)slownessDetector;

@end

NS_ASSUME_NONNULL_END
