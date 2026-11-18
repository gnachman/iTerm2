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

// Parses the ssh config files iTerm2 consults, in precedence order.
+ (NSArray<NMSSHConfig *> *)configs;

// The files `configs` reads, in precedence order.
+ (NSArray<NSString *> *)defaultConfigPaths;

// Parses each file in `paths` that exists, skipping any that can't be read.
+ (NSArray<NMSSHConfig *> *)configsAtPaths:(NSArray<NSString *> *)paths;

@end

NS_ASSUME_NONNULL_END
