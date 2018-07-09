//
//  iTermStatusBarSpringComponent.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import "iTermStatusBarBaseComponent.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermStatusBarSpringComponent : iTermStatusBarBaseComponent

+ (instancetype)springComponentWithCompressionResistance:(double)compressionResistance;

@end

NS_ASSUME_NONNULL_END
