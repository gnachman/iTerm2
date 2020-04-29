//
//  iTermSwipeHandler.h
//  iTerm2
//
//  Created by George Nachman on 4/4/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermSwipeHandler<NSObject>

typedef struct {
    NSUInteger count;
    NSUInteger currentIndex;
    CGFloat width;
} iTermSwipeHandlerParameters;

- (iTermSwipeHandlerParameters)swipeHandlerParameters;
- (id)swipeHandlerBeginSessionAtOffset:(CGFloat)offset;
- (void)swipeHandlerSetOffset:(CGFloat)offset forSession:(id)session;
- (void)swipeHandlerEndSession:(id)session atIndex:(NSInteger)index;

@end

NS_ASSUME_NONNULL_END
