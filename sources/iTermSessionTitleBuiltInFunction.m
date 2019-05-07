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
#import "PTYSession.h"

// Arguments to title BIF
static NSString *const iTermSessionTitleArgName = @"name";
static NSString *const iTermSessionTitleArgProfile = @"profile";
static NSString *const iTermSessionTitleArgJob = @"job";
static NSString *const iTermSessionTitleArgPath = @"path";
static NSString *const iTermSessionTitleArgTTY = @"tty";
static NSString *const iTermSessionTitleArgUser = @"username";
static NSString *const iTermSessionTitleArgHost = @"hostname";
static NSString *const iTermSessionTitleArgTmux = @"tmux";
static NSString *const iTermSessionTitleArgTmuxRole = @"tmuxRole";
static NSString *const iTermSessionTitleArgTmuxClientName = @"tmuxClientName";
static NSString *const iTermSessionTitleArgIconName = @"iconName";
static NSString *const iTermSessionTitleArgWindowName = @"windowName";

static NSString *const iTermSessionTitleSession = @"session";


@implementation iTermSessionTitleBuiltInFunction

#pragma mark - iTermBuiltInFunction

+ (void)registerBuiltInFunction {
    NSDictionary<NSString *, NSString *> *defaults =
    @{ iTermSessionTitleArgName: iTermVariableKeySessionAutoName,
       iTermSessionTitleArgProfile: iTermVariableKeySessionProfileName,
       iTermSessionTitleArgJob: iTermVariableKeySessionJob,
       iTermSessionTitleArgPath: iTermVariableKeySessionPath,
       iTermSessionTitleArgTTY: iTermVariableKeySessionTTY,
       iTermSessionTitleArgUser: iTermVariableKeySessionUsername,
       iTermSessionTitleArgHost: iTermVariableKeySessionHostname,
       iTermSessionTitleArgTmux: iTermVariableKeySessionTmuxWindowTitleEval,
       iTermSessionTitleArgTmuxRole: iTermVariableKeySessionTmuxRole,
       iTermSessionTitleArgTmuxClientName: iTermVariableKeySessionTmuxClientName,
       iTermSessionTitleArgIconName: iTermVariableKeySessionIconName,
       iTermSessionTitleArgWindowName: iTermVariableKeySessionWindowName,
       };
    // This would be a cyclic reference since the session.name is the result of this function.
    assert(![defaults.allValues containsObject:iTermVariableKeySessionName]);

    {
        iTermBuiltInFunction *func =
        [[iTermBuiltInFunction alloc] initWithName:@"session_title"
                                         arguments:@{ iTermSessionTitleSession: [NSString class] }
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
    NSString *pwd = trim(parameters[iTermSessionTitleArgPath]);
    NSString *tty = trim(parameters[iTermSessionTitleArgTTY]);
    NSString *user = trim(parameters[iTermSessionTitleArgUser]);
    NSString *host = trim(parameters[iTermSessionTitleArgHost]);
    NSString *tmux = trim(parameters[iTermSessionTitleArgTmux]);
    NSString *iconName = trim(parameters[iTermSessionTitleArgIconName]);
    NSString *windowName = trim(parameters[iTermSessionTitleArgWindowName]);
    iTermTitleComponents titleComponents;
    titleComponents = [iTermProfilePreferences unsignedIntegerForKey:KEY_TITLE_COMPONENTS
                                                           inProfile:session.profile];

    NSString *result = [self titleForSessionName:name
                                     profileName:profile
                                             job:job
                                             pwd:pwd
                                             tty:tty
                                            user:user
                                            host:host
                                            tmux:tmux
                                        iconName:iconName
                                      windowName:windowName
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
+ (NSString *)titleForSessionName:(NSString *)sessionName
                      profileName:(NSString *)profileName
                              job:(NSString *)jobVariable
                              pwd:(NSString *)pwdVariable
                              tty:(NSString *)ttyVariable
                             user:(NSString *)userVariable
                             host:(NSString *)hostVariable
                             tmux:(NSString *)tmuxVariable
                         iconName:(NSString *)iconName
                       windowName:(NSString *)windowName
                       components:(iTermTitleComponents)titleComponents
                    isWindowTitle:(BOOL)isWindowTitle {
    DLog(@"Compute title for sessionName=%@ profileName=%@ jobVariable=%@ pwdVariable=%@ ttyVariable=%@ userVariable=%@ hostVariable=%@ tmuxVariable=%@",
         sessionName, profileName, jobVariable, pwdVariable, ttyVariable, userVariable, hostVariable, tmuxVariable);
    NSString *name = nil;
    NSMutableString *result = [NSMutableString string];

    if (titleComponents == iTermTitleComponentsCustom) {
        // This can happen when the session is synthesized
        return @"";
    }

    NSString *effectiveSessionName;
    if (tmuxVariable) {
        effectiveSessionName = tmuxVariable;
    } else {
        if (isWindowTitle) {
            effectiveSessionName = windowName ?: sessionName;
        } else {
            effectiveSessionName = sessionName;
        }
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
    if (titleComponents & iTermTitleComponentsJob) {
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
                [userHostPWD appendString:pwdVariable ?: @""];
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

    if (!result.length) {
        [result appendString:@" "];
    }
    return result;
}

@end
