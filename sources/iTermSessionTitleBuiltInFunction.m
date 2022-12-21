//
//  iTermSessionTitleBuiltInFunction.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/19/18.
//

#import "iTermSessionTitleBuiltInFunction.h"

#import "DebugLogging.h"
#import "iTermProfilePreferences.h"
#import "iTermVariableScope.h"
#import "NSHost+iTerm.h"
#import "PTYSession.h"

// Arguments to title BIF
static NSString *const iTermSessionTitleArgName = @"name";
static NSString *const iTermSessionTitleArgProfile = @"profile";
static NSString *const iTermSessionTitleArgJob = @"job";
static NSString *const iTermSessionTitleArgCommandLine = @"commandLine";
static NSString *const iTermSessionTitleArgPath = @"path";
static NSString *const iTermSessionTitleArgTTY = @"tty";
static NSString *const iTermSessionTitleArgUser = @"username";
static NSString *const iTermSessionTitleArgHost = @"hostname";
static NSString *const iTermSessionTitleArgHomeDirectory = @"homeDirectory";
static NSString *const iTermSessionTitleArgTmuxPane = @"tmuxPane";
static NSString *const iTermSessionTitleArgTmuxRole = @"tmuxRole";
static NSString *const iTermSessionTitleArgTmuxClientName = @"tmuxClientName";
static NSString *const iTermSessionTitleArgIconName = @"iconName";
static NSString *const iTermSessionTitleArgWindowName = @"windowName";
static NSString *const iTermSessionTitleArgTmuxWindowName = @"tmuxWindowName";
static NSString *const iTermSessionTitleArgTmuxWindowTitle = @"tmuxWindowTitle";
static NSString *const iTermSessionTitleArgRows = @"rows";
static NSString *const iTermSessionTitleArgColumns = @"columns";
static NSString *const iTermSessionTitleSession = @"session";


@implementation iTermSessionTitleBuiltInFunction

#pragma mark - iTermBuiltInFunction

+ (void)registerBuiltInFunction {
    NSDictionary<NSString *, NSString *> *defaults =
    @{ iTermSessionTitleArgName: iTermVariableKeySessionAutoName,
       iTermSessionTitleArgProfile: iTermVariableKeySessionProfileName,
       iTermSessionTitleArgJob: iTermVariableKeySessionProcessTitle,
       iTermSessionTitleArgCommandLine: iTermVariableKeySessionCommandLine,
       iTermSessionTitleArgPath: iTermVariableKeySessionPath,
       iTermSessionTitleArgTTY: iTermVariableKeySessionTTY,
       iTermSessionTitleArgUser: iTermVariableKeySessionUsername,
       iTermSessionTitleArgHost: iTermVariableKeySessionHostname,
       iTermSessionTitleArgHomeDirectory: iTermVariableKeySessionHomeDirectory,
       iTermSessionTitleArgTmuxPane: iTermVariableKeySessionTmuxPaneTitle,
       iTermSessionTitleArgTmuxRole: iTermVariableKeySessionTmuxRole,
       iTermSessionTitleArgTmuxClientName: iTermVariableKeySessionTmuxClientName,
       iTermSessionTitleArgIconName: iTermVariableKeySessionIconName,
       iTermSessionTitleArgWindowName: iTermVariableKeySessionWindowName,
       iTermSessionTitleArgTmuxWindowName: [NSString stringWithFormat:@"%@.%@", iTermVariableKeySessionTab, iTermVariableKeyTabTmuxWindowName],
       iTermSessionTitleArgTmuxWindowTitle: [NSString stringWithFormat:@"%@.%@", iTermVariableKeySessionTab, iTermVariableKeyTabTmuxWindowTitle],
       iTermSessionTitleArgRows: iTermVariableKeySessionRows,
       iTermSessionTitleArgColumns: iTermVariableKeySessionColumns
       };
    // This would be a cyclic reference since the session.name is the result of this function.
    assert(![defaults.allValues containsObject:iTermVariableKeySessionName]);
    NSSet *optionalArguments = [NSSet setWithArray:@[ iTermSessionTitleArgTmuxPane,
                                                      iTermSessionTitleArgTmuxRole,
                                                      iTermSessionTitleArgTmuxClientName,
                                                      iTermSessionTitleArgTmuxWindowName,
                                                      iTermSessionTitleArgTmuxWindowTitle ]];
    {
        iTermBuiltInFunction *func =
        [[iTermBuiltInFunction alloc] initWithName:@"session_title"
                                         arguments:@{ iTermSessionTitleSession: [NSString class] }
                                 optionalArguments:optionalArguments
                                     defaultValues:defaults
                                           context:iTermVariablesSuggestionContextSession
                                             block:
         ^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock  _Nonnull completion) {
             NSString *result = [self titleForParameters:parameters isWindow:NO];
             completion(result, nil);
         }];
        [[iTermBuiltInFunctions sharedInstance] registerFunction:func
                                                       namespace:@"iterm2.private"];
    }
    {
        iTermBuiltInFunction *func =
        [[iTermBuiltInFunction alloc] initWithName:@"window_title"
                                         arguments:@{ iTermSessionTitleSession: [NSString class] }
                                 optionalArguments:optionalArguments
                                     defaultValues:defaults
                                           context:iTermVariablesSuggestionContextSession
                                             block:
         ^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock  _Nonnull completion) {
             NSString *result = [self titleForParameters:parameters isWindow:YES];
             // NOTE: iTermSessionNameController assumes that the built-in window_title function completes synchronously.
             completion(result, nil);
         }];
        [[iTermBuiltInFunctions sharedInstance] registerFunction:func
                                                       namespace:@"iterm2.private"];
    }
}

