//
//  iTermWeakProxy.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/17/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermWeakProxy<ObjectType> : NSProxy

@property (nullable, weak) ObjectType object;

- (instancetype)initWithObject:(ObjectType)object;

@end

NS_ASSUME_NONNULL_END
