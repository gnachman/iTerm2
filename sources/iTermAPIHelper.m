//
//  iTermAPIHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/18/18.
//

#import "iTermAPIHelper.h"

#import "DebugLogging.h"
#import "iTermLSOF.h"
#import "MovePaneController.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"

static NSString *const kBundlesWithAPIAccessSettingKey = @"NoSyncBundlesWithAPIAccessSettings";
NSString *const iTermRemoveAPIServerSubscriptionsNotification = @"iTermRemoveAPIServerSubscriptionsNotification";

static NSString *const kAPIAccessAllowed = @"allowed";
static NSString *const kAPIAccessDate = @"date";
static NSString *const kAPINextConfirmationDate = @"next confirmation";
static NSString *const kAPIAccessLocalizedName = @"app name";
static const NSTimeInterval kOneMonth = 30 * 24 * 60 * 60;

@implementation iTermAPIHelper {
    iTermAPIServer *_apiServer;
    BOOL _layoutChanged;
    NSMutableDictionary<id, ITMNotificationRequest *> *_newSessionSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_terminateSessionSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_layoutChangeSubscriptions;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _apiServer = [[iTermAPIServer alloc] init];
        _apiServer.delegate = self;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(sessionDidTerminate:)
                                                     name:PTYSessionTerminatedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(sessionCreated:)
                                                     name:PTYSessionCreatedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(sessionCreated:)
                                                     name:PTYSessionRevivedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(layoutChanged:)
                                                     name:iTermSessionDidChangeTabNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(layoutChanged:)
                                                     name:iTermTabDidChangeWindowNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(layoutChanged:)
                                                     name:iTermTabDidChangePositionInWindowNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)postAPINotification:(ITMNotification *)notification toConnection:(id)connection {
    [_apiServer postAPINotification:notification toConnection:connection];
}

- (void)sessionCreated:(NSNotification *)notification {
    PTYSession *session = notification.object;
    [_newSessionSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        ITMNotification *notification = [[ITMNotification alloc] init];
        notification.newSessionNotification = [[ITMNewSessionNotification alloc] init];
        notification.newSessionNotification.uniqueIdentifier = session.guid;
        [self postAPINotification:notification toConnection:key];
    }];
}

- (void)sessionDidTerminate:(NSNotification *)notification {
    PTYSession *session = notification.object;
    [_terminateSessionSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        ITMNotification *notification = [[ITMNotification alloc] init];
        notification.terminateSessionNotification = [[ITMTerminateSessionNotification alloc] init];
        notification.terminateSessionNotification.uniqueIdentifier = session.guid;
        [self postAPINotification:notification toConnection:key];
    }];
}

- (void)layoutChanged:(NSNotification *)notification {
    if (!_layoutChanged) {
        _layoutChanged = YES;
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf handleLayoutChange];
        });
    }
}

- (void)handleLayoutChange {
    _layoutChanged = NO;
    [_layoutChangeSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        ITMNotification *notification = [[ITMNotification alloc] init];
        notification.layoutChangedNotification.listSessionsResponse = [self newListSessionsResponse];
        [self postAPINotification:notification toConnection:key];
    }];
}

#pragma mark - iTermAPIServerDelegate