+ (NSString *)titleForParameters:(NSDictionary *)parameters isWindow:(BOOL)isWindow {
    NSString *(^trim)(NSString *) = ^NSString *(NSString *value) {
        NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length) {
            return trimmed;
        } else {
            return nil;
        }
    };
    NSString *sessionID = parameters[iTermSessionTitleSession];
    PTYSession *session = [[PTYSession sessionMap] objectForKey:sessionID];
    NSString *name = trim(parameters[iTermSessionTitleArgName]);
    NSString *profile = trim(parameters[iTermSessionTitleArgProfile]);
    NSString *job = trim(parameters[iTermSessionTitleArgJob]);
    NSString *commandLine = trim(parameters[iTermSessionTitleArgCommandLine]);
    NSString *pwd = trim(parameters[iTermSessionTitleArgPath]);
    NSString *tty = trim(parameters[iTermSessionTitleArgTTY]);
    NSString *user = trim(parameters[iTermSessionTitleArgUser]);
    NSString *host = trim(parameters[iTermSessionTitleArgHost]);
    NSString *homeDirectory = trim(parameters[iTermSessionTitleArgHomeDirectory]);
    NSString *tmuxPane = trim(parameters[iTermSessionTitleArgTmuxPane]);
    NSString *iconName = trim(parameters[iTermSessionTitleArgIconName]);
    NSString *windowName = trim(parameters[iTermSessionTitleArgWindowName]);
    NSString *tmuxWindowName = trim(parameters[iTermSessionTitleArgTmuxWindowName]);
    NSString *tmuxWindowTitle = trim(parameters[iTermSessionTitleArgTmuxWindowTitle]);
    NSNumber *rows = parameters[iTermSessionTitleArgRows];
    NSNumber *columns = parameters[iTermSessionTitleArgColumns];

    iTermTitleComponents titleComponents;
    titleComponents = [iTermProfilePreferences unsignedIntegerForKey:KEY_TITLE_COMPONENTS
                                                           inProfile:session.profile];

    NSString *result = [self titleForSessionName:name
                                     profileName:profile
                                             job:job
                                     commandLine:commandLine
                                             pwd:pwd
                                             tty:tty
                                            user:user
                                            host:host
                                   homeDirectory:homeDirectory
                                        tmuxPane:tmuxPane
                                        iconName:iconName
                                      windowName:windowName
                                  tmuxWindowName:tmuxWindowName
                                 tmuxWindowTitle:tmuxWindowTitle
                                            rows:rows
                                         columns:columns
                                      components:titleComponents
                                   isWindowTitle:isWindow];
    DLog(@"Title for session %@ is %@", session, result);
    return result;
}

