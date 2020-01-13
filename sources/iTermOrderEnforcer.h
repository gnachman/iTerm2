//
//  iTermOrderEnforcer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/14/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermOrderedToken<NSObject>
- (BOOL)commit;
- (BOOL)peek;
@end

// Helps you enforce an order of operations. Create tokens in the order you
// want operations to complete. When your asynchronous operation completes,
// call commit. If no future tokens have already been committed, it will return
// YES and you'll know that token corresponds to the most recent completed
// async operation.
@interface iTermOrderEnforcer : NSObject

- (id<iTermOrderedToken>)newToken;

@end

NS_ASSUME_NONNULL_END
