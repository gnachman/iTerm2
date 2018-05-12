//
//  iTermAPIHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/18/18.
//

#import "iTermAPIHelper.h"

#import "CVector.h"
#import "DebugLogging.h"
#import "iTermAPIAuthorizationController.h"
#import "iTermController.h"
#import "iTermDisclosableView.h"
#import "iTermLSOF.h"
#import "iTermPythonArgumentParser.h"
#import "MovePaneController.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "VT100Parser.h"

NSString *const iTermRemoveAPIServerSubscriptionsNotification = @"iTermRemoveAPIServerSubscriptionsNotification";

@interface iTermAllSessionsSubscription : NSObject
@property (nonatomic, strong) ITMNotificationRequest *request;
@property (nonatomic, strong) id connection;
@end

@implementation iTermAllSessionsSubscription
@end

@implementation iTermAPIHelper {
    iTermAPIServer *_apiServer;
    BOOL _layoutChanged;
    NSMutableDictionary<id, ITMNotificationRequest *> *_newSessionSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_terminateSessionSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_layoutChangeSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_focusChangeSubscriptions;
    NSMutableArray<iTermAllSessionsSubscription *> *_allSessionsSubscriptions;
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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidResignActive:)
                                                     name:NSApplicationDidResignActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidBecomeKey:)
                                                     name:NSWindowDidBecomeKeyNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidResignKey:)
                                                     name:NSWindowDidResignKeyNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(selectedTabDidChange:)
                                                     name:iTermSelectedTabDidChange
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(activeSessionDidChange:)
                                                     name:iTermSessionBecameKey
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
    for (iTermAllSessionsSubscription *sub in _allSessionsSubscriptions) {
        [self handleAPINotificationRequest:sub.request connection:sub.connection];
    }

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

/*
 oneof event {
 // true: application became active. false: application resigned active.
 bool application_active = 1;

 // true: window became key. false: window resigned key.
 bool window_key = 2;

 // If set, selected tab changed to the one identified herein.
 Tab selected_tab = 3;

 // If set, the given session became active in its tab.
 string session = 4;
 }
*/

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    ITMFocusChangedNotification *focusChange = [[ITMFocusChangedNotification alloc] init];
    focusChange.applicationActive = YES;
    [self handleFocusChange:focusChange];
}

- (void)applicationDidResignActive:(NSNotification *)notification {
    ITMFocusChangedNotification *focusChange = [[ITMFocusChangedNotification alloc] init];
    focusChange.applicationActive = NO;
    [self handleFocusChange:focusChange];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    ITMFocusChangedNotification *focusChange = [[ITMFocusChangedNotification alloc] init];
    NSWindow *window = notification.object;
    PseudoTerminal *term = [[iTermController sharedInstance] terminalForWindow:window];
    focusChange.window = [[ITMFocusChangedNotification_Window alloc] init];
    if (term) {
        focusChange.window.windowId = term.terminalGuid;
        focusChange.window.windowStatus = ITMFocusChangedNotification_Window_WindowStatus_TerminalWindowBecameKey;
    } else {
        term = [[iTermController sharedInstance] currentTerminal];
        if (!term) {
            // Non-terminal window became key and no terminal is current (e.g., you opened prefs).
            // Not very interesting.
            return;
        }
        focusChange.window.windowId = [term terminalGuid];
        focusChange.window.windowStatus = ITMFocusChangedNotification_Window_WindowStatus_TerminalWindowIsCurrent;
    }
    [self handleFocusChange:focusChange];
}

- (void)windowDidResignKey:(NSNotification *)notification {
    ITMFocusChangedNotification *focusChange = [[ITMFocusChangedNotification alloc] init];
    NSWindow *window = notification.object;
    PseudoTerminal *term = [[iTermController sharedInstance] terminalForWindow:window];
    if (window && term) {
        focusChange.window = [[ITMFocusChangedNotification_Window alloc] init];
        focusChange.window.windowId = term.terminalGuid;
        focusChange.window.windowStatus = ITMFocusChangedNotification_Window_WindowStatus_TerminalWindowResignedKey;
        [self handleFocusChange:focusChange];
    }
}

