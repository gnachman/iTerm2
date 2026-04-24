//
//  iTermSSHHelpers.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/14/24.
//

#import <Foundation/Foundation.h>

@class NMSSHConfig;

NS_ASSUME_NONNULL_BEGIN

@interface iTermSSHHelpers : NSObject

+ (NSArray<NMSSHConfig *> *)configs;

@end

NS_ASSUME_NONNULL_END
