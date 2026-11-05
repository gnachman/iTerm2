//
//  iTermTemporaryDoubleBufferedGridController+Testing.h
//  iTerm2
//
//  Lets tests decide when a saved grid expires instead of racing its timer.
//

#import "iTermTemporaryDoubleBufferedGridController.h"

// The base header only declares the class in C++.
#if !defined(__cplusplus)

NS_ASSUME_NONNULL_BEGIN

@interface iTermTemporaryDoubleBufferedGridController (Testing)

// When YES, saving a grid doesn't start the expiration timer. The saved grid expires only when
// -fireExpirationTimerForTesting is called.
@property(nonatomic) BOOL manualExpirationForTesting;

// Whether the expiration timer is running, or would be if expiration weren't manual.
@property(nonatomic, readonly) BOOL expirationPendingForTesting;

// Expires the saved grid as the timer would. Expiration must be pending.
- (void)fireExpirationTimerForTesting;

@end

NS_ASSUME_NONNULL_END

#endif  // !__cplusplus
