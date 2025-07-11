//
//  iTermSessionLauncher.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/11/19.
//

#import "iTermSessionLauncher.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "iTermController.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "iTermSessionFactory.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "ProfileModel.h"
#import "PTYSession.h"
#import "PseudoTerminal.h"

@implementation iTermSessionLauncher {
    BOOL _finished;
    BOOL _haveSetSession;
    BOOL _launched;
    id _keepAlive;  // reference to self so I don't get released before completion.
}

+ (BOOL)profileIsWellFormed:(Profile *)profile {
    NSFont *font = [ITAddressBookMgr fontWithDesc:[profile objectForKey:KEY_NORMAL_FONT]
                                 ligaturesEnabled:[iTermProfilePreferences boolForKey:KEY_ASCII_LIGATURES
                                                                            inProfile:profile]];
    if (!font) {
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"Couldn’t find the specified font “%@” or the fallback standard fixed-pitch font, Menlo. Please ensure at least one of these is installed.", profile[KEY_NORMAL_FONT]]
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:nil
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Invalid Profile"
                                    window:nil];
        return NO;
    }
    return YES;
}

+ (void)launchBookmark:(NSDictionary *)bookmarkData
            inTerminal:(PseudoTerminal *)theTerm
    respectTabbingMode:(BOOL)respectTabbingMode
            completion:(void (^)(PTYSession *session))completion {
    return [self launchBookmark:bookmarkData
                     inTerminal:theTerm
                        withURL:nil
                       hotkeyWindowType:iTermHotkeyWindowTypeNone
                        makeKey:YES
                    canActivate:YES
             respectTabbingMode:respectTabbingMode
                          index:nil
                        command:nil
                    makeSession:nil
                 didMakeSession:completion
                     completion:nil];
}

+ (void)launchBookmark:(NSDictionary *)bookmarkData
            inTerminal:(PseudoTerminal *)theTerm
               withURL:(NSString *)url
      hotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType
               makeKey:(BOOL)makeKey
           canActivate:(BOOL)canActivate
    respectTabbingMode:(BOOL)respectTabbingMode
                 index:(NSNumber *)index
               command:(NSString *)command
           makeSession:(void (^)(Profile *profile, PseudoTerminal *windowController, void (^completion)(PTYSession *)))makeSession
        didMakeSession:(void (^)(PTYSession *))didMakeSession
            completion:(void (^ _Nullable)(PTYSession *, BOOL))completion {
    iTermSessionLauncher *launcher = [[iTermSessionLauncher alloc] initWithProfile:bookmarkData windowController:theTerm];
    launcher.url = url;
    launcher.hotkeyWindowType = hotkeyWindowType;
    launcher.makeKey = makeKey;
    launcher.canActivate = canActivate;
    launcher.respectTabbingMode = respectTabbingMode;
    launcher.command = command;
    if (makeSession) {
        launcher.makeSession = makeSession;
    }
    launcher.didCreateSession = didMakeSession;
    launcher.index = index;
    [launcher launchWithCompletion:completion];
}

+ (PTYSession *)synchronouslyLaunchProfile:(nullable NSDictionary *)bookmarkData
                                inTerminal:(nullable PseudoTerminal *)theTerm
                                   withURL:(nullable NSString *)url
                          hotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType
                                   makeKey:(BOOL)makeKey
                               canActivate:(BOOL)canActivate
                        respectTabbingMode:(BOOL)respectTabbingMode
                                     index:(NSNumber * _Nullable)index
                                   command:(nullable NSString *)command
                               makeSession:(PTYSession *(^)(Profile *profile, PseudoTerminal *windowController))makeSession {
    iTermSessionLauncher *launcher = [[iTermSessionLauncher alloc] initWithProfile:bookmarkData windowController:theTerm];
    launcher.url = url;
    launcher.hotkeyWindowType = hotkeyWindowType;
    launcher.makeKey = makeKey;
    launcher.canActivate = canActivate;
    launcher.respectTabbingMode = respectTabbingMode;
    launcher.command = command;
    launcher.index = index;
    return [launcher launchSynchronously:makeSession];
}


