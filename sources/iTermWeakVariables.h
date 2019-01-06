//
//  iTermWeakVariables.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/5/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermVariables;

@interface iTermWeakVariables : NSObject<NSCopying, NSSecureCoding>
@property (nonatomic, nullable, weak, readonly) iTermVariables *variables;

- (instancetype)initWithVariables:(iTermVariables *)variables NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
