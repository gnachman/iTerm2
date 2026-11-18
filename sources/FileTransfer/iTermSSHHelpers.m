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
#import <NMSSH/NMSSH-Swift.h>

@implementation iTermSSHHelpers

+ (NSArray<NMSSHConfigFile *> *)defaultConfigFiles {
    NSString *appSupport = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSMutableArray<NMSSHConfigFile *> *files = [NSMutableArray array];
    NSString *iTermConfig = [appSupport stringByAppendingPathComponent:@"ssh_config"];
    if (iTermConfig.length) {
        [files addObject:[[NMSSHConfigFile alloc] initWithPath:iTermConfig isUserConfig:YES]];
    }
    NSString *userConfig = [@"~/.ssh/config" stringByExpandingTildeInPath];
    if (userConfig.length) {
        [files addObject:[[NMSSHConfigFile alloc] initWithPath:userConfig isUserConfig:YES]];
    }
    [files addObject:[[NMSSHConfigFile alloc] initWithPath:@"/etc/ssh/ssh_config" isUserConfig:NO]];
    [files addObject:[[NMSSHConfigFile alloc] initWithPath:@"/etc/ssh_config" isUserConfig:NO]];
    return files;
}

+ (NMSSHConfigResolver *)resolver {
    return [self resolverForFiles:[self defaultConfigFiles]];
}

+ (NMSSHConfigResolver *)resolverForFiles:(NSArray<NMSSHConfigFile *> *)files {
    NMSSHConfigResolver *resolver = [[NMSSHConfigResolver alloc] initWithFiles:files];
    resolver.logHandler = ^(NSString *message) {
        DLog(@"ssh config: %@", message);
    };
    return resolver;
}

@end