// Historical note: 3.2 and earlier had three flags that controlled behavior: job, profile, and sticky.
// SessionName is the name inherited from the profile or set by icon title, manual edit, or trigger.
// Job Profile Sticky      Name unchanged    Name changed
// no  no      no          "Shell"           SessionName

// no  no      yes         "Shell"           SessionName
// yes no      no          job               SessionName (job)
// yes no      yes         job               SessionName (job)
//
// no  yes     no          ProfileName       SessionName
// yes yes     no          ProfileName (job) SessionName (job)
//
// no  yes     yes         ProfileName       ProfileName: IconTitle -or- SessionName
// yes yes     yes         ProfileName (job) ProfileName: IconTitle -or- SessionName (job)
+ (NSString *)titleForSessionName:(NSString *)rawSessionName
                      profileName:(NSString *)profileName
                              job:(NSString *)jobVariable
                      commandLine:(NSString *)commandLineVariable
                              pwd:(NSString *)pwdVariable
                              tty:(NSString *)ttyVariable
                             user:(NSString *)userVariable
                             host:(NSString *)hostVariable
                    homeDirectory:(NSString *)homeDirectoryVariable
                         tmuxPane:(NSString *)tmuxPaneVariable
                         iconName:(NSString *)iconName
                       windowName:(NSString *)windowName
                   tmuxWindowName:(NSString *)tmuxWindowName
                  tmuxWindowTitle:(NSString *)tmuxWindowTitle
                             rows:(NSNumber *)rows
                          columns:(NSNumber *)columns
                       components:(iTermTitleComponents)titleComponents
                    isWindowTitle:(BOOL)isWindowTitle {
    NSString *sessionName = isWindowTitle ? rawSessionName.removingHTMLFromTabTitleIfNeeded : rawSessionName;
    DLog(@"sessionName=%@ profileName=%@ job=%@ commandLine=%@ pwd=%@ tty=%@ user=%@ host=%@ tmuxPane=%@ iconName=%@ windowName=%@ tmuxWindowName=%@ tmuxWindowTitle=%@ isWindowTitle=%@ rows=%@ columns=%@",
         sessionName, profileName, jobVariable, commandLineVariable, pwdVariable, ttyVariable,
         userVariable, hostVariable, tmuxPaneVariable, iconName, windowName, tmuxWindowName,
         tmuxWindowTitle, @(isWindowTitle), rows, columns);

    NSString *name = nil;
    NSMutableString *result = [NSMutableString string];

    if (titleComponents == iTermTitleComponentsCustom) {
        // This can happen when the session is synthesized
        return @"";
    }

    NSString *effectiveSessionName;
    if (tmuxPaneVariable) {
        if (isWindowTitle) {
            // `tmuxWindowTitle` comes from #{T:set-titles-string} if you've done `set-option -g set-titles on`. Prefer this since it is an explicit opt-in.
            // `windowName` is affected by OSC 0 and OSC 2 and popping the window title stack. It will be unset if there was no OSC. This is the session's `terminalWindowName` variable.
            // `tmuxWindowName` comes from `#{window_name}`. The default is the current process. It can be changed with the rename-window command or ESC k. It comes from the variable `tab.tmuxWindowName`. It is driven by the %window-renamed notification.
            // `tmuxPaneVariable` corresponds to #{pane_title}, which is affected by OSC 0 and OSC 2 and popping the window title stack. Its default value is the hostname.
            effectiveSessionName = tmuxWindowTitle ?: windowName ?: tmuxWindowName ?: tmuxPaneVariable;
        } else {
            effectiveSessionName = tmuxPaneVariable;
        }
    } else if (isWindowTitle && windowName) {
        return windowName;
    } else {
        effectiveSessionName = sessionName;
    }
    if (titleComponents == 0) {
        if (isWindowTitle) {
            if (windowName) {
                return windowName;
            } else if (iconName) {
                return iconName;
            }
        } else {
            if (iconName) {
                return iconName;
            } else if (windowName) {
                return windowName;
            }
        }
        return @"Shell";
    }
    if (titleComponents & iTermTitleComponentsSessionName) {
        name = effectiveSessionName;
    } else if (titleComponents & iTermTitleComponentsProfileName) {
        name = profileName;
    } else if (titleComponents & iTermTitleComponentsProfileAndSessionName) {
        if (effectiveSessionName && profileName) {
            if ([effectiveSessionName isEqualToString:profileName]) {
                name = effectiveSessionName;
            } else {
                name = [NSString stringWithFormat:@"%@: %@", profileName, effectiveSessionName];
            }
        } else {
            name = effectiveSessionName ?: profileName;
        }
    }
    if (name) {
        [result appendString:name];
    }

    NSString *job = nil;
    if (titleComponents & iTermTitleComponentsCommandLine) {
        job = commandLineVariable;
    } else if (titleComponents & iTermTitleComponentsJob) {
        job = jobVariable;
    }
    if (job) {
        if (result.length) {
            [result appendFormat:@" (%@)", job];
        } else {
            [result appendString:job];
        }
    }

    const BOOL showUser = userVariable.length && (titleComponents & iTermTitleComponentsUser);
    const BOOL showHost = hostVariable.length && (titleComponents & iTermTitleComponentsHost);
    const BOOL showPWD = pwdVariable.length && (titleComponents & iTermTitleComponentsWorkingDirectory);

    //                                               User Host PWD
    NSArray<NSString *> *formats = @[ @"",        //
                                      @"U",       // X
                                      @"H",       //      X
                                      @"U@H",     // X    X
                                      @"P",       //           X
                                      @"U:P",     // X         X
                                      @"H:P",     //      X    X
                                      @"U@H:P" ]; // X    X    X
    int formatIndex = (showUser ? 1 : 0) | (showHost ? 2 : 0) | (showPWD ? 4 : 0);
    if (formatIndex) {
        NSString *format = formats[formatIndex];
        NSMutableString *userHostPWD = [NSMutableString string];
        for (NSInteger i = 0; i < format.length; i++) {
            unichar c = [format characterAtIndex:i];
            if (c == 'U') {
                [userHostPWD appendString:userVariable ?: @""];
            } else if (c == 'H') {
                [userHostPWD appendString:hostVariable ?: @""];
            } else if (c == 'P') {
                [userHostPWD appendString:[self prettyPWD:pwdVariable homeDirectory:homeDirectoryVariable] ?: @""];
            } else {
                [userHostPWD appendCharacter:c];
            }
        }
        if (result.length) {
            [result appendFormat:@" — %@", userHostPWD];
        } else {
            [result appendString:userHostPWD];
        }
    }

    NSString *tty = nil;
    if (titleComponents & iTermTitleComponentsTTY) {
        tty = ttyVariable;
    }
    if (tty) {
        if (result.length) {
            [result appendFormat:@" — %@", tty];
        } else {
            [result appendString:tty];
        }
    }
    if (titleComponents & iTermTitleComponentsSize) {
        if (![result hasSuffix:@" "]) {
            [result appendString:@" "];
        }
        [result appendString:@" — "];
        [result appendString:iTermColumnsByRowsString(columns.intValue, rows.intValue)];
    }

    if (!result.length) {
        [result appendString:@" "];
    }
    return result;
}

NSString *iTermColumnsByRowsString(int columns, int rows) {
    return [NSString stringWithFormat:@"%d✕%d", columns, rows];
}

+ (NSString *)prettyPWD:(NSString *)absolutePath
          homeDirectory:(NSString *)home {
    if (!home) {
        return absolutePath;
    }
    if (![absolutePath hasPrefix:home]) {
        return absolutePath;
    }
    return [@"~" stringByAppendingString:[absolutePath stringByRemovingPrefix:home]];
}

@end
