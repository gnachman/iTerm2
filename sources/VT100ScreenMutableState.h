//
//  VT100ScreenMutableState.h
//  iTerm2
//
//  Created by George Nachman on 12/28/21.
//

#import <Foundation/Foundation.h>
#import "VT100ScreenState.h"

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

#pragma mark - Shell Integration

- (void)assignCurrentCommandEndDate;

@end

NS_ASSUME_NONNULL_END