- (instancetype)initWithProfile:(nullable Profile *)profile
               windowController:(nullable PseudoTerminal *)windowController {
    self = [super init];
    if (self) {
        _profile = [profile copy];
        _windowController = windowController;
        _makeKey = YES;
        _canActivate = YES;
        _respectTabbingMode = NO;
        _hotkeyWindowType = iTermHotkeyWindowTypeNone;
    }
    return self;
}

- (void)launchWithCompletion:(void (^ _Nullable)(PTYSession *session, BOOL ok))completion {
    _completion = [completion copy];
    [self prepareToLaunch];

    Profile *profile = [self modifiedProfile];
    if (!profile) {
        DLog(@"No profile");
        [self setFinishedWithSuccess:NO];
        self.session = nil;
        return;
    }

    BOOL toggle = NO;
    PseudoTerminal *windowController = [self possiblyNewWindowControllerForProfile:profile
                                                         toggleFullScreen:&toggle];
    if (toggle) {
        windowController.fullScreenPromise = [iTermPromise promise:^(id<iTermPromiseSeal>  _Nonnull seal) {
            windowController.fullScreenEnteredSeal = seal;
        }];
    }
    __weak __typeof(self) weakSelf = self;
    [self makeSessionWithProfile:profile
                windowController:windowController
                      completion:
     ^(PTYSession *session, BOOL willCallCompletionBlock) {
         DLog(@"session=%@ willCallCompletionBlock=%@", session, @(willCallCompletionBlock));
         if (!session && windowController.numberOfTabs == 0) {
             DLog(@"abort");
             [[windowController window] close];
             if (!willCallCompletionBlock) {
                 [weakSelf setFinishedWithSuccess:NO];
             }
             weakSelf.session = nil;
             return;
         }
         [self setSession:session withSideEffects:NO];
         if (toggle) {
             DLog(@"toggle");
             [windowController delayedEnterFullscreen];
         }
         [weakSelf makeKeyAndActivateIfNeeded:windowController];

         if (!willCallCompletionBlock) {
             [weakSelf setFinishedWithSuccess:YES];
         }
         [self setSession:session withSideEffects:YES];
     }];
}

- (PTYSession *)launchSynchronously:(PTYSession *(^)(Profile *profile, PseudoTerminal *windowController))makeSession  {
    [self prepareToLaunch];

    Profile *profile = [self modifiedProfile];
    if (!profile) {
        DLog(@"No profile");
        [self setFinishedWithSuccess:NO];
        self.session = nil;
        return nil;
    }

    BOOL toggle = NO;
    PseudoTerminal *windowController = [self possiblyNewWindowControllerForProfile:profile
                                                         toggleFullScreen:&toggle];
    if (toggle) {
        windowController.fullScreenPromise = [iTermPromise promise:^(id<iTermPromiseSeal>  _Nonnull seal) {
            windowController.fullScreenEnteredSeal = seal;
        }];
    }
    PTYSession *session = makeSession(profile, windowController);
    if (!session && windowController.numberOfTabs == 0) {
        DLog(@"abort");
        [[windowController window] close];
        [self setFinishedWithSuccess:NO];
        self.session = nil;
        return nil;
    }
    [self setSession:session withSideEffects:NO];
    if (toggle) {
        DLog(@"toggle");
        [windowController delayedEnterFullscreen];
    }
    [self makeKeyAndActivateIfNeeded:windowController];

    [self setFinishedWithSuccess:YES];
    [self setSession:session withSideEffects:YES];

    return session;
}