- (void)selectedTabDidChange:(NSNotification *)notification {
    PTYTab *tab = notification.object;
    ITMFocusChangedNotification *focusChange = [[ITMFocusChangedNotification alloc] init];
    focusChange.selectedTab = [@(tab.uniqueId) stringValue];
    [self handleFocusChange:focusChange];
}

- (void)activeSessionDidChange:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSNumber *changed = userInfo[@"changed"];
    if (changed && !changed.boolValue) {
        return;
    }
    PTYSession *session = notification.object;
    ITMFocusChangedNotification *focusChange = [[ITMFocusChangedNotification alloc] init];
    focusChange.session = session.guid;
    [self handleFocusChange:focusChange];
}

- (void)handleFocusChange:(ITMFocusChangedNotification *)notif {
    [_focusChangeSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        ITMNotification *notification = [[ITMNotification alloc] init];
        notification.focusChangedNotification = notif;
        [self postAPINotification:notification toConnection:key];
    }];
}

#pragma mark - iTermAPIServerDelegate

- (BOOL)askUserToGrantAuthForController:(iTermAPIAuthorizationController *)controller
                      isReauthorization:(BOOL)reauth
                               remember:(out BOOL *)remember {
    NSAlert *alert = [[NSAlert alloc] init];
    if (reauth) {
        alert.messageText = @"Reauthorize API Access";
        alert.informativeText = [NSString stringWithFormat:@"The application “%@” has API access, which grants it permission to see and control your activity. Would you like it to continue?",
                                 controller.humanReadableName];
    } else {
        alert.messageText = @"API Access Request";
        alert.informativeText = [NSString stringWithFormat:@"The application “%@” would like to control iTerm2. This exposes a significant amount of data in iTerm2 to %@. Allow this request?",
                                 controller.humanReadableName, controller.humanReadableName];
    }

    iTermDisclosableView *accessory = [[iTermDisclosableView alloc] initWithFrame:NSZeroRect
                                                                           prompt:@"Full Command"
                                                                          message:controller.fullCommandOrBundleID];
    accessory.frame = NSMakeRect(0, 0, accessory.intrinsicContentSize.width, accessory.intrinsicContentSize.height);
    accessory.requestLayout = ^{
        [alert layout];
    };
    alert.accessoryView = accessory;

    [alert addButtonWithTitle:@"Deny"];
    [alert addButtonWithTitle:@"Allow"];
    if (!reauth) {
        // Reauth is always persistent so don't show the button.
        alert.suppressionButton.title = @"Remember my selection";
        alert.showsSuppressionButton = YES;
    }
    NSModalResponse response = [alert runModal];
    *remember = (alert.suppressionButton.state == NSOnState);
    return (response == NSAlertSecondButtonReturn);
}

