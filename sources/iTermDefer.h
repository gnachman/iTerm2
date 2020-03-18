//
//  iTermDefer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/15/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermDefer : NSObject

+ (instancetype)block:(void (^)(void))block;

@end

NS_ASSUME_NONNULL_END
