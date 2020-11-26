//
//  iTermSwipeTracker.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/26/20.
//

#import <Cocoa/Cocoa.h>

#import "iTermSwipeHandler.h"
#import "iTermSwipeState.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermSwipeTracker;

@protocol iTermSwipeTrackerDelegate<NSObject>
// Delta gives distance moved.
- (iTermSwipeState *)swipeTrackerWillBeginNewSwipe:(iTermSwipeTracker *)tracker;
- (BOOL)swipeTrackerShouldBeginNewSwipe:(iTermSwipeTracker *)tracker;
@end

@interface iTermSwipeTracker : NSObject
@property (nonatomic, weak) id<iTermSwipeTrackerDelegate> delegate;

- (BOOL)handleEvent:(NSEvent *)event;

@end

NS_ASSUME_NONNULL_END