- (NSDictionary *)apiServerAuthorizeProcess:(pid_t)pid
                              preauthorized:(BOOL)preauthorized
                                     reason:(out NSString *__autoreleasing *)reason
                                displayName:(out NSString *__autoreleasing *)displayName {
    iTermAPIAuthorizationController *controller = [[iTermAPIAuthorizationController alloc] initWithProcessID:pid];
    *reason = [controller identificationFailureReason];
    if (*reason) {
        return nil;
    }
    *displayName = controller.humanReadableName;

    if (preauthorized) {
        *reason = @"Script launched by user action";
        return controller.identity;
    }


    BOOL reauth = NO;
    switch (controller.setting) {
        case iTermAPIAuthorizationSettingPermanentlyDenied:
            // Access permanently disallowed.
            *reason = [NSString stringWithFormat:@"Access permanently disallowed by user preference to %@",
                       controller.fullCommandOrBundleID];
            return nil;

        case iTermAPIAuthorizationSettingRecentConsent:
            // No need to reauth, allow it.
            *reason = [NSString stringWithFormat:@"Allowing continued API access to process id %d, name %@, bundle ID %@. User gave consent recently.",
                       pid, controller.humanReadableName, controller.fullCommandOrBundleID];
            return controller.identity;

        case iTermAPIAuthorizationSettingExpiredConsent:
            // It's been a month since API access was confirmed. Request it again.
            reauth = YES;
            break;

        case iTermAPIAuthorizationSettingUnknown:
            break;
    }

    BOOL remember = NO;
    BOOL allow = [self askUserToGrantAuthForController:controller isReauthorization:reauth remember:&remember];

    if (reauth || remember) {
        [controller setAllowed:allow];
    } else {
        [controller removeSetting];
    }

    if (allow) {
        *reason = [NSString stringWithFormat:@"User accepted connection by %@", controller.fullCommandOrBundleID];
        return controller.identity;
    } else {
        *reason = [NSString stringWithFormat:@"User rejected connection attempt by %@", controller.fullCommandOrBundleID];
        return nil;
    }
}

- (PTYSession *)sessionForAPIIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"active"]) {
        return [[[iTermController sharedInstance] currentTerminal] currentSession];
    } else if (identifier) {
        for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
            for (PTYSession *session in term.allSessions) {
                if ([session.guid isEqualToString:identifier]) {
                    return session;
                }
            }
        }
    }
    return nil;
}

- (void)apiServerGetBuffer:(ITMGetBufferRequest *)request
                   handler:(void (^)(ITMGetBufferResponse *))handler {
    PTYSession *session = [self sessionForAPIIdentifier:request.session];
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
    PTYSession *session = [self sessionForAPIIdentifier:request.session];
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
        _focusChangeSubscriptions = [[NSMutableDictionary alloc] init];
    }
    NSMutableDictionary<id, ITMNotificationRequest *> *subscriptions;
    if (request.notificationType == ITMNotificationType_NotifyOnNewSession) {
        subscriptions = _newSessionSubscriptions;
    } else if (request.notificationType == ITMNotificationType_NotifyOnTerminateSession) {
        subscriptions = _terminateSessionSubscriptions;
    } else if (request.notificationType == ITMNotificationType_NotifyOnLayoutChange) {
        subscriptions = _layoutChangeSubscriptions;
    } else if (request.notificationType == ITMNotificationType_NotifyOnFocusChange) {
        subscriptions = _focusChangeSubscriptions;
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

- (NSArray<PTYSession *> *)allSessions {
    return [[[iTermController sharedInstance] terminals] flatMapWithBlock:^id(PseudoTerminal *windowController) {
        return windowController.allSessions;
    }];
}

- (void)apiServerNotification:(ITMNotificationRequest *)request
                   connection:(id)connection
                      handler:(void (^)(ITMNotificationResponse *))handler {
    if (request.notificationType == ITMNotificationType_NotifyOnNewSession ||
        request.notificationType == ITMNotificationType_NotifyOnTerminateSession ||
        request.notificationType == ITMNotificationType_NotifyOnLayoutChange ||
        request.notificationType == ITMNotificationType_NotifyOnFocusChange) {
        handler([self handleAPINotificationRequest:request connection:connection]);
    } else if ([request.session isEqualToString:@"all"]) {
        iTermAllSessionsSubscription *sub = [[iTermAllSessionsSubscription alloc] init];
        sub.request = [request copy];
        sub.connection = connection;

        for (PTYSession *session in [self allSessions]) {
            ITMNotificationResponse *response = [session handleAPINotificationRequest:request connection:connection];
            if (response.status != ITMNotificationResponse_Status_AlreadySubscribed &&
                response.status != ITMNotificationResponse_Status_NotSubscribed &&
                response.status != ITMNotificationResponse_Status_Ok) {
                handler(response);
                return;
            }
        }
        ITMNotificationResponse *response = [[ITMNotificationResponse alloc] init];
        response.status = ITMNotificationResponse_Status_Ok;
        handler(response);
    } else {
        PTYSession *session = [self sessionForAPIIdentifier:request.session];
        if (!session) {
            ITMNotificationResponse *response = [[ITMNotificationResponse alloc] init];
            response.status = ITMNotificationResponse_Status_SessionNotFound;
            handler(response);
        } else {
            handler([session handleAPINotificationRequest:request connection:connection]);
        }
    }
}

- (void)apiServerDidCloseConnection:(id)connection {
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermRemoveAPIServerSubscriptionsNotification object:connection];
    [_allSessionsSubscriptions removeObjectsPassingTest:^BOOL(iTermAllSessionsSubscription *sub) {
        return [sub.connection isEqual:connection];
    }];
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
    NSArray<PTYSession *> *sessions;
    if ([request.session isEqualToString:@"all"]) {
        sessions = [self allSessions];
    } else {
        PTYSession *session = [self sessionForAPIIdentifier:request.session];
        if (!session) {
            ITMSetProfilePropertyResponse *response = [[ITMSetProfilePropertyResponse alloc] init];
            response.status = ITMSetProfilePropertyResponse_Status_SessionNotFound;
            handler(response);
            return;
        }
        sessions = @[ session ];
    }

    for (PTYSession *session in sessions) {
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

        ITMSetProfilePropertyResponse *response = [session handleSetProfilePropertyForKey:request.key value:value];
        if (response.status != ITMSetProfilePropertyResponse_Status_Ok) {
            handler(response);
            return;
        }
    }

    ITMSetProfilePropertyResponse *response = [[ITMSetProfilePropertyResponse alloc] init];
    response.status = ITMSetProfilePropertyResponse_Status_Ok;
    handler(response);
}

