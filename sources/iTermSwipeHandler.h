//
//  iTermSwipeHandler.h
//  iTerm2
//
//  Created by George Nachman on 4/4/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Post this with the identifier as the object to cancel a swipe.
extern NSString *const iTermSwipeHandlerCancelSwipe;

@protocol iTermSwipeHandler<NSObject>

typedef struct {
    NSInteger count;
    NSInteger currentIndex;
    CGFloat width;
} iTermSwipeHandlerParameters;

- (iTermSwipeHandlerParameters)swipeHandlerParameters;
- (id)swipeHandlerBeginSessionAtOffset:(CGFloat)offset identifier:(id)identifier;
- (void)swipeHandlerSetOffset:(CGFloat)offset forSession:(id)session;
- (void)swipeHandlerEndSession:(id)session atIndex:(NSInteger)index;
- (BOOL)swipeHandlerShouldBeginNewSwipe;

@end

NS_ASSUME_NONNULL_END
