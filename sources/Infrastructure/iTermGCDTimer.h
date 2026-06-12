//
//  iTermGCDTimer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/29/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermTimer<NSObject>
- (void)invalidate;
- (NSDate *)fireDate;
@end


@interface NSTimer (GCD)<iTermTimer>
@end

// Like NSTimer but implemented with GCD so you don't have to burn brain cells thinking about
// runloops. Holds a weak reference to target.
@interface iTermGCDTimer: NSObject<iTermTimer>
@property (nonatomic, readonly) NSTimeInterval actualInterval;

- (instancetype)initWithInterval:(NSTimeInterval)interval
                           queue:(dispatch_queue_t)queue
                          target:(id)target // WEAK!
                        selector:(SEL)selector NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithInterval:(NSTimeInterval)interval
                          target:(id)target // WEAK!
                        selector:(SEL)selector;

+ (instancetype)scheduledWeakTimerWithTimeInterval:(NSTimeInterval)ti
                                            target:(id)aTarget
                                          selector:(SEL)aSelector
                                             queue:(dispatch_queue_t)queue;

- (instancetype)init NS_UNAVAILABLE;
- (void)invalidate;
@end

NS_ASSUME_NONNULL_END