- (void)apiServerGetProfileProperty:(ITMGetProfilePropertyRequest *)request
                            handler:(void (^)(ITMGetProfilePropertyResponse *))handler {
    PTYSession *session = [self sessionForAPIIdentifier:request.session];
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
    NSArray<PTYSession *> *sessions;
    if ([request.session isEqualToString:@"all"]) {
        sessions = [self allSessions];
    } else {
        PTYSession *session = [self sessionForAPIIdentifier:request.session];
        if (!session || session.exited) {
            ITMSendTextResponse *response = [[ITMSendTextResponse alloc] init];
            response.status = ITMSendTextResponse_Status_SessionNotFound;
            handler(response);
            return;
        }
        sessions = @[ session ];
    }

    for (PTYSession *session in sessions) {
        [session writeTask:request.text];
    }
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
    NSArray<PTYSession *> *sessions;
    if ([request.session isEqualToString:@"all"]) {
        sessions = [self allSessions];
    } else {
        PTYSession *session = [self sessionForAPIIdentifier:request.session];
        if (!session || session.exited) {
            ITMSplitPaneResponse *response = [[ITMSplitPaneResponse alloc] init];
            response.status = ITMSplitPaneResponse_Status_SessionNotFound;
            handler(response);
            return;
        }
        sessions = @[ session ];
    }

    for (PTYSession *session in sessions) {
        PseudoTerminal *term = [[iTermController sharedInstance] terminalWithSession:session];
        if (!term) {
            ITMSplitPaneResponse *response = [[ITMSplitPaneResponse alloc] init];
            response.status = ITMSplitPaneResponse_Status_SessionNotFound;
            handler(response);
            return;
        }
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

    ITMSplitPaneResponse *response = [[ITMSplitPaneResponse alloc] init];
    response.status = ITMSplitPaneResponse_Status_Ok;
    for (PTYSession *session in sessions) {
        PseudoTerminal *term = [[iTermController sharedInstance] terminalWithSession:session];
        PTYSession *newSession = [term splitVertically:request.splitDirection == ITMSplitPaneRequest_SplitDirection_Vertical
                                                before:request.before
                                               profile:profile
                                         targetSession:session];
        if (newSession == nil && !session.isTmuxClient) {
            response.status = ITMSplitPaneResponse_Status_CannotSplit;
        } else {
            [response.sessionIdArray addObject:newSession.guid];
        }
    }

    handler(response);
}

- (void)apiServerSetProperty:(ITMSetPropertyRequest *)request handler:(void (^)(ITMSetPropertyResponse *))handler {
    ITMSetPropertyResponse *response = [[ITMSetPropertyResponse alloc] init];
    switch (request.identifierOneOfCase) {
        case ITMSetPropertyRequest_Identifier_OneOfCase_GPBUnsetOneOfCase:
            response.status = ITMSetPropertyResponse_Status_InvalidTarget;
            handler(response);
            return;

        case ITMSetPropertyRequest_Identifier_OneOfCase_WindowId: {
            PseudoTerminal *term = [[iTermController sharedInstance] terminalWithGuid:request.windowId];
            if (!term) {
                response.status = ITMSetPropertyResponse_Status_InvalidTarget;
                handler(response);
                return;
            }
            NSError *error = nil;
            id value = [NSJSONSerialization JSONObjectWithData:[request.jsonValue dataUsingEncoding:NSUTF8StringEncoding]
                                                       options:NSJSONReadingAllowFragments
                                                         error:&error];
            if (!value || error) {
                XLog(@"JSON parsing error %@ for value in request %@", error, request);
                ITMSetPropertyResponse *response = [[ITMSetPropertyResponse alloc] init];
                response.status = ITMSetPropertyResponse_Status_InvalidValue;
                handler(response);
            }
            response.status = [self setPropertyInWindow:term name:request.name value:value];
            handler(response);
        }
    }
}

- (ITMSetPropertyResponse_Status)setPropertyInWindow:(PseudoTerminal *)term name:(NSString *)name value:(id)value {
    typedef ITMSetPropertyResponse_Status (^SetWindowPropertyBlock)(void);
    SetWindowPropertyBlock setFrame = ^ITMSetPropertyResponse_Status {
        NSDictionary *dict = [NSDictionary castFrom:value];
        NSDictionary *origin = dict[@"origin"];
        NSDictionary *size = dict[@"size"];
        NSNumber *x = origin[@"x"];
        NSNumber *y = origin[@"y"];
        NSNumber *width = size[@"width"];
        NSNumber *height = size[@"height"];
        if (!x || !y || !width || !height) {
            return ITMSetPropertyResponse_Status_InvalidValue;
        }
        NSRect rect = NSMakeRect(x.doubleValue, y.doubleValue, width.doubleValue, height.doubleValue);
        [term.window setFrame:rect display:YES];
        return ITMSetPropertyResponse_Status_Ok;
    };

    SetWindowPropertyBlock setFullScreen = ^ITMSetPropertyResponse_Status {
        NSNumber *number = [NSNumber castFrom:value];
        if (!number) {
            return ITMSetPropertyResponse_Status_InvalidValue;
        }
        BOOL fullscreen = number.boolValue;
        if (!!term.anyFullScreen == !!fullscreen) {
            return ITMSetPropertyResponse_Status_Ok;
        } else {
            [term toggleFullScreenMode:nil];
        }
        return ITMSetPropertyResponse_Status_Ok;
    };
    NSDictionary<NSString *, SetWindowPropertyBlock> *handlers =
        @{ @"frame": setFrame,
           @"fullscreen": setFullScreen };
    SetWindowPropertyBlock block = handlers[name];
    if (block) {
        return block();
    } else {
        return ITMSetPropertyResponse_Status_UnrecognizedName;
    }
}

- (void)apiServerGetProperty:(ITMGetPropertyRequest *)request handler:(void (^)(ITMGetPropertyResponse *))handler {
    ITMGetPropertyResponse *response = [[ITMGetPropertyResponse alloc] init];
    switch (request.identifierOneOfCase) {
        case ITMGetPropertyRequest_Identifier_OneOfCase_GPBUnsetOneOfCase:
            response.status = ITMGetPropertyResponse_Status_InvalidTarget;
            handler(response);
            return;

        case ITMGetPropertyRequest_Identifier_OneOfCase_WindowId: {
            PseudoTerminal *term = [[iTermController sharedInstance] terminalWithGuid:request.windowId];
            if (!term) {
                response.status = ITMGetPropertyResponse_Status_InvalidTarget;
                handler(response);
                return;
            }
            NSString *jsonValue = [self getPropertyFromWindow:term name:request.name];
            if (jsonValue) {
                response.jsonValue = jsonValue;
                response.status = ITMGetPropertyResponse_Status_Ok;
            } else {
                response.status = ITMGetPropertyResponse_Status_UnrecognizedName;
            }
            handler(response);
        }
    }
}

- (NSString *)getPropertyFromWindow:(PseudoTerminal *)term name:(NSString *)name {
    typedef NSString * (^GetWindowPropertyBlock)(void);

    GetWindowPropertyBlock getFrame = ^NSString * {
        NSRect frame = term.window.frame;
        NSDictionary *dict =
            @{ @"origin": @{ @"x": @(frame.origin.x),
                             @"y": @(frame.origin.y) },
               @"size": @{ @"width": @(frame.size.width),
                           @"height": @(frame.size.height) } };
        NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    };

    GetWindowPropertyBlock getFullScreen = ^NSString * {
        return term.anyFullScreen ? @"true" : @"false";
    };

    NSDictionary<NSString *, GetWindowPropertyBlock> *handlers =
        @{ @"frame": getFrame,
           @"fullscreen": getFullScreen };

    GetWindowPropertyBlock block = handlers[name];
    if (block) {
        return block();
    } else {
        return nil;
    }
}

- (void)apiServerInject:(ITMInjectRequest *)request handler:(void (^)(ITMInjectResponse *))handler {
    ITMInjectResponse *response = [[ITMInjectResponse alloc] init];
    for (NSString *sessionID in request.sessionIdArray) {
        if ([sessionID isEqualToString:@"all"]) {
            for (PTYSession *session in [self allSessions]) {
                [self inject:request.data_p into:session];
            }
            [response.statusArray addValue:ITMInjectResponse_Status_Ok];
        } else {
            PTYSession *session = [self sessionForAPIIdentifier:sessionID];
            if (session) {
                [self inject:request.data_p into:session];
                [response.statusArray addValue:ITMInjectResponse_Status_Ok];
            } else {
                [response.statusArray addValue:ITMInjectResponse_Status_SessionNotFound];
            }
        }
    }
    handler(response);
}

- (void)inject:(NSData *)data into:(PTYSession *)session {
    [session injectData:data];
}

- (void)apiServerActivate:(ITMActivateRequest *)request handler:(void (^)(ITMActivateResponse *))handler {
    ITMActivateResponse *response = [[ITMActivateResponse alloc] init];
    PTYSession *session;
    PTYTab *tab;
    PseudoTerminal *windowController;
    if (request.identifierOneOfCase == ITMActivateRequest_Identifier_OneOfCase_TabId) {
        for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
            tab = [term tabWithUniqueId:request.tabId.intValue];
            if (tab) {
                windowController = term;
                break;
            }
        }
        if (!tab) {
            response.status = ITMActivateResponse_Status_BadIdentifier;
            handler(response);
            return;
        }
    } else if (request.identifierOneOfCase == ITMActivateRequest_Identifier_OneOfCase_WindowId) {
        windowController = [[[iTermController sharedInstance] terminals] objectPassingTest:^BOOL(PseudoTerminal *element, NSUInteger index, BOOL *stop) {
            return [element.terminalGuid isEqual:request.windowId];
        }];
        if (!windowController) {
            response.status = ITMActivateResponse_Status_BadIdentifier;
            handler(response);
            return;
        }
    } else if (request.identifierOneOfCase == ITMActivateRequest_Identifier_OneOfCase_SessionId) {
        session = [self sessionForAPIIdentifier:request.sessionId];
        if (!session) {
            response.status = ITMActivateResponse_Status_BadIdentifier;
            handler(response);
            return;
        }
        tab = [session.delegate.realParentWindow tabForSession:session];
        if (!tab) {
            response.status = ITMActivateResponse_Status_BadIdentifier;
            handler(response);
            return;
        }
        windowController = [PseudoTerminal castFrom:tab.realParentWindow];
    }

    if (request.selectSession) {
        if (!session) {
            response.status = ITMActivateResponse_Status_InvalidOption;
            handler(response);
            return;
        }
        [tab setActiveSession:session];
        response.status = ITMActivateResponse_Status_Ok;
        handler(response);
    }

    if (request.selectTab) {
        if (!tab) {
            response.status = ITMActivateResponse_Status_InvalidOption;
            handler(response);
            return;
        }
        [windowController.tabView selectTabViewItemWithIdentifier:tab];
    }

    if (request.orderWindowFront) {
        if (!windowController) {
            response.status = ITMActivateResponse_Status_InvalidOption;
            handler(response);
            return;
        }
        [windowController.window makeKeyAndOrderFront:nil];
    }

    if (request.hasActivateApp) {
        NSApplicationActivationOptions options = 0;
        if (request.activateApp.raiseAllWindows) {
            options |= NSApplicationActivateAllWindows;
        }
        if (request.activateApp.ignoringOtherApps) {
            options |= NSApplicationActivateIgnoringOtherApps;
        }
        [[NSRunningApplication currentApplication] activateWithOptions:options];
    }

    response.status = ITMActivateResponse_Status_Ok;
    handler(response);
}

