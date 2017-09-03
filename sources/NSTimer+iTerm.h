//
//  NSTimer+iTerm.h
//  iTerm2
//
//  Created by George Nachman on 8/1/17.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSTimer (iTerm)

// Careful, this one isn't scheduled. You have to add it to the runloop yourself.
+ (instancetype)weakTimerWithTimeInterval:(NSTimeInterval)interval
                                   target:(id)target
                                 selector:(SEL)selector
                                 userInfo:(nullable id)userInfo
                                  repeats:(BOOL)repeats;

// Like the similarly named NSTimer method but does not retain aTarget.
+ (instancetype)scheduledWeakTimerWithTimeInterval:(NSTimeInterval)ti
                                            target:(id)aTarget
                                          selector:(SEL)aSelector
                                          userInfo:(nullable id)userInfo
                                           repeats:(BOOL)yesOrNo;

// Block based API since the OS's isn't available until 10.12
+ (instancetype)it_scheduledTimerWithTimeInterval:(NSTimeInterval)timeInterval
                                          repeats:(BOOL)repeats
                                            block:(void (^_Nonnull)(NSTimer * _Nonnull timer))block;

@end

NS_ASSUME_NONNULL_END
