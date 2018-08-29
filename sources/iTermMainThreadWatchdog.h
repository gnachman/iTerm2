//
//  iTermMainThreadWatchdog.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/28/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermMainThreadWatchdog : NSObject

+ (instancetype)sharedInstance;
- (void)schedule;

@end

NS_ASSUME_NONNULL_END