- (void)apiServerVariable:(ITMVariableRequest *)request handler:(void (^)(ITMVariableResponse *))handler {
    ITMVariableResponse *response = [[ITMVariableResponse alloc] init];
    const BOOL allSetNamesLegal = [request.setArray allWithBlock:^BOOL(ITMVariableRequest_Set *setRequest) {
        return [setRequest.name hasPrefix:@"user."];
    }];
    if (!allSetNamesLegal) {
        response.status = ITMVariableResponse_Status_InvalidName;
        handler(response);
        return;
    }
    if ([request.sessionId isEqualToString:@"all"]) {
        if (request.getArray_Count > 0) {
            response.status = ITMVariableResponse_Status_SessionNotFound;
            handler(response);
            return;
        }
        for (PTYSession *session in [self allSessions]) {
            [request.setArray enumerateObjectsUsingBlock:^(ITMVariableRequest_Set * _Nonnull setRequest, NSUInteger idx, BOOL * _Nonnull stop) {
                [session setVariableNamed:setRequest.name toValue:setRequest.value];
            }];
        }
        response.status = ITMVariableResponse_Status_Ok;
        handler(response);
        return;
    }

    PTYSession *session = [self sessionForAPIIdentifier:request.sessionId];
    if (!session) {
        response.status = ITMVariableResponse_Status_SessionNotFound;
        handler(response);
        return;
    }

    [request.setArray enumerateObjectsUsingBlock:^(ITMVariableRequest_Set * _Nonnull setRequest, NSUInteger idx, BOOL * _Nonnull stop) {
        [session setVariableNamed:setRequest.name toValue:setRequest.value];
    }];
    [request.getArray enumerateObjectsUsingBlock:^(NSString * _Nonnull name, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([name isEqualToString:@"*"]) {
            [response.valuesArray addObject:[session.variables.allKeys componentsJoinedByString:@"\n"]];
        } else {
            NSString *value = session.variables[name] ?: @"";
            [response.valuesArray addObject:value];
        }
    }];
    handler(response);
}

