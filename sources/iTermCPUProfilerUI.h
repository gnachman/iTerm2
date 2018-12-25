//
//  iTermCPUProfilerUI.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/24/18.
//

#import <Foundation/Foundation.h>
#import "iTermCPUProfiler.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermCPUProfilerUI : NSObject

+ (void)createProfileWithCompletion:(nonnull void (^)(iTermCPUProfile * _Nonnull))completion;

@end

NS_ASSUME_NONNULL_END
