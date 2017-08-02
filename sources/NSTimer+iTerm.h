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

+ (instancetype)weakTimerWithTimeInterval:(NSTimeInterval)interval
                                   target:(id)target
                                 selector:(SEL)selector
                                 userInfo:(nullable id)userInfo
                                  repeats:(BOOL)repeats;

+ (instancetype)scheduledWeakTimerWithTimeInterval:(NSTimeInterval)ti
                                            target:(id)aTarget
                                          selector:(SEL)aSelector
                                          userInfo:(nullable id)userInfo
                                           repeats:(BOOL)yesOrNo;

+ (instancetype)it_scheduledTimerWithTimeInterval:(NSTimeInterval)timeInterval
                                          repeats:(BOOL)repeats
                                            block:(void (^_Nonnull)(NSTimer * _Nonnull timer))block;

+ (instancetype)it_weakTimerWithTimeInterval:(NSTimeInterval)timeInterval repeats:(BOOL)repeats target:(id)target selector:(SEL)selector;

@end

NS_ASSUME_NONNULL_END
