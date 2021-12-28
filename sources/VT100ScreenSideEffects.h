//
//  VT100ScreenSideEffects.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/21/21.
//

#import <Foundation/Foundation.h>

@protocol VT100ScreenDelegate;
@protocol iTermIntervalTreeObserver;

typedef void (^VT100ScreenSideEffectBlock)(id<VT100ScreenDelegate> delegate);
typedef void (^VT100ScreenIntervalTreeSideEffectBlock)(id<iTermIntervalTreeObserver> observer);

NS_ASSUME_NONNULL_BEGIN

@protocol VT100ScreenSideEffectQueueReading<NSObject>
- (void)executeWithDelegate:(id<VT100ScreenDelegate>)delegate
       intervalTreeObserver:(id<iTermIntervalTreeObserver>)observer;
@end

@interface VT100ScreenSideEffectQueue: NSObject<NSCopying, VT100ScreenSideEffectQueueReading>

- (void)addSideEffect:(VT100ScreenSideEffectBlock)sideEffect;
- (void)addIntervalTreeSideEffect:(VT100ScreenIntervalTreeSideEffectBlock)sideEffect;

@end

NS_ASSUME_NONNULL_END