- (NSDictionary *)apiServerAuthorizeProcess:(pid_t)pid reason:(out NSString *__autoreleasing *)reason displayName:(out NSString *__autoreleasing *)displayName {
    *displayName = nil;
    NSMutableDictionary *bundles = [[[NSUserDefaults standardUserDefaults] objectForKey:kBundlesWithAPIAccessSettingKey] mutableCopy];
    if (!bundles) {
        bundles = [NSMutableDictionary dictionary];
    }

    NSString *processName = nil;
    NSString *processIdentifier = nil;
    NSString *processIdentifierWithoutArgs = nil;

    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (app.localizedName && app.bundleIdentifier) {
        processName = app.localizedName;
        processIdentifier = app.bundleIdentifier;
    } else {
        NSString *execName = nil;
        processIdentifier = [iTermLSOF commandForProcess:pid execName:&execName];
        if (!execName || !processIdentifier) {
            *reason = [NSString stringWithFormat:@"Could not identify name for process with pid %d", (int)pid];
            return nil;
        }

        NSArray<NSString *> *parts = [processIdentifier componentsInShellCommand];
        NSString *maybePython = parts.firstObject.lastPathComponent;

        if ([maybePython isEqualToString:@"python"] ||
            [maybePython isEqualToString:@"python3.6"] ||
            [maybePython isEqualToString:@"python3"]) {
            if (parts.count > 1) {
                processName = [parts[1] lastPathComponent];
                processIdentifierWithoutArgs = [[parts subarrayWithRange:NSMakeRange(0, 2)] componentsJoinedByString:@" "];
            }
        }
        if (!processName) {
            processName = execName.lastPathComponent;
            processIdentifierWithoutArgs = execName;
        }
    }
    *displayName = processName;

    NSDictionary *authorizedIdentity = @{ iTermWebSocketConnectionPeerIdentityBundleIdentifier: processIdentifierWithoutArgs };
    NSString *key = [NSString stringWithFormat:@"bundle=%@", processIdentifierWithoutArgs];
    NSDictionary *setting = bundles[key];
    BOOL reauth = NO;
    if (setting) {
        if (![setting[kAPIAccessAllowed] boolValue]) {
            // Access permanently disallowed.
            *reason = [NSString stringWithFormat:@"Access permanently disallowed by user preference to %@", processIdentifier];
            return nil;
        }

        NSString *name = setting[kAPIAccessLocalizedName];
        if ([processName isEqualToString:name]) {
            // Access is permanently allowed and the display name is unchanged. Do we need to reauth?

            NSDate *confirm = setting[kAPINextConfirmationDate];
            if ([[NSDate date] compare:confirm] == NSOrderedAscending) {
                // No need to reauth, allow it.
                *reason = [NSString stringWithFormat:@"Allowing continued API access to process id %d, name %@, bundle ID %@. User gave consent recently.", pid, processName, processIdentifier];
                return authorizedIdentity;
            }

            // It's been a month since API access was confirmed. Request it again.
            reauth = YES;
        }
    }
    NSAlert *alert = [[NSAlert alloc] init];
    if (reauth) {
        alert.messageText = @"Reauthorize API Access";
        alert.informativeText = [NSString stringWithFormat:@"The application “%@” (%@) has API access, which grants it permission to see and control your activity. Would you like it to continue?", processName, processIdentifier];
    } else {
        alert.messageText = @"API Access Request";
        alert.informativeText = [NSString stringWithFormat:@"The application “%@” (%@) would like to control iTerm2. This exposes a significant amount of data in iTerm2 to %@. Allow this request?", processName, processIdentifier, processName];
    }
    [alert addButtonWithTitle:@"Deny"];
    [alert addButtonWithTitle:@"Allow"];
    if (!reauth) {
        // Reauth is always persistent so don't show the button.
        alert.suppressionButton.title = @"Remember my selection";
        alert.showsSuppressionButton = YES;
    }
    NSModalResponse response = [alert runModal];
    BOOL allow = (response == NSAlertSecondButtonReturn);

    if (reauth || alert.suppressionButton.state == NSOnState) {
        bundles[key] = @{ kAPIAccessAllowed: @(allow),
                          kAPIAccessDate: [NSDate date],
                          kAPINextConfirmationDate: [[NSDate date] dateByAddingTimeInterval:kOneMonth],
                          kAPIAccessLocalizedName: processName };
    } else {
        [bundles removeObjectForKey:key];
    }
    [[NSUserDefaults standardUserDefaults] setObject:bundles forKey:kBundlesWithAPIAccessSettingKey];

    *reason = allow ? [NSString stringWithFormat:@"User accepted connection by %@", processIdentifier] : [NSString stringWithFormat:@"User rejected connection attempt by %@", processIdentifier];
    return allow ? authorizedIdentity : nil;
}

- (PTYSession *)sessionForAPIIdentifier:(NSString *)identifier {
    if (identifier) {
        for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
            for (PTYSession *session in term.allSessions) {
                if ([session.guid isEqualToString:identifier]) {
                    return session;
                }
            }
        }
        return nil;
    } else {
        return [[[iTermController sharedInstance] currentTerminal] currentSession];
    }
}