- (void)prepareToLaunch {
    DLog(@"Preparing to launch a session.");
    DLog(@"Profile:\n%@", _profile);
    DLog(@"URL: %@", _url);
    DLog(@"hotkey window type: %@", @(_hotkeyWindowType));
    DLog(@"makeKey: %@", @(_makeKey));
    DLog(@"canActivate: %@", @(_canActivate));
    DLog(@"command: %@", _command);
    assert(!_launched);
    _launched = YES;
    _keepAlive = self;
}

- (void)makeKeyAndActivateIfNeeded:(PseudoTerminal *)term {
    DLog(@"called");
    if (!_makeKey) {
        DLog(@"make key off");
        return;
    }
    if ([[term window] isKeyWindow]) {
        DLog(@"already key");
        return;
    }
    // When this function is activated from the dock icon's context menu make sure
    // that the new window is on top of all other apps' windows. For some reason,
    // makeKeyAndOrderFront does nothing.
    if ([term.window isKindOfClass:[iTermPanel class]]) {
        DLog(@"is panel; set canActivate to NO");
        _canActivate = NO;
    }
    if (_canActivate) {
        DLog(@"Activating app");
        // activateIgnoringApp: happens asynchronously which means doing makeKeyAndOrderFront:
        // immediately after it won't do what you want. Issue 6397
        NSWindow *termWindow = [term window];
        [[iTermApplication sharedApplication] activateAppWithCompletion:^{
            DLog(@"App activated. Order window front.");
            [termWindow makeKeyAndOrderFront:nil];
        }];
    } else {
        DLog(@"Order window front");
        [[term window] makeKeyAndOrderFront:nil];
    }
    if (_canActivate) {
        DLog(@"Arrange in front");
        [NSApp arrangeInFront:self];
    }
}

- (void)makeSessionWithProfile:(Profile *)profile
              windowController:(PseudoTerminal *)windowController
                    completion:(void (^)(PTYSession *, BOOL willCallCompletionBlock))completion {
    if (_makeSession) {
        [self makeSessionByBlockWithProfile:profile
                           windowController:windowController
                                 completion:completion];
    } else if (_url) {
        [self makeSessionByURLWithProfile:profile
                         windowController:windowController
                               completion:completion];
    } else {
        [self makeSessionByCreatingTabWithProfile:profile
                                 windowController:windowController
                                       completion:completion];
    }
}

- (void)makeSessionByBlockWithProfile:(Profile *)profile
                     windowController:(PseudoTerminal *)windowController
                           completion:(void (^)(PTYSession *, BOOL willCallCompletionBlock))completion {
    DLog(@"Create a session via callback");
    _makeSession(profile, windowController, ^(PTYSession *session) {
        DLog(@"Created a session: %@", session);
        completion(session, NO);
    });
}

- (void)makeSessionByURLWithProfile:(Profile *)profile
                   windowController:(PseudoTerminal *)windowController
                         completion:(void (^)(PTYSession *, BOOL willCallCompletionBlock))completion {
    DLog(@"Creating a new session by URL: %@", _url);
    PTYSession *session = [windowController.sessionFactory newSessionWithProfile:profile
                                                                          parent:nil];
    const BOOL saved = windowController.automaticallySelectNewTabs;
    windowController.automaticallySelectNewTabs = !self.disableAutomaticTabSelection;
    [windowController addSessionInNewTab:session];
    windowController.automaticallySelectNewTabs = saved;
    __weak __typeof(self) weakSelf = self;

    if ([[NSNumber castFrom:profile[KEY_LOCK_SCROLL_ON_LAUNCH]] boolValue]) {
        // This is the earliest we can do this because the session needs to have a view for it to work.
        [session lockScroll];
    }

    iTermSessionAttachOrLaunchRequest *launchRequest =
    [iTermSessionAttachOrLaunchRequest launchRequestWithSession:session
                                                      canPrompt:YES
                                                     objectType:self.objectType
                                            hasServerConnection:NO
                                               serverConnection:(iTermGeneralServerConnection){}
                                                      urlString:_url
                                                   allowURLSubs:YES
                                                    environment:@{}
                                                    customShell:[ITAddressBookMgr customShellForProfile:profile]
                                                         oldCWD:nil
                                                 forceUseOldCWD:NO
                                                        command:nil
                                                         isUTF8:nil
                                                  substitutions:nil
                                               windowController:windowController
                                                          ready:^(BOOL ok) {
        if (ok) {
            DLog(@"success");
            completion(session, YES);
        } else {
            DLog(@"failure");
            [self setFinishedWithSuccess:NO];
            completion(nil, YES);
        }
    }
                                                     completion:
     ^(PTYSession *newSession, BOOL ok) {
        DLog(@"launch by url finished with ok=%@", @(ok));
        if (@available(macOS 11, *)) {
            [newSession loadDeferredURLIfNeeded];
        }
        [weakSelf setFinishedWithSuccess:ok];
    }];
    [windowController.sessionFactory attachOrLaunchWithRequest:launchRequest];
}