- (void)apiServerSavedArrangement:(ITMSavedArrangementRequest *)request handler:(void (^)(ITMSavedArrangementResponse *))handler {
    switch (request.action) {
        case ITMSavedArrangementRequest_Action_Save:
            [self saveArrangementNamed:request.name windowID:request.windowId handler:handler];
            return;

        case ITMSavedArrangementRequest_Action_Restore:
            [self restoreArrangementNamed:request.name windowID:request.windowId handler:handler];
            return;
    }
    ITMSavedArrangementResponse *response = [[ITMSavedArrangementResponse alloc] init];
    response.status = ITMSavedArrangementResponse_Status_RequestMalformed;
    handler(response);
}

- (void)saveArrangementNamed:(NSString *)name
                    windowID:(NSString *)windowID
                     handler:(void (^)(ITMSavedArrangementResponse *))handler {
    ITMSavedArrangementResponse *response = [[ITMSavedArrangementResponse alloc] init];
    if (windowID.length) {
        PseudoTerminal *term = [[iTermController sharedInstance] terminalWithGuid:windowID];
        if (!term) {
            response.status = ITMSavedArrangementResponse_Status_WindowNotFound;
            handler(response);
            return;
        }

        [[iTermController sharedInstance] saveWindowArrangementForWindow:term name:name];
    } else {
        [[iTermController sharedInstance] saveWindowArrangmentForAllWindows:YES name:name];
    }
    response.status = ITMSavedArrangementResponse_Status_Ok;
    handler(response);
}

