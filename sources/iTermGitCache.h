//
//  iTermGitCache.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import <Foundation/Foundation.h>
#import "iTermGitState.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermGitCache : NSObject

- (void)setState:(iTermGitState *)state forPath:(NSString *)path ttl:(NSTimeInterval)ttl;
- (iTermGitState *)stateForPath:(NSString *)path;
- (void)removeStateForPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
