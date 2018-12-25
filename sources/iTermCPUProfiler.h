//
//  iTermCPUProfiler.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/24/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermCPUProfile : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (NSString *)stringTree;

@end

@interface iTermCPUProfiler : NSObject

+ (instancetype)sharedInstance;
- (void)startProfilingForDuration:(NSTimeInterval)duration
                       completion:(void (^)(iTermCPUProfile *))completion;

@end

NS_ASSUME_NONNULL_END
