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
static NSString *const iTermSessionTitleArgAITitle = @"aiTitle";
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
       iTermSessionTitleArgAITitle: iTermVariableKeySessionAITitle,
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
                                                      iTermSessionTitleArgTmuxWindowTitle,
                                                      iTermSessionTitleArgAITitle ]];
    {
        iTermBuiltInFunction *func =
        [[iTermBuiltInFunction alloc] initWithName:@"session_title"
                                         arguments:@{ iTermSessionTitleSession: [NSString class] }
                                 optionalArguments:optionalArguments
                                     defaultValues:defaults
                                           context:iTermVariablesSuggestionContextSession
                            sideEffectsPlaceholder:nil
                                             block:
         ^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock  _Nonnull completion) {
             NSString *result = [self titleForParameters:parameters isWindow:NO];
             completion(result, nil);
         }];
        [[iTermBuiltInFunctions sharedInstance] registerFunction:func
                                                       namespace:@"iterm2.private"];
    }
    {
        // window_title uses the SAME argument set as session_title (including aiTitle).
        // An earlier version stripped aiTitle from window_title's args to avoid a ~5s
        // aiTitle mutation invalidating the window title, but that bought nothing:
        // iTermSessionNameController evaluates session_title and window_title against the
        // SAME recording scope and records the UNION of their reads, and session_title
        // reads session.aiTitle, so aiTitle is a dependency of the combined evaluation
        // regardless of window_title's declared args. An aiTitle change re-runs the whole
        // system-title evaluation (recomputing the window title to a provably-identical
        // value) either way. Stripping it only diverged the two functions' argument
        // signatures (window_title would reject an explicit aiTitle: caller passes). If the
        // redundant window-title recompute is ever worth eliminating, it must be done at
        // the name-controller level (a separate scope, or skipping window_title reeval when
        // only aiTitle changed), not here. Output is correct either way (window titles
        // never render aiTitle).
        iTermBuiltInFunction *func =
        [[iTermBuiltInFunction alloc] initWithName:@"window_title"
                                         arguments:@{ iTermSessionTitleSession: [NSString class] }
                                 optionalArguments:optionalArguments
                                     defaultValues:defaults
                                           context:iTermVariablesSuggestionContextSession
                            sideEffectsPlaceholder:nil
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
    if (!session) {
        // The session id did not resolve to a live session in the session map. Don't
        // bail: name/profile/job below come from the invocation scope, not the session
        // object, so we can still produce a (degraded) title -- which is what a terminal
        // session shows in this case, as it did before. We deliberately do NOT force the
        // browser session-name component here (we can't tell it's a browser without the
        // session), but a browser's resulting blank title is caught by the name
        // controller's browser-only blank suppression, which reads the real session via
        // its delegate. This should not normally happen; if it recurs it usually means
        // session.id has diverged from the session's guid (the map key), e.g. an
        // arrangement restoring the reserved id variable outside of -setGuid:.
        RLog(@"session_title: session id “%@” not found in session map (idIsEmpty=%@, mapCount=%@); computing from arguments",
             sessionID, @(sessionID.length == 0), @([PTYSession sessionMap].count));
    }
    NSString *name = trim(parameters[iTermSessionTitleArgName]);
    NSString *profile = trim(parameters[iTermSessionTitleArgProfile]);
    NSString *job = trim(parameters[iTermSessionTitleArgJob]);
    NSString *commandLine = trim(parameters[iTermSessionTitleArgCommandLine]);
    NSString *pwd = trim(parameters[iTermSessionTitleArgPath]);
    NSString *tty = trim(parameters[iTermSessionTitleArgTTY]);
    NSString *user = trim(parameters[iTermSessionTitleArgUser]);
    NSString *host = trim(parameters[iTermSessionTitleArgHost]);
    NSString *aiTitle = trim(parameters[iTermSessionTitleArgAITitle]);
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

    // A browser session has no job, tty, host, user, pwd, or terminal size, so a
    // title made only of those components (the job-only global default, or a stale
    // job-only override left in a saved arrangement by an older build) renders empty.
    // Guarantee the page title is visible by including the session-name component.
    // This is done here, at the single point where the components are consumed, so it
    // covers every browser session regardless of how it was created or restored.
    // A name component or the profile name yields a non-empty title for a browser;
    // only when neither is present do we add the session-name component so the page
    // title shows. Custom is deliberately NOT counted: a bare Custom component with no
    // script provider yields an empty title for a browser (there is no custom text),
    // which is exactly what we want to avoid. A real custom-title profile uses a
    // separate provider identifier, so session_title is not invoked for it and this
    // guarantee never runs.
    const iTermTitleComponents browserVisibleComponents = (iTermTitleComponentsSessionName |
                                                           iTermTitleComponentsProfileName |
                                                           iTermTitleComponentsProfileAndSessionName |
                                                           iTermTitleComponentsTemporarySessionName);
    if (session.isBrowserSession && !(titleComponents & browserVisibleComponents)) {
        titleComponents |= iTermTitleComponentsSessionName;
    }

    NSString *result = [self titleForSessionName:name
                                     profileName:profile
                                             job:job
                                     commandLine:commandLine
                                             pwd:pwd
                                             tty:tty
                                            user:user
                                            host:host
                                         aiTitle:aiTitle
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

// The icon/window/Shell fallback precedence, shared by the no-components case
// and the AI-empty case so the two don't drift.
// The program's own OSC name in the order that matters for this title: for a window
// title the OSC 2 window name leads, for a tab title the OSC 1 icon name leads.
// Returns nil if neither is set. One definition of this precedence, shared by the
// all-empty fallback (which appends "Shell") and the AI-branch degrade (which
// appends the session name).
static NSString *iTermTitleIconWindowName(NSString *iconName, NSString *windowName, BOOL isWindowTitle) {
    if (isWindowTitle) {
        return windowName ?: iconName;
    }
    return iconName ?: windowName;
}

static NSString *iTermTitleIconWindowShellFallback(NSString *iconName, NSString *windowName, BOOL isWindowTitle) {
    return iTermTitleIconWindowName(iconName, windowName, isWindowTitle) ?: @"Shell";
}

+ (NSString *)titleForSessionName:(NSString *)rawSessionName
                      profileName:(NSString *)profileName
                              job:(NSString *)jobVariable
                      commandLine:(NSString *)commandLineVariable
                              pwd:(NSString *)pwdVariable
                              tty:(NSString *)ttyVariable
                             user:(NSString *)userVariable
                             host:(NSString *)hostVariable
                          aiTitle:(NSString *)aiTitleVariable
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
    DLog(@"sessionName=%@ profileName=%@ job=%@ commandLine=%@ pwd=%@ tty=%@ user=%@ host=%@ tmuxPane=%@ iconName=%@ windowName=%@ tmuxWindowName=%@ tmuxWindowTitle=%@ isWindowTitle=%@ rows=%@ columns=%@ titleComponents=%@",
         sessionName, profileName, jobVariable, commandLineVariable, pwdVariable, ttyVariable,
         userVariable, hostVariable, tmuxPaneVariable, iconName, windowName, tmuxWindowName,
         tmuxWindowTitle, @(isWindowTitle), rows, columns, @(titleComponents));

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
            //
            effectiveSessionName = tmuxWindowTitle ?: windowName ?: tmuxWindowName ?: tmuxPaneVariable;
        } else {
            effectiveSessionName = tmuxPaneVariable;
        }
    } else if (isWindowTitle && windowName) {
        // A non-tmux WINDOW title: an explicit OSC 2 window name IS the window title,
        // for AI and non-AI profiles ALIKE. OSC 2 window titles win over tab titles, and
        // enabling the AI tab-title component must not change that - it must not adopt
        // the model guess for the window title, nor append Job/Size suffixes the non-AI
        // path never adds. Returned verbatim, above every component including
        // TemporarySessionName (a Set-Title trigger / manual rename). (tmux window titles
        // are handled by the tmuxPaneVariable branch above, where AI and non-AI both flow
        // through the suffix append, so they are already consistent.)
        return windowName;
    } else {
        effectiveSessionName = sessionName;
    }
    if (titleComponents == 0) {
        return iTermTitleIconWindowShellFallback(iconName, windowName, isWindowTitle);
    }
    if ((titleComponents & iTermTitleComponentsTemporarySessionName) && effectiveSessionName.length) {
        // An explicitly set name (a "Set Title" trigger, an OSC 1/2 icon/window
        // name, or a manual tab rename, all surfaced through the
        // TemporarySessionName component by enableSessionNameTitleComponentIfPossible)
        // is a deliberate choice by the user or program, a stronger signal than
        // a model guess. So it takes precedence over the AI title rather than
        // being masked by it.
        name = effectiveSessionName;
    } else if (titleComponents & iTermTitleComponentsAI) {
        // AI profile. The AI title is a TAB-only name source: it names the visible work
        // and wins for the tab title, but it must never hijack the window title. So
        // rather than re-derive the tmux/window/session precedence in AI-specific
        // branches, compute the name slot the way a non-AI name-group component would and
        // override it with the AI title for the tab title only. This is a unification of
        // what were five hand-synced branches into three.
        if (!isWindowTitle && aiTitleVariable.length) {
            // Tab title with an AI title: the model's name of the visible work wins.
            name = aiTitleVariable;
        } else if (isWindowTitle) {
            // WINDOW title (the AI title never applies here). Degrade to
            // effectiveSessionName, which already encodes the tmux window-title chain
            // (tmuxWindowTitle ?: windowName ?: tmuxWindowName ?: tmuxPaneVariable) and,
            // for a non-tmux session, the session name - EXACTLY like a non-AI window
            // title. (A non-tmux window with an explicit OSC 2 name returned verbatim far
            // above, so this is the no-explicit-name degrade.) Those were branches
            // 1/2/4a: tmuxWindowTitle and windowName are just the first non-nil terms of
            // effectiveSessionName, so a single assignment reproduces all three.
            name = effectiveSessionName;
        } else {
            // TAB title with no AI title yet. Prefer the program's own OSC name (icon then
            // window), so a profile that also selects a secondary component like Job shows
            // `filename (vim)` rather than just `(vim)`, then the session name. A plain
            // fallback, not a sticky TemporarySessionName: a real AI title replaces it as
            // soon as one exists (no hijack).
            name = iTermTitleIconWindowName(iconName, windowName, isWindowTitle) ?: effectiveSessionName;
        }
    } else if (titleComponents & (iTermTitleComponentsSessionName | iTermTitleComponentsTemporarySessionName)) {
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
        // Only an AI TAB gets the icon/window/Shell fallback: an AI profile whose aiTitle
        // is empty (model not run yet, Apple Intelligence unavailable on macOS < 26, or the
        // screen deliberately left unnamed) would otherwise render a blank TAB. Gated on
        // !isWindowTitle: the justification is tab-only, and applying it to WINDOW titles
        // would change an AI window title's historical empty-result behavior from a single
        // space to "Shell"/icon/window - an unintended, AI-bit-gated window-title change.
        // Non-AI profiles (and AI window titles) keep the historical single-space behavior
        // so this doesn't silently change their titles.
        if (!isWindowTitle && (titleComponents & iTermTitleComponentsAI)) {
            return iTermTitleIconWindowShellFallback(iconName, windowName, isWindowTitle);
        }
        [result appendString:@" "];
    }
    return result;
}

