//
//  iTermSSHHelpers.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/14/24.
//

#import "iTermSSHHelpers.h"

#import "DebugLogging.h"
#import "NSFileManager+iTerm.h"
#import "iTerm2SharedARC-Swift.h"

#import <NMSSH/NMSSH.h>

@implementation iTermSSHHelpers

+ (NSArray<NMSSHConfig *> *)configs {
    NSString *appSupport = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSArray<NSString *> *userPaths = @[ [appSupport stringByAppendingPathComponent:@"ssh_config"] ?: @"",
                                        [@"~/.ssh/config" stringByExpandingTildeInPath] ?: @"" ];
    NSArray<NSString *> *systemPaths = @[ @"/etc/ssh/ssh_config",
                                          @"/etc/ssh_config" ];
    return [self configsWithUserPaths:userPaths
                          systemPaths:systemPaths
                             expander:[[iTermSSHConfigIncludeExpander alloc] init]];
}

+ (NSArray<NMSSHConfig *> *)configsWithUserPaths:(NSArray<NSString *> *)userPaths
                                     systemPaths:(NSArray<NSString *> *)systemPaths
                                        expander:(iTermSSHConfigIncludeExpander *)expander {
    NSMutableArray<NMSSHConfig *> *configs = [NSMutableArray array];
    void (^load)(NSString *, BOOL) = ^(NSString *path, BOOL isUserConfig) {
        if (path.length == 0) {
            DLog(@"Zero length path in configs paths %@ %@", userPaths, systemPaths);
            return;
        }
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return;
        }
        NSString *contents = [expander expandedContentsOfFile:path isUserConfig:isUserConfig];
        NMSSHConfig *config = contents ? [[NMSSHConfig alloc] initWithString:contents] : nil;
        if (config) {
            [configs addObject:config];
        } else {
            XLog(@"Could not parse config file at %@", path);
        }
    };
    for (NSString *path in userPaths) {
        load(path, YES);
    }
    for (NSString *path in systemPaths) {
        load(path, NO);
    }
    return configs;
}

@end
