//
//  iTermShellArguments.m
//  iTerm2
//
//  Created by George Nachman on 9/29/26.
//

#import "iTermShellArguments.h"

@implementation iTermShellArguments

// Shells verified to accept -l together with -i and -c.
+ (NSSet<NSString *> *)shellsAcceptingLoginFlag {
    static NSSet<NSString *> *shells;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shells = [NSSet setWithArray:@[ @"zsh", @"bash", @"sh", @"dash", @"fish", @"ksh" ]];
    });
    return shells;
}

+ (NSArray<NSString *> *)argumentsForShell:(NSString *)shell
                                      mode:(iTermShellRunMode)mode
                                scriptPath:(NSString *)scriptPath {
    switch (mode) {
        case iTermShellRunModeBare:
            return @[ @"-c", scriptPath ];
        case iTermShellRunModeInteractive:
            return @[ @"-i", @"-c", scriptPath ];
        case iTermShellRunModeLoginInteractive:
            if ([[self shellsAcceptingLoginFlag] containsObject:shell.lastPathComponent]) {
                return @[ @"-l", @"-i", @"-c", scriptPath ];
            }
            return @[ @"-i", @"-c", scriptPath ];
    }
    return @[ @"-c", scriptPath ];
}

@end
