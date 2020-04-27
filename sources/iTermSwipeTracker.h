//
//  iTermSwipeTracker.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/26/20.
//

#import <Cocoa/Cocoa.h>

#import "iTermSwipeHandler.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermSwipeTracker;

@interface iTermSwipeState: NSObject
@property (nonatomic, readonly) id userInfo;
@property (nonatomic, strong, readonly) id<iTermSwipeHandler> swipeHandler;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithSwipeHandler:(id<iTermSwipeHandler>)handler NS_DESIGNATED_INITIALIZER;
@end

@protocol iTermSwipeTrackerDelegate<NSObject>
// Delta gives distance moved.
- (iTermSwipeState *)swipeTrackerWillBeginNewSwipe:(iTermSwipeTracker *)tracker
                                             delta:(CGFloat)delta;
@end

@interface iTermSwipeTracker : NSObject
@property (nonatomic, weak) id<iTermSwipeTrackerDelegate> delegate;

- (BOOL)handleEvent:(NSEvent *)event;

@end

NS_ASSUME_NONNULL_END
