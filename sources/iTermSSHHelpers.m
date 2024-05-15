//
//  iTermSSHHelpers.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/14/24.
//

#import "iTermSSHHelpers.h"

#import "DebugLogging.h"
#import "NSFileManager+iTerm.h"

#import <NMSSH/NMSSH.h>

@implementation iTermSSHHelpers

+ (NSArray<NMSSHConfig *> *)configs {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *appSupport = [fileManager applicationSupportDirectory];
    NSArray *paths = @[ [appSupport stringByAppendingPathComponent:@"ssh_config"] ?: @"",
                        [@"~/.ssh/config" stringByExpandingTildeInPath] ?: @"",
                        @"/etc/ssh/ssh_config",
                        @"/etc/ssh_config" ];
    NSMutableArray *configs = [NSMutableArray array];
    for (NSString *path in paths) {
        if (path.length == 0) {
            DLog(@"Zero length path in configs paths %@", paths);
            continue;
        }
        if ([fileManager fileExistsAtPath:path]) {
            NMSSHConfig *config = [NMSSHConfig configFromFile:path];
            if (config) {
                [configs addObject:config];
            } else {
                XLog(@"Could not parse config file at %@", path);
            }
        }
    }
    return configs;
}

@end
