//
//  VT100ScreenMutableState.h
//  iTerm2
//
//  Created by George Nachman on 12/28/21.
//

#import <Foundation/Foundation.h>
#import "VT100ScreenState.h"

@protocol VT100ScreenConfiguration;
@protocol iTermOrderedToken;

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

- (void)setWorkingDirectory:(NSString * _Nullable)workingDirectory
                  onAbsLine:(long long)absLine
                     pushed:(BOOL)pushed
                      token:(id<iTermOrderedToken> _Nullable)token;

- (void)currentDirectoryDidChangeTo:(NSString *)dir;

- (void)setRemoteHostFromString:(NSString *)remoteHost;

- (void)setHost:(NSString * _Nullable)host user:(NSString * _Nullable)user;

- (void)setCoordinateOfCommandStart:(VT100GridAbsCoord)coord;

#pragma mark - Annotations

- (void)removeAnnotation:(PTYAnnotation *)annotation;

- (void)addAnnotation:(PTYAnnotation *)annotation
              inRange:(VT100GridCoordRange)range
                focus:(BOOL)focus;

#pragma mark - URLs

- (void)linkRun:(VT100GridRun)run
    withURLCode:(unsigned int)code;

#pragma mark - Highlighting

- (void)highlightRun:(VT100GridRun)run
 withForegroundColor:(NSColor *)fgColor
     backgroundColor:(NSColor *)bgColor;

@end

NS_ASSUME_NONNULL_END
