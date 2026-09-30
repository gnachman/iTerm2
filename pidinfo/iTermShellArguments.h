//
//  iTermShellArguments.h
//  iTerm2
//
//  Created by George Nachman on 9/29/26.
//
//  Shared by the pidinfo XPC service and the app so the argument choice can be
//  unit-tested from ModernTests.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// How the user's shell is started when running a script to read its environment.
typedef NS_ENUM(NSInteger, iTermShellRunMode) {
    // `-c`: sources almost nothing (zsh reads only .zshenv, bash nothing). Fast.
    // Right when the exported environment suffices (SSH_AUTH_SOCK).
    iTermShellRunModeBare,

    // `-i -c`: the interactive rc files run (.zshrc, .bashrc, config.fish,
    // .tcshrc). Right for variables set there, such as CLAUDE_CONFIG_DIR.
    iTermShellRunModeInteractive,

    // `-l -i -c` where the shell accepts it: the profile files run as well, so
    // the result matches a terminal session. zsh reads .zprofile, .zshrc and
    // .zlogin; bash reads .bash_profile (or .bash_login or .profile) and only
    // what that sources, since a login bash does not read .bashrc on its own.
    // Right for PATH, which is usually set in the profile files. Shells not
    // known to accept -l with other flags (tcsh and csh reject it with a usage
    // error; elvish has no -l) get the interactive shape instead.
    iTermShellRunModeLoginInteractive,
};

// A class rather than a C function so the app’s dead-code stripping keeps it
// for the unit tests, which are its only client on the app side.
@interface iTermShellArguments : NSObject

// The arguments to run `scriptPath` with `shell` in `mode`.
+ (NSArray<NSString *> *)argumentsForShell:(NSString *)shell
                                      mode:(iTermShellRunMode)mode
                                scriptPath:(NSString *)scriptPath;

@end

NS_ASSUME_NONNULL_END
