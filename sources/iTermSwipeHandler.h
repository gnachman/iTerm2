//
//  iTermSwipeHandler.h
//  iTerm2
//
//  Created by George Nachman on 4/4/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermSwipeHandler<NSObject>
- (nullable id)didBeginSwipeWithAmount:(CGFloat)amount;
- (BOOL)canSwipeBack;
- (BOOL)canSwipeForward;
- (void)didEndSwipe:(id)context amount:(CGFloat)amount;
- (void)didCancelSwipe:(id)context;
- (void)didCompleteSwipe:(id)context direction:(int)direction;
- (void)didUpdateSwipe:(id)context amount:(CGFloat)amount;
@end

NS_ASSUME_NONNULL_END
