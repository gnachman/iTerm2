//
//  iTermProcessCache.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/18/18.
//

#import <Foundation/Foundation.h>

#import "iTerm2SharedARC-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@protocol ProcessInfoProvider;
@class iTermProcessCollection;

@interface iTermProcessCache : NSObject<ProcessInfoProvider>

+ (instancetype)sharedInstance;
+ (iTermProcessCollection *)newProcessCollection;

@end

NS_ASSUME_NONNULL_END
