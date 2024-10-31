//
//  iTermBijection.h
//  iTerm2
//
//  Created by George Nachman on 11/1/24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermBijection<__covariant Left, __covariant Right>: NSObject

- (void)link:(Left)left to:(Right)right;
- (Right)objectForLeft:(Left)left;
- (Left)objectForRight:(Right)right;

@end

NS_ASSUME_NONNULL_END

