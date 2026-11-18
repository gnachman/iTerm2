//
//  iTermSSHHelpers.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/14/24.
//

#import <Foundation/Foundation.h>

@class NMSSHConfigFile;
@class NMSSHConfigResolver;

NS_ASSUME_NONNULL_BEGIN

@interface iTermSSHHelpers : NSObject

// The ssh config files iTerm2 consults, in precedence order: iTerm2's own ssh_config,
// ~/.ssh/config, then the system files.
+ (NSArray<NMSSHConfigFile *> *)defaultConfigFiles;

// Resolves settings from defaultConfigFiles. Each lookup rereads the files, so edits take
// effect immediately.
+ (NMSSHConfigResolver *)resolver;

// Resolves settings from `files`, logging problems in them with DLog.
+ (NMSSHConfigResolver *)resolverForFiles:(NSArray<NMSSHConfigFile *> *)files NS_SWIFT_NAME(resolver(forFiles:));

@end

NS_ASSUME_NONNULL_END