- (void)makeSessionByCreatingTabWithProfile:(Profile *)profile
                           windowController:(PseudoTerminal *)windowController
                                 completion:(void (^)(PTYSession *, BOOL willCallCompletionBlock))completion {
    DLog(@"Make session by creating tab");
    __weak __typeof(self) weakSelf = self;
    const BOOL saved = windowController.automaticallySelectNewTabs;
    windowController.automaticallySelectNewTabs = !self.disableAutomaticTabSelection;
    __weak __typeof(windowController) weakWindowController = windowController;
    [windowController asyncCreateTabWithProfile:profile
                                    withCommand:_command
                                    environment:nil
                                       tabIndex:self.index
                                 didMakeSession:^(PTYSession *session) { completion(session, YES); }
                                completion:^(PTYSession *newSession, BOOL ok) {
        weakWindowController.automaticallySelectNewTabs = saved;
        [weakSelf setFinishedWithSuccess:ok]; }]
    ;
}

- (NSDictionary *)profile:(NSDictionary *)aDict
        modifiedToOpenURL:(NSString *)url
            forObjectType:(iTermObjectType)objectType {
    const BOOL browser = [aDict[KEY_CUSTOM_COMMAND] isEqualToString:kProfilePreferenceCommandTypeBrowserValue];
    if (browser) {
        MutableProfile *temp = [aDict mutableCopy];
        temp[KEY_INITIAL_URL] = url;
        return temp;
    }
    const BOOL custom = [aDict[KEY_CUSTOM_COMMAND] isEqualToString:kProfilePreferenceCommandTypeCustomValue];
    if (aDict == nil ||
        [[ITAddressBookMgr bookmarkCommandSwiftyString:aDict
                                         forObjectType:objectType] isEqualToString:@"$$"] ||
        !custom) {
        Profile *prototype = aDict;
        if (!prototype) {
            prototype = [[iTermController sharedInstance] defaultBookmark];
        }

        NSURL *urlRep = [NSURL URLWithString:url];
        NSString *urlType = [urlRep scheme];
        DLog(@"urlType=%@", urlType);
        if ([urlType compare:@"ssh" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            return [self profileByModifyingProfile:prototype toSshTo:urlRep];
        } else if ([urlType compare:@"ftp" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            return [self profileByModifyingProfile:prototype toFtpTo:url];
        } else if ([urlType compare:@"telnet" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            return [self profileByModifyingProfile:prototype toTelnetTo:urlRep];
        } else if ([urlType compare:@"x-man-page" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            return [self profileByModifyingProfile:prototype toShowManPage:urlRep];
        } else if (!aDict) {
            return [prototype copy];
        } else {
            return prototype;
        }
    } else {
        DLog(@"no subs");
        return aDict;
    }
}

- (NSString *)validatedAndShellEscapedUsername:(NSString *)username {
    return [username sanitizedUsername];
}

- (NSString *)validatedAndShellEscapedHostname:(NSString *)hostname {
    return [hostname sanitizedHostname];
}

- (NSString *)sanitizedCommand:(NSString *)unsafeCommand {
    return [unsafeCommand sanitizedCommand];
}

- (Profile *)profileByModifyingProfile:(NSDictionary *)prototype toShowManPage:(NSURL *)url {
    DLog(@"Modify profile to show man page for url %@", url);
    // https://github.com/ouspg/urlhandlers/blob/master/cases/x-man-page.md
    // host = section, path = page         -> login -pfq fenris /usr/bin/man -P ul -S mysection mypage
    // host = section, path = page; type=a -> login -pfq fenris /usr/bin/man -P cat -k -S mysection pattern
    NSArray<NSString *> *parts = [url.path componentsSeparatedByString:@";"];
    NSString *command = nil;
    if ([parts.lastObject isEqualToString:@"type=a"]) {
        // x-man-page:///<query>;type=a
        // Apropos
        command = [NSString stringWithFormat:@"login -pfq %@ /usr/bin/man -P cat -k %@",
                   NSUserName(),
                   [self sanitizedCommand:[parts[0] stringByRemovingPrefix:@"/"]]];
    } else {
        if (url.host.length) {
            // x-man-page://<section>/<command>
            command = [NSString stringWithFormat:@"login -pfq %@ /usr/bin/man -P ul -S %@ %@",
                       NSUserName(),
                       [self sanitizedCommand:url.host],
                       [self sanitizedCommand:url.path]];
        } else {
            // x-man-page:///<command>
            command = [NSString stringWithFormat:@"login -pfq %@ /usr/bin/man -P ul %@",
                       NSUserName(),
                       [self sanitizedCommand:url.path]];
        }
    }
    return [prototype dictionaryByMergingDictionary:@{ KEY_COMMAND_LINE: command,
                                                       KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeCustomValue,
                                                       KEY_SESSION_END_ACTION: @(iTermSessionEndActionDefault),
                                                       KEY_INITIAL_TEXT: @"",
                                                       KEY_SHORT_LIVED_SINGLE_USE: @YES,
                                                       KEY_LOCK_SCROLL_ON_LAUNCH: @YES,
                                                       KEY_UNLIMITED_SCROLLBACK: @YES,
                                                       KEY_MOVEMENT_KEYS_SCROLL_OUTSIDE_INTERACTIVE_APPS: @YES
                                                    }];
}

- (Profile *)profileByModifyingProfile:(NSDictionary *)prototype toSshTo:(NSURL *)url {
    DLog(@"modify profile to ssh to %@", url);
    NSMutableString *tempString = [NSMutableString string];
    const BOOL useSSHIntegration = [iTermPreferences boolForKey:kPreferenceKeySshIntegrationForURLs];
    if (!useSSHIntegration) {
        [tempString appendString:[iTermAdvancedSettingsModel sshSchemePath]];
        NSCharacterSet *alphanumericSet = [NSMutableCharacterSet alphanumericCharacterSet];
        if ([tempString rangeOfCharacterFromSet:alphanumericSet].location == NSNotFound) {
            // if the setting is set to an empty string, we will default to "ssh" for safety reasons
            tempString = [NSMutableString stringWithString:@"ssh"];
        }
        [tempString appendString:@" "];
    }
    NSString *username = url.user;
    BOOL cd = ([iTermAdvancedSettingsModel sshURLsSupportPath] && url.path.length > 1);
    if (username) {
        NSString *part = [self validatedAndShellEscapedUsername:username];
        if (!part) {
            NSString *message = [NSString stringWithFormat:@"The SSH user name “%@” contained a disallowed character. The set of allowed characters is limited for security reasons. You can modify it in Settings > Advanced > Valid characters in SSH user names.",
                                 username];
            [iTermWarning showWarningWithTitle:message
                                       actions:@[ @"OK" ]
                                     accessory:nil
                                    identifier:nil
                                   silenceable:kiTermWarningTypePersistent
                                       heading:@"Illegal Username"
                                        window:nil];
            DLog(@"bad username");
            return nil;
        }
        [tempString appendFormat:@"-l %@ ", part];
    }
    if (url.port) {
        [tempString appendFormat:@"-p %@ ", url.port];
    }
    if (cd) {
        // Force a TTY since we're providing a command
        [tempString appendString:@"-t "];
    }
    NSString *hostname = url.host;
    if (hostname) {
        NSString *part = [self validatedAndShellEscapedHostname:hostname];
        if (!part) {
            DLog(@"Bad hostname");
            return nil;
        }
        [tempString appendString:part];
    }
    if (cd) {
        NSString *path = url.path;
        if ([path hasPrefix:@"/~"]) {
            path = [path substringFromIndex:1];
        }
        NSCharacterSet *unsafeCharacters = [NSCharacterSet characterSetWithCharactersInString:@"\"'\\\r\n\0"];
        if ([path rangeOfCharacterFromSet:unsafeCharacters].location == NSNotFound) {
            [tempString appendFormat:@" \"cd %@; exec \\$SHELL -l\"", [path stringWithEscapedShellCharactersIncludingNewlines:YES]];
        }
    }
    DLog(@"Use command line: %@", tempString);
    if (useSSHIntegration) {
        return [prototype dictionaryByMergingDictionary:@{ KEY_COMMAND_LINE: tempString,
                                                           KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeSSHValue }];
    } else {
        return [prototype dictionaryByMergingDictionary:@{ KEY_COMMAND_LINE: tempString,
                                                           KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeCustomValue }];
    }
}

- (Profile *)profileByModifyingProfile:(Profile *)prototype toFtpTo:(NSString *)url {
    NSMutableString *tempString = [NSMutableString stringWithFormat:@"%@ %@", [iTermAdvancedSettingsModel pathToFTP], url];
    DLog(@"Command line is %@", tempString);
    return [prototype dictionaryByMergingDictionary:@{ KEY_COMMAND_LINE: tempString,
                                                       KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeCustomValue }];
}

- (Profile *)profileByModifyingProfile:(NSDictionary *)prototype toTelnetTo:(NSURL *)url {
    NSMutableString *tempString = [NSMutableString stringWithFormat:@"%@ ", [iTermAdvancedSettingsModel pathToTelnet]];
    if (url.user) {
        NSString *part = [self validatedAndShellEscapedUsername:url.user];
        if (!part) {
            return nil;
        }
        [tempString appendFormat:@"-l %@ ", part];
    }
    if (url.host) {
        NSString *part = [self validatedAndShellEscapedHostname:url.host];
        if (!part) {
            return nil;
        }
        [tempString appendString:part];
    }
    if (url.port) {
        [tempString appendFormat:@" %@", url.port];
    }
    DLog(@"Command line is %@", tempString);
    return [prototype dictionaryByMergingDictionary:@{ KEY_COMMAND_LINE: tempString,
                                                       KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeCustomValue }];
}


- (Profile *)modifiedProfile {
    NSDictionary *profile = _profile;
    if (profile == nil) {
        DLog(@"Using default profile");
        profile = [[iTermController sharedInstance] defaultBookmark];
    }

    if (_url) {
        DLog(@"Add URL to profile");
        // Automatically fill in ssh command if command is exactly equal to $$ or it's a login shell.
        profile = [self profile:profile modifiedToOpenURL:_url forObjectType:self.objectType];
        if (profile == nil) {
            // Bogus hostname detected
            return nil;
        }
    }
    if (!_profile) {
        DLog(@"Using profile:\n%@", profile);
    }
    return profile;
}

- (iTermObjectType)objectType {
    if (_windowController) {
        return iTermTabObject;
    }
    return iTermWindowObject;
}

- (PseudoTerminal *)possiblyNewWindowControllerForProfile:(Profile *)profile
                                         toggleFullScreen:(BOOL *)togglePtr {
    PseudoTerminal *windowController = [[iTermController sharedInstance] windowControllerForNewTabWithProfile:profile
                                                                                                    candidate:_windowController
                                                                                           respectTabbingMode:_respectTabbingMode];
    *togglePtr = NO;
    if (windowController != nil && [windowController windowInitialized]) {
        DLog(@"Use an existing window");
        return windowController;
    }

    [iTermController switchToSpaceInBookmark:profile];
    int windowType = [[iTermController sharedInstance] windowTypeForBookmark:profile];
    if (self.isHotkey && windowType == WINDOW_TYPE_LION_FULL_SCREEN) {
        DLog(@"Convert lion to traditional fullscreen because hotkey window");
        windowType = WINDOW_TYPE_TRADITIONAL_FULL_SCREEN;
    }
    if (windowController) {
        DLog(@"Theoretically unreachable code path reached!");
        // TODO: This code path might be unreachable. It was originally added in
        // fb845ffbc908ffbb3b7b57c35b881eab0f87a01e to deal with the crazy way applescript creates
        // windows separately from tabs, but that is no longer possible.
        DLog(@"Finish initialization of an existing window controller");
        [windowController finishInitializationWithSmartLayout:YES
                                                   windowType:windowType
                                              savedWindowType:iTermWindowDefaultType()
                                                       screen:profile[KEY_SCREEN] ? [profile[KEY_SCREEN] intValue] : -1
                                             hotkeyWindowType:_hotkeyWindowType
                                                      profile:profile];
    } else {
        DLog(@"Create a new window controller");
        windowController = [[PseudoTerminal alloc] initWithSmartLayout:YES
                                                            windowType:windowType
                                                       savedWindowType:windowType
                                                                screen:profile[KEY_SCREEN] ? [profile[KEY_SCREEN] intValue] : -1
                                                      hotkeyWindowType:_hotkeyWindowType
                                                               profile:profile];
    }
    if ([profile[KEY_HIDE_AFTER_OPENING] boolValue]) {
        DLog(@"hide after opening");
        [windowController hideAfterOpening];
    }
    [[iTermController sharedInstance] addTerminalWindow:windowController];
    if (self.isHotkey) {
        // Hotkey windows can't use Lion fullscreen.
        *togglePtr = NO;
    } else {
        *togglePtr = ([windowController windowType] == WINDOW_TYPE_LION_FULL_SCREEN);
    }

    return windowController;
}

- (BOOL)isHotkey {
    return _hotkeyWindowType != iTermHotkeyWindowTypeNone;
}

- (void)setSession:(PTYSession *)session {
    [self setSession:session withSideEffects:YES];
}

- (void)setSession:(PTYSession *)session withSideEffects:(BOOL)sideEffects {
    DLog(@"setSession:%@ withSideEffects:%@", session, @(sideEffects));
    _session = session;
    if (!sideEffects) {
        return;
    }
    assert(!_haveSetSession);

    _haveSetSession = YES;
    if (_didCreateSession) {
        _didCreateSession(session);
    }
    [self maybeBreakRetainCycle];
}

- (void)setFinishedWithSuccess:(BOOL)ok {
    DLog(@"setFinishedWithSuccess:%@", @(ok));
    if (_finished) {
        return;
    }
    _finished = YES;
    if (_completion) {
        // Ensure the completion block runs after the caller returns for better consistency.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.completion) {
                self.completion(self.session, ok);
            }
        });
    }
    [self maybeBreakRetainCycle];
}

- (void)maybeBreakRetainCycle {
    if (_haveSetSession & _finished) {
        DLog(@"Break retain cycle");
        _keepAlive = nil;
    }
}

@end
