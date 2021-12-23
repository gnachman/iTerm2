//
//  VT100ScreenSideEffects.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/21/21.
//

#import <Foundation/Foundation.h>

@protocol VT100ScreenDelegate;

typedef void (^VT100ScreenSideEffectBlock)(id<VT100ScreenDelegate> delegate);

NS_ASSUME_NONNULL_BEGIN

@protocol VT100ScreenSideEffectQueueReading<NSObject>
- (void)executeWithDelegate:(id<VT100ScreenDelegate>)delegate;
@end

@interface VT100ScreenSideEffectQueue: NSObject<NSCopying, VT100ScreenSideEffectQueueReading>

- (void)addSideEffect:(VT100ScreenSideEffectBlock)sideEffect;

@end

NS_ASSUME_NONNULL_END
