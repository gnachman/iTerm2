//
//  iTermProcessCache.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/18/18.
//

#import <Foundation/Foundation.h>

#import "iTerm2SharedARC-Swift.h"
#import "iTermProcessCollection.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermProcessCache : NSObject<ProcessInfoProvider>

+ (instancetype)sharedInstance;

@end

NS_ASSUME_NONNULL_END