- (void)restoreArrangementNamed:(NSString *)name
                       windowID:(NSString *)windowID
                        handler:(void (^)(ITMSavedArrangementResponse *))handler {
    ITMSavedArrangementResponse *response = [[ITMSavedArrangementResponse alloc] init];
    PseudoTerminal *term = nil;
    if (windowID.length) {
        term = [[iTermController sharedInstance] terminalWithGuid:windowID];
        if (!term) {
            response.status = ITMSavedArrangementResponse_Status_WindowNotFound;
            handler(response);
            return;
        }
    }
    BOOL ok = [[iTermController sharedInstance] loadWindowArrangementWithName:name asTabsInTerminal:term];
    if (ok) {
        response.status = ITMSavedArrangementResponse_Status_Ok;
    } else {
        response.status = ITMSavedArrangementResponse_Status_ArrangementNotFound;
    }
    handler(response);
}

- (void)apiServerFocus:(ITMFocusRequest *)request handler:(void (^)(ITMFocusResponse *))handler {
    ITMFocusResponse *response = [[ITMFocusResponse alloc] init];

    ITMFocusChangedNotification *focusChange = [[ITMFocusChangedNotification alloc] init];
    focusChange.applicationActive = [NSApp isActive];
    [response.notificationsArray addObject:focusChange];

    focusChange = [[ITMFocusChangedNotification alloc] init];
    PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];
    focusChange.window = [[ITMFocusChangedNotification_Window alloc] init];
    if (term && term.window == NSApp.keyWindow) {
        focusChange.window.windowStatus = ITMFocusChangedNotification_Window_WindowStatus_TerminalWindowBecameKey;
    } else if (term) {
        focusChange.window.windowStatus = ITMFocusChangedNotification_Window_WindowStatus_TerminalWindowIsCurrent;
    } else {
        focusChange.window.windowStatus = ITMFocusChangedNotification_Window_WindowStatus_TerminalWindowResignedKey;
    }
    focusChange.window.windowId = term.terminalGuid;
    [response.notificationsArray addObject:focusChange];

    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        focusChange = [[ITMFocusChangedNotification alloc] init];
        PTYTab *tab = term.currentTab;
        focusChange.selectedTab = [@(tab.uniqueId) stringValue];
        [response.notificationsArray addObject:focusChange];

        for (PTYTab *tab in term.tabs) {
            focusChange = [[ITMFocusChangedNotification alloc] init];
            focusChange.session = tab.activeSession.guid;
            [response.notificationsArray addObject:focusChange];
        }
    }
    handler(response);
}

@end