- (void)apiServerGetBuffer:(ITMGetBufferRequest *)request
                   handler:(void (^)(ITMGetBufferResponse *))handler {
    PTYSession *session = [self sessionForAPIIdentifier:request.hasSession ? request.session : nil];
    if (!session) {
        ITMGetBufferResponse *response = [[ITMGetBufferResponse alloc] init];
        response.status = ITMGetBufferResponse_Status_SessionNotFound;
        handler(response);
    } else {
        handler([session handleGetBufferRequest:request]);
    }
}

- (void)apiServerGetPrompt:(ITMGetPromptRequest *)request
                   handler:(void (^)(ITMGetPromptResponse *))handler {
    PTYSession *session = [self sessionForAPIIdentifier:request.hasSession ? request.session : nil];
    if (!session) {
        ITMGetPromptResponse *response = [[ITMGetPromptResponse alloc] init];
        response.status = ITMGetPromptResponse_Status_SessionNotFound;
        handler(response);
    } else {
        handler([session handleGetPromptRequest:request]);
    }
}

- (ITMNotificationResponse *)handleAPINotificationRequest:(ITMNotificationRequest *)request connection:(id)connection {
    ITMNotificationResponse *response = [[ITMNotificationResponse alloc] init];
    if (!request.hasSubscribe) {
        response.status = ITMNotificationResponse_Status_RequestMalformed;
        return response;
    }
    if (!_newSessionSubscriptions) {
        _newSessionSubscriptions = [[NSMutableDictionary alloc] init];
        _terminateSessionSubscriptions = [[NSMutableDictionary alloc] init];
        _layoutChangeSubscriptions = [[NSMutableDictionary alloc] init];
    }
    NSMutableDictionary<id, ITMNotificationRequest *> *subscriptions;
    if (request.notificationType == ITMNotificationType_NotifyOnNewSession) {
        subscriptions = _newSessionSubscriptions;
    } else if (request.notificationType == ITMNotificationType_NotifyOnTerminateSession) {
        subscriptions = _terminateSessionSubscriptions;
    } else if (request.notificationType == ITMNotificationType_NotifyOnLayoutChange) {
        subscriptions = _layoutChangeSubscriptions;
    } else {
        assert(false);
    }
    if (request.subscribe) {
        if (subscriptions[connection]) {
            response.status = ITMNotificationResponse_Status_AlreadySubscribed;
            return response;
        }
        subscriptions[connection] = request;
    } else {
        if (!subscriptions[connection]) {
            response.status = ITMNotificationResponse_Status_NotSubscribed;
            return response;
        }
        [subscriptions removeObjectForKey:connection];
    }

    response.status = ITMNotificationResponse_Status_Ok;
    return response;
}

- (void)apiServerNotification:(ITMNotificationRequest *)request
                   connection:(id)connection
                      handler:(void (^)(ITMNotificationResponse *))handler {
    if (request.notificationType == ITMNotificationType_NotifyOnNewSession ||
        request.notificationType == ITMNotificationType_NotifyOnTerminateSession |
        request.notificationType == ITMNotificationType_NotifyOnLayoutChange) {
        handler([self handleAPINotificationRequest:request connection:connection]);
    } else {
        PTYSession *session = [self sessionForAPIIdentifier:request.hasSession ? request.session : nil];
        if (!session) {
            ITMNotificationResponse *response = [[ITMNotificationResponse alloc] init];
            response.status = ITMNotificationResponse_Status_SessionNotFound;
            handler(response);
        } else {
            handler([session handleAPINotificationRequest:request connection:connection]);
        }
    }
}

- (void)apiServerRemoveSubscriptionsForConnection:(id)connection {
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermRemoveAPIServerSubscriptionsNotification object:connection];
}

- (void)apiServerRegisterTool:(ITMRegisterToolRequest *)request
                 peerIdentity:(NSDictionary *)peerIdentity
                      handler:(void (^)(ITMRegisterToolResponse *))handler {
    ITMRegisterToolResponse *response = [[ITMRegisterToolResponse alloc] init];
    if (!request.hasName || !request.hasIdentifier || !request.hasURL) {
        response.status = ITMRegisterToolResponse_Status_RequestMalformed;
        handler(response);
        return;
    }
    NSURL *url = [NSURL URLWithString:request.URL];
    if (!url || !url.host) {
        response.status = ITMRegisterToolResponse_Status_RequestMalformed;
        handler(response);
        return;
    }

    if ([[iTermToolbeltView builtInToolNames] containsObject:request.name]) {
        response.status = ITMRegisterToolResponse_Status_PermissionDenied;
        handler(response);
        return;
    }

    [iTermToolbeltView registerDynamicToolWithIdentifier:request.identifier
                                                    name:request.name
                                                     URL:request.URL
                               revealIfAlreadyRegistered:request.revealIfAlreadyRegistered];
    response.status = ITMRegisterToolResponse_Status_Ok;
    handler(response);
}

