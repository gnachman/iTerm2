//
//  iTermResult.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/14/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermResult<T> : NSObject
+ (instancetype)withObject:(T)object;
+ (instancetype)withError:(NSError *)error;
- (void)handleObject:(void (^)(T object))object
               error:(void (^)(NSError *error))error;
@end

NS_ASSUME_NONNULL_END
