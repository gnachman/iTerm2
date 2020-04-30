//
//  iTermSwipeState.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/29/20.
//

#import <Foundation/Foundation.h>

#import "iTermScrollWheelStateMachine.h"
#import "iTermSwipeHandler.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermSwipeState: NSObject
@property (nonatomic, readonly) id userInfo;
@property (nonatomic, strong, readonly) id<iTermSwipeHandler> swipeHandler;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithSwipeHandler:(id<iTermSwipeHandler>)handler NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