- (void)apiServerSetProfileProperty:(ITMSetProfilePropertyRequest *)request
                            handler:(void (^)(ITMSetProfilePropertyResponse *))handler {
    PTYSession *session = [self sessionForAPIIdentifier:request.hasSession ? request.session : nil];
    if (!session) {
        ITMSetProfilePropertyResponse *response = [[ITMSetProfilePropertyResponse alloc] init];
        response.status = ITMSetProfilePropertyResponse_Status_SessionNotFound;
        handler(response);
        return;
    }

    NSError *error = nil;
    id value = [NSJSONSerialization JSONObjectWithData:[request.jsonValue dataUsingEncoding:NSUTF8StringEncoding]
                                               options:NSJSONReadingAllowFragments
                                                 error:&error];
    if (!value || error) {
        XLog(@"JSON parsing error %@ for value in request %@", error, request);
        ITMSetProfilePropertyResponse *response = [[ITMSetProfilePropertyResponse alloc] init];
        response.status = ITMSetProfilePropertyResponse_Status_RequestMalformed;
        handler(response);
    }

    handler([session handleSetProfilePropertyForKey:request.key value:value]);
}

- (void)apiServerGetProfileProperty:(ITMGetProfilePropertyRequest *)request
                            handler:(void (^)(ITMGetProfilePropertyResponse *))handler {
    PTYSession *session = [self sessionForAPIIdentifier:request.hasSession ? request.session : nil];
    if (!session) {
        ITMGetProfilePropertyResponse *response = [[ITMGetProfilePropertyResponse alloc] init];
        response.status = ITMGetProfilePropertyResponse_Status_SessionNotFound;
        handler(response);
        return;
    }

    handler([session handleGetProfilePropertyForKeys:request.keysArray]);
}

- (void)apiServerListSessions:(ITMListSessionsRequest *)request
                      handler:(void (^)(ITMListSessionsResponse *))handler {
    handler([self newListSessionsResponse]);
}

- (ITMListSessionsResponse *)newListSessionsResponse {
    ITMListSessionsResponse *response = [[ITMListSessionsResponse alloc] init];
    for (PseudoTerminal *window in [[iTermController sharedInstance] terminals]) {
        ITMListSessionsResponse_Window *windowMessage = [[ITMListSessionsResponse_Window alloc] init];
        windowMessage.windowId = window.terminalGuid;
        NSRect frame = window.window.frame;
        windowMessage.frame.origin.x = frame.origin.x;
        windowMessage.frame.origin.y = frame.origin.y;
        windowMessage.frame.size.width = frame.size.width;
        windowMessage.frame.size.height = frame.size.height;

        for (PTYTab *tab in window.tabs) {
            ITMListSessionsResponse_Tab *tabMessage = [[ITMListSessionsResponse_Tab alloc] init];
            tabMessage.tabId = [@(tab.uniqueId) stringValue];
            tabMessage.root = [tab rootSplitTreeNode];
            [windowMessage.tabsArray addObject:tabMessage];
        }

        [response.windowsArray addObject:windowMessage];
    }
    return response;
}

- (void)apiServerSendText:(ITMSendTextRequest *)request handler:(void (^)(ITMSendTextResponse *))handler {
    PTYSession *session = [self sessionForAPIIdentifier:request.hasSession ? request.session : nil];
    if (!session || session.exited) {
        ITMSendTextResponse *response = [[ITMSendTextResponse alloc] init];
        response.status = ITMSendTextResponse_Status_SessionNotFound;
        handler(response);
        return;
    }
    [session writeTask:request.text];
    ITMSendTextResponse *response = [[ITMSendTextResponse alloc] init];
    response.status = ITMSendTextResponse_Status_Ok;
    handler(response);
}

