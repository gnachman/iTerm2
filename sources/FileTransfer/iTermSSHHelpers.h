//
//  iTermSSHHelpers.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/14/24.
//

#import <Foundation/Foundation.h>

@class NMSSHConfig;
@class iTermSSHConfigIncludeExpander;

NS_ASSUME_NONNULL_BEGIN

@interface iTermSSHHelpers : NSObject

+ (NSArray<NMSSHConfig *> *)configs;

// Loads each existing file with its Include directives expanded. User paths come first, then
// system paths, in the order given; missing or unparseable files are skipped. Relative Include
// paths resolve against ~/.ssh for user files and /etc/ssh for system files.
+ (NSArray<NMSSHConfig *> *)configsWithUserPaths:(NSArray<NSString *> *)userPaths
                                     systemPaths:(NSArray<NSString *> *)systemPaths
                                        expander:(iTermSSHConfigIncludeExpander *)expander;

@end

NS_ASSUME_NONNULL_END
