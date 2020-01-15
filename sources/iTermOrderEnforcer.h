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

@interface iTermOrderEnforcer : NSObject

- (id<iTermOrderedToken>)newToken;

@end

NS_ASSUME_NONNULL_END