- (void)apiServerCreateTab:(ITMCreateTabRequest *)request handler:(void (^)(ITMCreateTabResponse *))handler {
    PseudoTerminal *term = nil;
    if (request.hasWindowId) {
        term = [[iTermController sharedInstance] terminalWithGuid:request.windowId];
        if (!term) {
            ITMCreateTabResponse *response = [[ITMCreateTabResponse alloc] init];
            response.status = ITMCreateTabResponse_Status_InvalidWindowId;
            handler(response);
            return;
        }
    }

    Profile *profile = [[ProfileModel sharedInstance] defaultBookmark];
    if (request.hasProfileName) {
        profile = [[ProfileModel sharedInstance] bookmarkWithName:request.profileName];
        if (!profile) {
            ITMCreateTabResponse *response = [[ITMCreateTabResponse alloc] init];
            response.status = ITMCreateTabResponse_Status_InvalidProfileName;
            handler(response);
            return;
        }
    }

    PTYSession *session = [[iTermController sharedInstance] launchBookmark:profile
                                                                inTerminal:term
                                                                   withURL:nil
                                                          hotkeyWindowType:iTermHotkeyWindowTypeNone
                                                                   makeKey:YES
                                                               canActivate:YES
                                                                   command:request.hasCommand ? request.command : nil
                                                                     block:nil];
    if (!session) {
        ITMCreateTabResponse *response = [[ITMCreateTabResponse alloc] init];
        response.status = ITMCreateTabResponse_Status_MissingSubstitution;
        handler(response);
        return;
    }

    term = [[iTermController sharedInstance] terminalWithSession:session];
    PTYTab *tab = [term tabForSession:session];

    ITMCreateTabResponse_Status status = ITMCreateTabResponse_Status_Ok;

    if (request.hasTabIndex) {
        NSInteger sourceIndex = [term indexOfTab:tab];
        if (term.numberOfTabs > request.tabIndex && sourceIndex != NSNotFound) {
            [term.tabBarControl moveTabAtIndex:sourceIndex toIndex:request.tabIndex];
        } else {
            status = ITMCreateTabResponse_Status_InvalidTabIndex;
        }
    }

    ITMCreateTabResponse *response = [[ITMCreateTabResponse alloc] init];
    response.status = status;
    response.windowId = term.terminalGuid;
    response.tabId = tab.uniqueId;
    response.sessionId = session.guid;
    handler(response);
}

- (void)apiServerSplitPane:(ITMSplitPaneRequest *)request handler:(void (^)(ITMSplitPaneResponse *))handler {
    PTYSession *session = [self sessionForAPIIdentifier:request.hasSession ? request.session : nil];
    PseudoTerminal *term = session ? [[iTermController sharedInstance] terminalWithSession:session] : nil;
    if (!term || !session || session.exited) {
        ITMSplitPaneResponse *response = [[ITMSplitPaneResponse alloc] init];
        response.status = ITMSplitPaneResponse_Status_SessionNotFound;
        handler(response);
        return;
    }

    Profile *profile = [[ProfileModel sharedInstance] defaultBookmark];
    if (request.hasProfileName) {
        profile = [[ProfileModel sharedInstance] bookmarkWithName:request.profileName];
        if (!profile) {
            ITMSplitPaneResponse *response = [[ITMSplitPaneResponse alloc] init];
            response.status = ITMSplitPaneResponse_Status_InvalidProfileName;
            handler(response);
            return;
        }
    }

    PTYSession *newSession = [term splitVertically:request.splitDirection == ITMSplitPaneRequest_SplitDirection_Vertical
                                            before:request.before
                                           profile:profile
                                     targetSession:session];
    if (newSession == nil && !session.isTmuxClient) {
        ITMSplitPaneResponse *response = [[ITMSplitPaneResponse alloc] init];
        response.status = ITMSplitPaneResponse_Status_CannotSplit;
        handler(response);
        return;
    }

    ITMSplitPaneResponse *response = [[ITMSplitPaneResponse alloc] init];
    response.status = ITMSplitPaneResponse_Status_Ok;
    if (newSession != nil) {
        response.sessionId = newSession.guid;
    }
    handler(response);
}

@end