NSString *iTermColumnsByRowsString(int columns, int rows) {
    return [NSString stringWithFormat:@"%d✕%d", columns, rows];
}

// Collapses every run of "/" to a single "/" and drops a trailing slash, so a
// displayed path never contains "//" and "/Users/x/" compares equal to "/Users/x".
// A slash-only input ("/", "//") normalizes to "/". The common case (no doubled
// slash, no trailing slash) returns the input without allocating.
static NSString *iTermNormalizeSlashes(NSString *s) {
    if (!s.length) {
        return @"";
    }
    const BOOL hasDoubled = [s containsString:@"//"];
    const BOOL hasTrailing = s.length > 1 && [s characterAtIndex:s.length - 1] == '/';
    if (!hasDoubled && !hasTrailing) {
        return s;
    }
    NSMutableString *result = [NSMutableString stringWithString:s];
    // Collapse runs in place. Loop because a single pass leaves a run of 3+ slashes
    // partly doubled ("///" -> "//"): replaceOccurrences does not re-scan the text it
    // just inserted. Real paths have at most a doubled slash, so this runs once.
    while ([result replaceOccurrencesOfString:@"//"
                                   withString:@"/"
                                      options:0
                                        range:NSMakeRange(0, result.length)] > 0) {
        // Keep collapsing until no "//" remains.
    }
    if (result.length > 1 && [result hasSuffix:@"/"]) {
        [result deleteCharactersInRange:NSMakeRange(result.length - 1, 1)];
    }
    return result;
}

+ (NSString *)prettyPWD:(NSString *)absolutePath
          homeDirectory:(NSString *)home {
    // Normalize both sides first so a doubled slash can never reach the output and a
    // trailing slash doesn't defeat the boundary match.
    NSString *path = iTermNormalizeSlashes(absolutePath);
    NSString *homeStem = iTermNormalizeSlashes(home);
    // No home, or a root home ("/"): every absolute path begins with it, so there is
    // nothing useful to abbreviate. Show the normalized path (whether that renders as
    // "/" or "~" for a literally-root home is don't-care; the point is it is never "//").
    if (!homeStem.length || [homeStem isEqualToString:@"/"]) {
        return path;
    }
    if ([path isEqualToString:homeStem]) {
        return @"~";
    }
    // Match on a path BOUNDARY (home + "/"), not a bare prefix, so /Users/gnachmanx is not
    // rewritten to ~x for home /Users/gnachman.
    if ([path hasPrefix:[homeStem stringByAppendingString:@"/"]]) {
        return [@"~" stringByAppendingString:[path substringFromIndex:homeStem.length]];
    }
    return path;
}

@end
