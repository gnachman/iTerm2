//
//  iTermAPIHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/18/18.
//

#import "iTermAPIHelper.h"

#import "CVector.h"
#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAPIAuthorizationController.h"
#import "iTermBuriedSessions.h"
#import "iTermBuiltInFunctions.h"
#import "iTermColorPresets.h"
#import "iTermController.h"
#import "iTermDisclosableView.h"
#import "iTermLSOF.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "iTermPythonArgumentParser.h"
#import "iTermScriptFunctionCall.h"
#import "iTermScriptHistory.h"
#import "iTermSelection.h"
#import "iTermStatusBarComponent.h"
#import "iTermStatusBarViewController.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope+Global.h"
#import "iTermWarning.h"
#import "MovePaneController.h"
#import "NSApplication+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "ProfileModel.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "TmuxController.h"
#import "TmuxControllerRegistry.h"
#import "TmuxGateway.h"
#import "WindowControllerInterface.h"
#import "VT100Parser.h"

NSString *const iTermAPIHelperDidStopNotification = @"iTermAPIHelperDidStopNotification";
static NSString *const iTermAPIHelperEnablePythonAPIWarningIdentifier = @"NoSyncEnableAPIServer";

static iTermAPIHelper *sAPIHelperInstance;


@interface iTermBlockTargetActionForwarder : NSObject
- (instancetype)initWithBlock:(void (^)(id))block NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)attachToOwner:(NSObject *)owner failure:(void (^)(void))failure;
- (void)selector:(id)object;
@end

@implementation iTermBlockTargetActionForwarder {
    void (^_block)(id);
    void (^_failure)(void);
    void *_associatedObjectKey;
}

- (instancetype)initWithBlock:(void (^)(id))block {
    self = [super init];
    if (self) {
        _block = [block copy];
    }
    return self;
}

- (void)dealloc {
    if (_failure && _block) {
        _failure();
    }
    free(_associatedObjectKey);
}

- (void)selector:(id)object {
    if (_block) {
        _failure = nil;
        void (^block)(id) = _block;
        _block = nil;
        block(object);
    }
}

- (void)attachToOwner:(NSObject *)owner failure:(void (^)(void))failure {
    assert(!_associatedObjectKey);
    _associatedObjectKey = malloc(1);
    [owner it_setAssociatedObject:self forKey:_associatedObjectKey];
    _failure = [failure copy];
}

@end

@interface iTermAPIHelper() <iTermAPINotificationControllerDelegate>
@end

@implementation iTermAPIHelper {
    iTermAPIServer *_apiServer;
}

+ (instancetype)sharedInstance {
    if (!sAPIHelperInstance) {
        sAPIHelperInstance = [[self alloc] initWithExplicitUserAction:NO];
    }
    return sAPIHelperInstance;
}

+ (instancetype)sharedInstanceFromExplicitUserAction {
    if (!sAPIHelperInstance) {
        sAPIHelperInstance = [[self alloc] initWithExplicitUserAction:YES];
    }
    return sAPIHelperInstance;
}

+ (NSDictionary<NSString *, NSArray<NSString *> *> *)registeredFunctionSignatureDictionary {
    return [sAPIHelperInstance.dispatcher registeredFunctionSignatureDictionary] ?: @{};
}

+ (NSArray<iTermSessionTitleProvider *> *)sessionTitleFunctions {
    return [sAPIHelperInstance.dispatcher sessionTitleFunctions] ?: @[];
}

+ (NSArray<ITMRPCRegistrationRequest *> *)statusBarComponentProviderRegistrationRequests {
    return [sAPIHelperInstance.dispatcher statusBarComponentProviderRegistrationRequests] ?: @[];
}

+ (BOOL)confirmShouldStartServerAndUpdateUserDefaultsForced:(BOOL)forced {
    // It was not enabled in preferences. Ask the user. If they permanently silence this
    // they'll need to go into prefs to enable it.
    iTermWarning *warning = [[iTermWarning alloc] init];
    warning.heading = @"Enable Python API?";
    warning.actionLabels = @[ @"OK", @"Cancel" ];
    warning.identifier = iTermAPIHelperEnablePythonAPIWarningIdentifier;
    warning.warningType = forced ? kiTermWarningTypePersistent : kiTermWarningTypePermanentlySilenceable;
    warning.title = @"The Python API allows scripts you run to control iTerm2 and access all its data.";
    static BOOL showing;
    assert(!showing);
    showing = YES;
    const iTermWarningSelection selection = [warning runModal];
    showing = NO;
    if (selection == kiTermWarningSelection1) {
        [iTermPreferences setBool:NO forKey:kPreferenceKeyEnableAPIServer];
        return NO;
    } else {
        [iTermPreferences setBool:YES forKey:kPreferenceKeyEnableAPIServer];
    }
    return YES;
}

- (instancetype)initWithExplicitUserAction:(BOOL)force {
    self = [super init];
    if (self) {
        if (![NSApp isRunningUnitTests]) {
            if (![iTermPreferences boolForKey:kPreferenceKeyEnableAPIServer]) {
                if (![iTermAPIHelper confirmShouldStartServerAndUpdateUserDefaultsForced:force]) {
                    return nil;
                }
            }
            _apiServer = [[iTermAPIServer alloc] init];
            _apiServer.delegate = self;
        }

        _notificationController = [[iTermAPINotificationController alloc] init];
        _notificationController.delegate = self;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (void)setEnabled:(BOOL)enabled {
    [iTermWarning unsilenceIdentifier:iTermAPIHelperEnablePythonAPIWarningIdentifier
                    ifSelectionEquals:kiTermWarningSelection0];
    [iTermWarning unsilenceIdentifier:iTermAPIHelperEnablePythonAPIWarningIdentifier
                    ifSelectionEquals:kiTermWarningSelection1];
    if (enabled) {
        [iTermPreferences setBool:YES forKey:kPreferenceKeyEnableAPIServer];
        [self sharedInstance];
    } else {
        [iTermPreferences setBool:NO forKey:kPreferenceKeyEnableAPIServer];
        [sAPIHelperInstance stop];
        sAPIHelperInstance = nil;
    }
}

+ (BOOL)isEnabled {
    return [iTermPreferences boolForKey:kPreferenceKeyEnableAPIServer];
}

- (void)stop {
    [_apiServer stop];
    _apiServer.delegate = nil;
    _apiServer = nil;
    [self.notificationController stop];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermAPIHelperDidStopNotification object:nil];
}

- (void)postAPINotification:(ITMNotification *)notification toConnectionKey:(NSString *)connectionKey {
    [_apiServer postAPINotification:notification toConnectionKey:connectionKey];
}


+ (ITMRPCRegistrationRequest *)registrationRequestForStatusBarComponentWithUniqueIdentifier:(NSString *)uniqueIdentifier {
    return [[[self sharedInstance] statusBarComponentProviderRegistrationRequests] objectPassingTest:^BOOL(ITMRPCRegistrationRequest *request, NSUInteger index, BOOL *stop) {
        return [request.statusBarComponentAttributes.uniqueIdentifier isEqualToString:uniqueIdentifier];
    }];
}

- (BOOL)haveRegisteredFunctionWithName:(NSString *)name
                             arguments:(NSArray<NSString *> *)arguments {
    NSString *stringSignature = iTermFunctionSignatureFromNameAndArguments(name, arguments);
    return [self.dispatcher haveRegisteredFunctionWithSignature:stringSignature];
}

- (void)logToConnectionWithKey:(NSString *)connectionKey
                        format:(NSString *)format, ... {
    va_list arguments;
    va_start(arguments, format);
    NSString *string = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    [self logToConnectionWithKey:connectionKey string:string];
}

- (iTermScriptHistoryEntry *)scriptHistoryEntryForConnectionKey:(NSString *)connectionKey {
    NSString *key = connectionKey ? [_apiServer websocketKeyForConnectionKey:connectionKey] : nil;
    iTermScriptHistoryEntry *entry = key ? [[iTermScriptHistory sharedInstance] entryWithIdentifier:key] : nil;
    return entry;
}

- (void)logToConnectionWithKey:(NSString *)connectionKey string:(NSString *)string {
    iTermScriptHistoryEntry *entry = [self scriptHistoryEntryForConnectionKey:connectionKey];
    if (!entry) {
        entry = [iTermScriptHistoryEntry globalEntry];
    }

    [entry addOutput:@"❗️ "];
    [entry addOutput:string];
    [entry addOutput:@"\n"];
    XLog(@"%@", string);
}

- (iTermAPIDispatcher *)dispatcher {
    return _notificationController.dispatcher;
}

#pragma mark - iTermAPIServerDelegate

- (NSMenuItem *)menuItemWithTitleParts:(NSArray<NSString *> *)titleParts
                                inMenu:(NSMenu *)menu NS_DEPRECATED_MAC(10_10, 10_11, "Use menuItemWithIdentifier:") {
    NSString *head = titleParts.firstObject;
    NSArray<NSString *> *remainingTitleParts = [titleParts subarrayFromIndex:1];
    for (NSMenuItem *item in [menu itemArray]) {
        if ([item.title isEqualToString:head]) {
            if ([item hasSubmenu]) {
                return [self menuItemWithTitleParts:remainingTitleParts
                                             inMenu:item.submenu];
            } else if (remainingTitleParts.count == 0) {
                return item;
            }
        }
    }
    return nil;
}

- (NSMenuItem *)menuItemWithIdentifier:(NSString *)identifier
                                inMenu:(NSMenu *)menu NS_AVAILABLE_MAC(10_12) {
    for (NSMenuItem *item in [menu itemArray]) {
        if ([item hasSubmenu]) {
            NSMenuItem *result = [self menuItemWithIdentifier:identifier inMenu:item.submenu];
            if (result) {
                return result;
            }
        } else if (item.identifier && [identifier isEqualToString:item.identifier]) {
            return item;
        }
    }
    return nil;
}

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
                                                                          message:controller.fullCommandOrBundleID ?: @"Unknown application"];
    accessory.frame = NSMakeRect(0, 0, accessory.intrinsicContentSize.width, accessory.intrinsicContentSize.height);
    accessory.textView.selectable = YES;
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

- (PTYSession *)sessionForAPIIdentifier:(NSString *)identifier includeBuriedSessions:(BOOL)includeBuriedSessions {
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
        if (includeBuriedSessions) {
            for (PTYSession *session in [[iTermBuriedSessions sharedInstance] buriedSessions]) {
                if ([session.guid isEqualToString:identifier]) {
                    return session;
                }
            }
        }
    }
    return nil;
}

- (PseudoTerminal *)windowControllerWithID:(NSString *)windowID {
    return [[[iTermController sharedInstance] terminals] objectPassingTest:^BOOL(PseudoTerminal *windowController, NSUInteger index, BOOL *stop) {
        return [windowController.terminalGuid isEqualToString:windowID];
    }];
}

- (PTYTab *)tabWithID:(NSString *)tabID {
    return [[iTermController sharedInstance] tabWithID:tabID];
}

- (void)apiServerGetBuffer:(ITMGetBufferRequest *)request
                   handler:(void (^)(ITMGetBufferResponse *))handler {
    PTYSession *session = [self sessionForAPIIdentifier:request.session includeBuriedSessions:YES];
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
    PTYSession *session = [self sessionForAPIIdentifier:request.session includeBuriedSessions:YES];
    if (!session) {
        ITMGetPromptResponse *response = [[ITMGetPromptResponse alloc] init];
        response.status = ITMGetPromptResponse_Status_SessionNotFound;
        handler(response);
    } else {
        handler([session handleGetPromptRequest:request]);
    }
}

- (void)performBlockWhenFunctionRegisteredWithName:(NSString *)name
                                         arguments:(NSArray<NSString *> *)arguments
                                           timeout:(NSTimeInterval)timeout
                                             block:(void (^)(BOOL))block {
    if ([self haveRegisteredFunctionWithName:name arguments:arguments]) {
        block(NO);
        return;
    }

    __block BOOL called = NO;
    __block id observer =
        [[NSNotificationCenter defaultCenter] addObserverForName:iTermAPIRegisteredFunctionsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull notification) {
            if (called) {
                return;
            }
            if ([self haveRegisteredFunctionWithName:name arguments:arguments]) {
                called = YES;
                [[NSNotificationCenter defaultCenter] removeObserver:observer];
                block(NO);
            }
        }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!called) {
            called = YES;
            [[NSNotificationCenter defaultCenter] removeObserver:observer];
            block(YES);
        }
    });
}


- (NSArray<PTYSession *> *)allSessions {
    return [[[iTermController sharedInstance] terminals] flatMapWithBlock:^id(PseudoTerminal *windowController) {
        return windowController.allSessions;
    }];
}

- (NSArray<PTYTab *> *)allTabs {
    return [[[iTermController sharedInstance] terminals] flatMapWithBlock:^id(PseudoTerminal *windowController) {
        return windowController.tabs;
    }];
}

- (void)apiServerNotification:(ITMNotificationRequest *)request
                connectionKey:(NSString *)connectionKey
                      handler:(void (^)(ITMNotificationResponse *))handler {
    [self.notificationController apiServerNotification:request connectionKey:connectionKey handler:handler];
}

- (void)apiServerDidCloseConnectionWithKey:(id)connectionKey {
    [self.notificationController didCloseConnectionWithKey:connectionKey];
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
    ITMSetProfilePropertyResponse *response = [[ITMSetProfilePropertyResponse alloc] init];
    ITMSetProfilePropertyResponse_Status (^setter)(id object, NSString *key, id value) = nil;
    NSMutableArray *objects = [NSMutableArray array];
    id key = _apiServer.currentKey;
    iTermScriptHistoryEntry *entry = key ? [[iTermScriptHistory sharedInstance] entryWithIdentifier:key] : nil;

    switch (request.targetOneOfCase) {
        case ITMSetProfilePropertyRequest_Target_OneOfCase_GPBUnsetOneOfCase: {
            response.status = ITMSetProfilePropertyResponse_Status_RequestMalformed;
            handler(response);
            return;
        }

        case ITMSetProfilePropertyRequest_Target_OneOfCase_GuidList: {
            setter = ^ITMSetProfilePropertyResponse_Status(id object, NSString *key, id value) {
                Profile *profile = object;
                [iTermProfilePreferences setObject:value forKey:key inProfile:profile model:[ProfileModel sharedInstance]];
                return ITMSetProfilePropertyResponse_Status_Ok;
            };
            for (NSString *guid in request.guidList.guidsArray) {
                Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
                if (!profile) {
                    response.status = ITMSetProfilePropertyResponse_Status_BadGuid;
                    handler(response);
                    return;
                }
                [objects addObject:profile];
            }
            break;
        }

        case ITMSetProfilePropertyRequest_Target_OneOfCase_Session: {
            setter = ^ITMSetProfilePropertyResponse_Status(id object, NSString *key, id value) {
                return [(PTYSession *)object handleSetProfilePropertyForKey:request.key value:value scriptHistoryEntry:entry];
            };
            if ([request.session isEqualToString:@"all"]) {
                [objects addObjectsFromArray:[self allSessions]];
            } else {
                PTYSession *session = [self sessionForAPIIdentifier:request.session includeBuriedSessions:YES];
                if (!session) {
                    ITMSetProfilePropertyResponse *response = [[ITMSetProfilePropertyResponse alloc] init];
                    response.status = ITMSetProfilePropertyResponse_Status_SessionNotFound;
                    handler(response);
                    return;
                }
                [objects addObject:session];
            }
            break;
        }
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
        return;
    }

    for (id object in objects) {
        response.status = setter(object, request.key, value);
        if (response.status != ITMSetProfilePropertyResponse_Status_Ok) {
            handler(response);
            return;
        }
    }

    response.status = ITMSetProfilePropertyResponse_Status_Ok;
    handler(response);
}

- (void)apiServerGetProfileProperty:(ITMGetProfilePropertyRequest *)request
                            handler:(void (^)(ITMGetProfilePropertyResponse *))handler {
    PTYSession *session = [self sessionForAPIIdentifier:request.session includeBuriedSessions:YES];
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
        windowMessage.number = window.number;

        for (PTYTab *tab in window.tabs) {
            ITMListSessionsResponse_Tab *tabMessage = [[ITMListSessionsResponse_Tab alloc] init];
            tabMessage.tabId = [@(tab.uniqueId) stringValue];
            tabMessage.root = [tab rootSplitTreeNode];
            tabMessage.tmuxWindowId = [@(tab.tmuxWindow) stringValue];
            [windowMessage.tabsArray addObject:tabMessage];
        }

        [response.windowsArray addObject:windowMessage];
    }
    for (PTYSession *session in [[iTermBuriedSessions sharedInstance] buriedSessions]) {
        ITMSessionSummary *sessionSummary = [[ITMSessionSummary alloc] init];
        sessionSummary.uniqueIdentifier = session.guid;
        sessionSummary.title = session.name;
        [response.buriedSessionsArray addObject:sessionSummary];
    }
    return response;
}

- (void)apiServerSendText:(ITMSendTextRequest *)request handler:(void (^)(ITMSendTextResponse *))handler {
    NSArray<PTYSession *> *sessions;
    if ([request.session isEqualToString:@"all"]) {
        sessions = [self allSessions];
    } else {
        PTYSession *session = [self sessionForAPIIdentifier:request.session includeBuriedSessions:YES];
        if (!session || session.exited) {
            ITMSendTextResponse *response = [[ITMSendTextResponse alloc] init];
            response.status = ITMSendTextResponse_Status_SessionNotFound;
            handler(response);
            return;
        }
        sessions = @[ session ];
    }

    for (PTYSession *session in sessions) {
        if (request.suppressBroadcast) {
            [session writeTaskNoBroadcast:request.text];
        } else {
            [session writeTask:request.text];
        }
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
                                                                   command:nil
                                                                     block:^PTYSession *(Profile *profile, PseudoTerminal *term) {
                                                                         profile = [self profileByCustomizing:profile withProperties:request.customProfilePropertiesArray];
                                                                         return [term createTabWithProfile:profile
                                                                                               withCommand:nil
                                                                                               environment:nil
#warning TODO: This doesn't really need to block the main thread since this method is async.
                                                                                               synchronous:YES
                                                                                                completion:nil];
                                                                     }
#warning TODO: This doesn't really need to block the main thread since this method is async.
                                                               synchronous:YES
                                                                completion:nil];

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
        PTYSession *session = [self sessionForAPIIdentifier:request.session includeBuriedSessions:YES];
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

    profile = [self profileByCustomizing:profile withProperties:request.customProfilePropertiesArray];
    if (!profile) {
        ITMSplitPaneResponse *response = [[ITMSplitPaneResponse alloc] init];
        response.status = ITMSplitPaneResponse_Status_MalformedCustomProfileProperty;
        handler(response);
        return;
    }

    ITMSplitPaneResponse *response = [[ITMSplitPaneResponse alloc] init];
    response.status = ITMSplitPaneResponse_Status_Ok;
    for (PTYSession *session in sessions) {
        PseudoTerminal *term = [[iTermController sharedInstance] terminalWithSession:session];
        PTYSession *newSession = [term splitVertically:request.splitDirection == ITMSplitPaneRequest_SplitDirection_Vertical
                                                before:request.before
                                               profile:profile
                                         targetSession:session
#warning TODO: This doesn't really need to block the main thread since this method is async.
                                           synchronous:YES];
        if (newSession == nil && !session.isTmuxClient) {
            response.status = ITMSplitPaneResponse_Status_CannotSplit;
        } else if (newSession && newSession.guid) {  // The test for newSession.guid is just to quiet the analyzer
            [response.sessionIdArray addObject:newSession.guid];
        }
    }

    handler(response);
}

- (Profile *)profileByCustomizing:(Profile *)profile withProperties:(NSArray<ITMProfileProperty*> *)customProfilePropertiesArray {
    for (ITMProfileProperty *property in customProfilePropertiesArray) {
        id value = [NSJSONSerialization it_objectForJsonString:property.jsonValue];
        if (!value) {
            return nil;
        }
        profile = [profile dictionaryBySettingObject:value forKey:property.key];
    }
    return profile;
}

- (void)apiServerSetProperty:(ITMSetPropertyRequest *)request handler:(void (^)(ITMSetPropertyResponse *))handler {
    ITMSetPropertyResponse *response = [[ITMSetPropertyResponse alloc] init];
    NSError *error = nil;
    id value = [NSJSONSerialization JSONObjectWithData:[request.jsonValue dataUsingEncoding:NSUTF8StringEncoding]
                                               options:NSJSONReadingAllowFragments
                                                 error:&error];
    if (!value || error) {
        XLog(@"JSON parsing error %@ for value in request %@", error, request);
        ITMSetPropertyResponse *response = [[ITMSetPropertyResponse alloc] init];
        response.status = ITMSetPropertyResponse_Status_InvalidValue;
        handler(response);
        return;
    }
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
            [self setPropertyInWindow:term name:request.name value:value completion:handler];
            return;
        }

        case ITMSetPropertyRequest_Identifier_OneOfCase_SessionId: {
            if ([request.sessionId isEqualToString:@"all"]) {
                for (PTYSession *session in [self allSessions]) {
                    response.status = [self setPropertyInSession:session name:request.name value:value];
                    handler(response);
                    return;
                }
            } else {
                PTYSession *session = [self sessionForAPIIdentifier:request.sessionId includeBuriedSessions:YES];
                if (!session) {
                    response.status = ITMSetPropertyResponse_Status_InvalidTarget;
                    handler(response);
                    return;
                }
                response.status = [self setPropertyInSession:session name:request.name value:value];
                handler(response);
                return;
            }
        }
    }
    response.status = ITMSetPropertyResponse_Status_InvalidTarget;
    handler(response);
}

- (void)setPropertyInWindow:(PseudoTerminal *)term
                       name:(NSString *)name
                      value:(id)value
                 completion:(void (^)(ITMSetPropertyResponse *))completion {
    ITMSetPropertyResponse *response = [[ITMSetPropertyResponse alloc] init];
    void (^setFrame)(void) = ^{
        NSDictionary *dict = [NSDictionary castFrom:value];
        NSDictionary *origin = dict[@"origin"];
        NSDictionary *size = dict[@"size"];
        NSNumber *x = origin[@"x"];
        NSNumber *y = origin[@"y"];
        NSNumber *width = size[@"width"];
        NSNumber *height = size[@"height"];
        if (!x || !y || !width || !height) {
            response.status = ITMSetPropertyResponse_Status_InvalidValue;
            completion(response);
        }
        NSRect rect = NSMakeRect(x.doubleValue, y.doubleValue, width.doubleValue, height.doubleValue);
        [term.window setFrame:rect display:YES];
        response.status = ITMSetPropertyResponse_Status_Ok;
        completion(response);
    };

    void (^setFullScreen)(void) = ^{
        NSNumber *number = [NSNumber castFrom:value];
        if (!number) {
            response.status = ITMSetPropertyResponse_Status_InvalidValue;
            completion(response);
            return;
        }
        BOOL fullscreen = number.boolValue;
        if (!!term.anyFullScreen == !!fullscreen) {
            response.status = ITMSetPropertyResponse_Status_Ok;
            completion(response);
            return;
        }
        [term toggleFullScreenMode:nil completion:^(BOOL ok) {
            if (ok) {
                response.status = ITMSetPropertyResponse_Status_Ok;
            } else {
                response.status = ITMSetPropertyResponse_Status_Failed;
            }
            completion(response);
        }];
    };
    NSDictionary<NSString *, void (^)(void)> *handlers =
        @{ @"frame": setFrame,
           @"fullscreen": setFullScreen };
    void (^block)(void) = handlers[name];
    if (block) {
        block();
    } else {
        response.status = ITMSetPropertyResponse_Status_UnrecognizedName;
        completion(response);
        return;
    }
}

- (ITMSetPropertyResponse_Status)setPropertyInSession:(PTYSession *)session name:(NSString *)name value:(id)value {
    typedef ITMSetPropertyResponse_Status (^SetSessionPropertyBlock)(void);
    SetSessionPropertyBlock setGridSize = ^ITMSetPropertyResponse_Status {
        NSDictionary *size = [NSDictionary castFrom:value];
        NSNumber *width = size[@"width"];
        NSNumber *height = size[@"height"];
        if (!width || !height) {
            return ITMSetPropertyResponse_Status_InvalidValue;
        }
        id<WindowControllerInterface> controller = session.delegate.parentWindow;
        BOOL ok = [controller sessionInitiatedResize:session width:width.integerValue height:height.integerValue];
        if (ok) {
            if ([controller isKindOfClass:[PseudoTerminal class]]) {
                return ITMSetPropertyResponse_Status_Ok;
            } else {
                return ITMSetPropertyResponse_Status_Deferred;
            }
        } else {
            return ITMSetPropertyResponse_Status_Impossible;
        }
    };
    SetSessionPropertyBlock setBuried = ^ITMSetPropertyResponse_Status {
        NSNumber *number = [NSNumber castFrom:value];
        if (!number) {
            return ITMSetPropertyResponse_Status_InvalidValue;
        }
        const BOOL shouldBeBuried = number.boolValue;
        const BOOL isBuried = [[[iTermBuriedSessions sharedInstance] buriedSessions] containsObject:session];
        if (shouldBeBuried == isBuried) {
            return ITMSetPropertyResponse_Status_Ok;
        }
        if (shouldBeBuried) {
            [session bury];
        } else {
            [[iTermBuriedSessions sharedInstance] restoreSession:session];
        }
        return ITMSetPropertyResponse_Status_Ok;
    };
    NSDictionary<NSString *, SetSessionPropertyBlock> *handlers =
        @{ @"grid_size": setGridSize,
           @"buried": setBuried,
         };
    SetSessionPropertyBlock block = handlers[name];
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
            return;
        }

        case ITMGetPropertyRequest_Identifier_OneOfCase_SessionId: {
            PTYSession *session = [self sessionForAPIIdentifier:request.sessionId includeBuriedSessions:YES];
            if (!session) {
                response.status = ITMGetPropertyResponse_Status_InvalidTarget;
                handler(response);
                return;
            }
            NSString *jsonValue = [self getPropertyFromSession:session name:request.name];
            if (jsonValue) {
                response.jsonValue = jsonValue;
                response.status = ITMGetPropertyResponse_Status_Ok;
            } else {
                response.status = ITMGetPropertyResponse_Status_UnrecognizedName;
            }
            handler(response);
            return;
        }
    }
    response.status = ITMGetPropertyResponse_Status_InvalidTarget;
    handler(response);
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
        return [NSJSONSerialization it_jsonStringForObject:dict];
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

- (NSString *)getPropertyFromSession:(PTYSession *)session name:(NSString *)name {
    typedef NSString * (^GetSessionPropertyBlock)(void);

    GetSessionPropertyBlock getGridSize = ^NSString * {
        NSDictionary *dict =
            @{ @"width": @(session.screen.width - 1),
               @"height": @(session.screen.height - 1) };
        return [NSJSONSerialization it_jsonStringForObject:dict];
    };
    GetSessionPropertyBlock getBuried = ^NSString * {
        BOOL isBuried = [[[iTermBuriedSessions sharedInstance] buriedSessions] containsObject:session];
        return [NSJSONSerialization it_jsonStringForObject:@(isBuried)];
    };
    GetSessionPropertyBlock getNumberOfLines = ^NSString * {
        NSDictionary *dict =
            @{ @"overflow": @(session.screen.totalScrollbackOverflow),
               @"grid": @(session.screen.currentGrid.size.height),
               @"history": @(session.screen.numberOfScrollbackLines),
               @"first_visible": @(session.textview.firstVisibleAbsoluteLineNumber) };
        return [NSJSONSerialization it_jsonStringForObject:dict];
    };
    NSDictionary<NSString *, GetSessionPropertyBlock> *handlers =
        @{ @"grid_size": getGridSize,
           @"buried": getBuried,
           @"number_of_lines": getNumberOfLines,
         };

    GetSessionPropertyBlock block = handlers[name];
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
            PTYSession *session = [self sessionForAPIIdentifier:sessionID includeBuriedSessions:YES];
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
        session = [self sessionForAPIIdentifier:request.sessionId includeBuriedSessions:YES];
        if (!session) {
            response.status = ITMActivateResponse_Status_BadIdentifier;
            handler(response);
            return;
        }
        if ([[[iTermBuriedSessions sharedInstance] buriedSessions] containsObject:session]) {
            [[iTermBuriedSessions sharedInstance] restoreSession:session];
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
    const BOOL allSetNamesLegal = [request.setArray allWithBlock:^BOOL(ITMVariableRequest_Set *setRequest) {
        return [setRequest.name hasPrefix:@"user."];
    }];
    if (!allSetNamesLegal) {
        ITMVariableResponse *response = [[ITMVariableResponse alloc] init];
        response.status = ITMVariableResponse_Status_InvalidName;
        handler(response);
        return;
    }
    switch (request.scopeOneOfCase) {
        case ITMVariableRequest_Scope_OneOfCase_App:
            [self handleAppScopeVariableRequest:request handler:handler];
            return;

        case ITMVariableRequest_Scope_OneOfCase_TabId:
            [self handleTabScopeVariableRequest:request handler:handler];
            return;

        case ITMVariableRequest_Scope_OneOfCase_SessionId:
            [self handleSessionScopeVariableRequest:request handler:handler];
            return;

        case ITMVariableRequest_Scope_OneOfCase_GPBUnsetOneOfCase:
            break;
    }
    ITMVariableResponse *response = [[ITMVariableResponse alloc] init];
    response.status = ITMVariableResponse_Status_MissingScope;
    handler(response);
}

- (void)handleAppScopeVariableRequest:(ITMVariableRequest *)request
                              handler:(void (^)(ITMVariableResponse *))handler {
    ITMVariableResponse *response = [[ITMVariableResponse alloc] init];
    [self handleVariableSetsInRequest:request scope:[iTermVariableScope globalsScope]];
    [self handleVariableGetsInRequest:request response:response scope:[iTermVariableScope globalsScope]];
    response.status = ITMVariableResponse_Status_Ok;
    handler(response);
}

- (void)handleTabScopeVariableRequest:(ITMVariableRequest *)request
                              handler:(void (^)(ITMVariableResponse *))handler {
    if ([request.tabId isEqualToString:@"all"]) {
        NSArray<iTermVariableScope *> *scopes = [self.allTabs mapWithBlock:^id(PTYTab *anObject) {
            return anObject.variablesScope;
        }];
        handler([self handleVariableMultiSetRequest:request scopes:scopes]);
        return;
    }

    ITMVariableResponse *response = [[ITMVariableResponse alloc] init];
    PTYTab *tab = [self tabWithID:request.tabId];
    if (!tab) {
        response.status = ITMVariableResponse_Status_TabNotFound;
        handler(response);
        return;
    }

    [self handleVariableSetsInRequest:request scope:tab.variablesScope];
    [self handleVariableGetsInRequest:request response:response scope:tab.variablesScope];

    handler(response);
}


- (void)handleSessionScopeVariableRequest:(ITMVariableRequest *)request
                                  handler:(void (^)(ITMVariableResponse *))handler {
    if ([request.sessionId isEqualToString:@"all"]) {
        NSArray<iTermVariableScope *> *scopes = [self.allSessions mapWithBlock:^id(PTYSession *anObject) {
            return anObject.variablesScope;
        }];
        handler([self handleVariableMultiSetRequest:request scopes:scopes]);
        return;
    }

    ITMVariableResponse *response = [[ITMVariableResponse alloc] init];
    PTYSession *session = [self sessionForAPIIdentifier:request.sessionId includeBuriedSessions:YES];
    if (!session) {
        response.status = ITMVariableResponse_Status_SessionNotFound;
        handler(response);
        return;
    }

    [self handleVariableSetsInRequest:request scope:session.variablesScope];
    [self handleVariableGetsInRequest:request response:response scope:session.variablesScope];

    handler(response);
}

- (void)handleVariableSetsInRequest:(ITMVariableRequest *)request scope:(iTermVariableScope *)scope {
    [request.setArray enumerateObjectsUsingBlock:^(ITMVariableRequest_Set * _Nonnull setRequest, NSUInteger idx, BOOL * _Nonnull stop) {
        id value;
        if ([setRequest.value isEqual:@"null"]) {
            value = nil;
        } else {
            value = [NSJSONSerialization it_objectForJsonString:setRequest.value];
        }
        [scope setValue:value forVariableNamed:setRequest.name];
    }];
}

- (void)handleVariableGetsInRequest:(ITMVariableRequest *)request response:(ITMVariableResponse *)response scope:(iTermVariableScope *)scope {
    [request.getArray enumerateObjectsUsingBlock:^(NSString * _Nonnull name, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([name isEqualToString:@"*"]) {
            NSDictionary *dict = scope.dictionaryWithStringValues;
            [response.valuesArray addObject:[NSJSONSerialization it_jsonStringForObject:dict]];
        } else {
            id obj = [NSJSONSerialization it_jsonStringForObject:[scope valueForVariableName:name]];
            NSString *value = obj ?: @"null";
            [response.valuesArray addObject:value];
        }
    }];
}

- (ITMVariableResponse *)handleVariableMultiSetRequest:(ITMVariableRequest *)request
                                                scopes:(NSArray<iTermVariableScope *> *)scopes {
    ITMVariableResponse *response = [[ITMVariableResponse alloc] init];
    if (request.getArray_Count > 0) {
        response.status = ITMVariableResponse_Status_MultiGetDisallowed;
        return response;
    }
    for (iTermVariableScope *scope in scopes) {
        [self handleVariableSetsInRequest:request scope:scope];
    }
    response.status = ITMVariableResponse_Status_Ok;
    return response;
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
        [[iTermController sharedInstance] saveWindowArrangementForAllWindows:YES name:name];
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

- (void)apiServerListProfiles:(ITMListProfilesRequest *)request handler:(void (^)(ITMListProfilesResponse *))handler {
    ITMListProfilesResponse *response = [[ITMListProfilesResponse alloc] init];
    NSArray<NSString *> *desiredProperties = nil;
    if (request.propertiesArray_Count > 0) {
        desiredProperties = request.propertiesArray;
    }
    NSSet<NSString *> *desiredGuids = nil;
    if (request.guidsArray_Count > 0) {
        desiredGuids = [NSSet setWithArray:request.guidsArray];
    }
    for (Profile *profile in [[ProfileModel sharedInstance] bookmarks]) {
        BOOL matches = NO;
        if (desiredGuids) {
            if ([desiredGuids containsObject:profile[KEY_GUID]]) {
                matches = YES;
            }
        } else {
            matches = YES;
        }
        if (matches) {
            ITMListProfilesResponse_Profile *responseProfile = [[ITMListProfilesResponse_Profile alloc] init];
            NSArray<NSString *> *keys = nil;
            if (desiredProperties == nil) {
                keys = [iTermProfilePreferences allKeys];
            } else {
                keys = desiredProperties;
            }
            for (NSString *key in keys) {
                id value = [iTermProfilePreferences objectForKey:key inProfile:profile];
                if (value) {
                    NSString *jsonString = [iTermProfilePreferences jsonEncodedValueForKey:key inProfile:profile];
                    if (jsonString) {
                        ITMProfileProperty *property = [[ITMProfileProperty alloc] init];
                        property.key = key;
                        property.jsonValue = jsonString;
                        [responseProfile.propertiesArray addObject:property];
                    }
                }
            }
            [response.profilesArray addObject:responseProfile];
        }
    }
    handler(response);
}

- (void)handleServerOriginatedRPCResult:(ITMServerOriginatedRPCResultRequest *)result
                          connectionKey:(NSString *)connectionKey {
    [self.dispatcher serverOriginatedRPCDidReceiveResponseWithResult:result
                                                       connectionKey:connectionKey];
}

- (void)apiServerServerOriginatedRPCResult:(ITMServerOriginatedRPCResultRequest *)request
                             connectionKey:(NSString *)connectionKey
                                   handler:(void (^)(ITMServerOriginatedRPCResultResponse *))handler {
    [self handleServerOriginatedRPCResult:request connectionKey:connectionKey];
    ITMServerOriginatedRPCResultResponse *response = [[ITMServerOriginatedRPCResultResponse alloc] init];
    handler(response);

}

- (void)apiServerRestartSession:(ITMRestartSessionRequest *)request handler:(void (^)(ITMRestartSessionResponse *))handler {
    PTYSession *session = [self sessionForAPIIdentifier:request.sessionId includeBuriedSessions:YES];
    ITMRestartSessionResponse *response = [[ITMRestartSessionResponse alloc] init];
    if (!session) {
        response.status = ITMRestartSessionResponse_Status_SessionNotFound;
        handler(response);
        return;
    }

    if (!session.isRestartable) {
        response.status = ITMRestartSessionResponse_Status_SessionNotRestartable;
        handler(response);
        return;
    }

    if (request.onlyIfExited && !session.exited) {
        response.status = ITMRestartSessionResponse_Status_SessionNotRestartable;
        handler(response);
        return;
    }

    [session restartSession];
    response.status = ITMRestartSessionResponse_Status_Ok;
    handler(response);
    return;
}

- (void)apiServerMenuItem:(ITMMenuItemRequest *)request handler:(void (^)(ITMMenuItemResponse *))handler {
    ITMMenuItemResponse *response = [[ITMMenuItemResponse alloc] init];
    NSMenuItem *menuItem = nil;
    menuItem = [self menuItemWithIdentifier:request.identifier inMenu:[NSApp mainMenu]];
    if (!menuItem) {
        response.status = ITMMenuItemResponse_Status_BadIdentifier;
        handler(response);
        return;
    }
    [menuItem.menu update];
    if (!menuItem.enabled && !request.queryOnly) {
        response.status = ITMMenuItemResponse_Status_Disabled;
        handler(response);
        return;
    }
    response.checked = menuItem.state == NSOnState;
    response.enabled = menuItem.isEnabled;
    if (!request.queryOnly) {
        [NSApp sendAction:menuItem.action
                       to:menuItem.target
                     from:menuItem];
    }
    response.status = ITMMenuItemResponse_Status_Ok;
    handler(response);
}

static BOOL iTermCheckSplitTreesIsomorphic(ITMSplitTreeNode *node1, ITMSplitTreeNode *node2) {
    if (node1.vertical != node2.vertical) {
        return NO;
    }
    if (node1.linksArray_Count != node2.linksArray_Count) {
        return NO;
    }
    for (NSInteger i = 0; i < node1.linksArray_Count; i++) {
        ITMSplitTreeNode_SplitTreeLink *link1 = node1.linksArray[i];
        ITMSplitTreeNode_SplitTreeLink *link2 = node2.linksArray[i];
        if (link1.childOneOfCase == ITMSplitTreeNode_SplitTreeLink_Child_OneOfCase_GPBUnsetOneOfCase) {
            return NO;
        }
        if (link1.childOneOfCase != link2.childOneOfCase) {
            return NO;
        }
        if (link1.childOneOfCase == ITMSplitTreeNode_SplitTreeLink_Child_OneOfCase_Node) {
            if (!iTermCheckSplitTreesIsomorphic(link1.node, link2.node)) {
                return NO;
            }
        }
    }
    return YES;
}

- (void)apiServerSetTabLayout:(ITMSetTabLayoutRequest *)request handler:(void (^)(ITMSetTabLayoutResponse *))handler {
    ITMSetTabLayoutResponse *response = [[ITMSetTabLayoutResponse alloc] init];
    PTYTab *tab = [self tabWithID:request.tabId];
    if (!tab) {
        response.status = ITMSetTabLayoutResponse_Status_BadTabId;
        handler(response);
        return;
    }

    ITMSplitTreeNode *before = [tab rootSplitTreeNode];
    ITMSplitTreeNode *requested = request.root;

    if (!iTermCheckSplitTreesIsomorphic(before, requested)) {
        response.status = ITMSetTabLayoutResponse_Status_WrongTree;
        handler(response);
        return;
    }
    [tab setSizesFromSplitTreeNode:requested];

    response.status = ITMSetTabLayoutResponse_Status_Ok;
    handler(response);
}

- (void)enumerateBroadcastDomains:(void (^)(NSArray<PTYSession *> *))addDomain {
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        switch (term.broadcastMode) {
            case BROADCAST_OFF:
                for (PTYTab *tab in term.tabs) {
                    if (tab.broadcasting) {
                        addDomain(tab.sessions);
                    }
                }
                break;

            case BROADCAST_CUSTOM:
                addDomain(term.broadcastSessions);
                break;

            case BROADCAST_TO_ALL_TABS:
                addDomain(term.allSessions);
                break;

            case BROADCAST_TO_ALL_PANES:
                addDomain(term.currentTab.sessions);
                break;
        }
    }
}

- (void)apiServerGetBroadcastDomains:(ITMGetBroadcastDomainsRequest *)request handler:(void (^)(ITMGetBroadcastDomainsResponse *))handler {
    ITMGetBroadcastDomainsResponse *response = [[ITMGetBroadcastDomainsResponse alloc] init];
    [self enumerateBroadcastDomains:^(NSArray<PTYSession *> *sessions) {
        ITMBroadcastDomain *domain = [[ITMBroadcastDomain alloc] init];
        for (PTYSession *session in sessions) {
            [domain.sessionIdsArray addObject:session.guid];
        }
        [response.broadcastDomainsArray addObject:domain];
    }];
    handler(response);
}

- (void)handleTmuxSendCommand:(ITMTmuxRequest_SendCommand *)request handler:(void (^)(ITMTmuxResponse *))handler {
    ITMTmuxResponse *response = [[ITMTmuxResponse alloc] init];
    TmuxController *controller = [[TmuxControllerRegistry sharedInstance] controllerForClient:request.connectionId];
    if (!controller) {
        response.status = ITMTmuxResponse_Status_InvalidConnectionId;
        handler(response);
        return;
    }

    iTermBlockTargetActionForwarder *forwarder = [[iTermBlockTargetActionForwarder alloc] initWithBlock:^(NSString *result) {
        response.sendCommand.output = result;
        handler(response);
    }];
    [controller.gateway sendCommand:request.command responseTarget:forwarder responseSelector:@selector(selector:)];
    [forwarder attachToOwner:controller.gateway failure:^{
        handler(response);
    }];
}

- (void)handleTmuxListConnections:(ITMTmuxRequest_ListConnections *)request handler:(void (^)(ITMTmuxResponse *))handler {
    ITMTmuxResponse *response = [[ITMTmuxResponse alloc] init];
    for (NSString *clientName in [[TmuxControllerRegistry sharedInstance] clientNames]) {
        ITMTmuxResponse_ListConnections_Connection *connection = [[ITMTmuxResponse_ListConnections_Connection alloc] init];
        connection.connectionId = clientName;
        TmuxController *controller = [[TmuxControllerRegistry sharedInstance] controllerForClient:clientName];
        connection.owningSessionId = [controller.gateway.delegate tmuxOwningSessionGUID];
        [response.listConnections.connectionsArray addObject:connection];
    }
    response.status = ITMTmuxResponse_Status_Ok;
    handler(response);
}

- (void)handleTmuxCreateWindow:(ITMTmuxRequest_CreateWindow *)request handler:(void (^)(ITMTmuxResponse *))handler {
    ITMTmuxResponse *response = [[ITMTmuxResponse alloc] init];
    TmuxController *controller = [[TmuxControllerRegistry sharedInstance] controllerForClient:request.connectionId];
    if (!controller) {
        response.status = ITMTmuxResponse_Status_InvalidConnectionId;
        handler(response);
        return;
    }
    
    [controller newWindowWithAffinity:request.hasAffinity ? request.affinity : nil
                     initialDirectory:[iTermInitialDirectory initialDirectoryFromProfile:controller.profile
                                                                              objectType:iTermWindowObject]
                                scope:[iTermVariableScope globalsScope]
                           completion:^(int newWindowId) {
                               PTYTab *tab = [controller window:newWindowId];
                               response.createWindow.tabId = [NSString stringWithFormat:@"%d", tab.uniqueId];
                               handler(response);
                           }];
}

- (void)handleTmuxSetWindowVisible:(ITMTmuxRequest_SetWindowVisible *)request handler:(void (^)(ITMTmuxResponse *))handler {
    ITMTmuxResponse *response = [[ITMTmuxResponse alloc] init];
    TmuxController *controller = [[TmuxControllerRegistry sharedInstance] controllerForClient:request.connectionId];
    if (!controller) {
        response.status = ITMTmuxResponse_Status_InvalidConnectionId;
        handler(response);
        return;
    }

    if (!request.windowId.isNumeric) {
        response.status = ITMTmuxResponse_Status_InvalidWindowId;
        handler(response);
        return;
    }

    if (request.visible) {
        // Show the window
        if (![controller windowIsHidden:[request.windowId intValue]]) {
            response.status = ITMTmuxResponse_Status_InvalidWindowId;
            handler(response);
            return;
        }

        [controller openWindowWithId:[[request windowId] intValue] intentional:YES];
        response.status = ITMTmuxResponse_Status_Ok;
        handler(response);
        return;
    }
    // Hide the window
    if ([controller windowIsHidden:[request.windowId intValue]]) {
        response.status = ITMTmuxResponse_Status_InvalidWindowId;
        handler(response);
        return;
    }

    [controller hideWindow:request.windowId.intValue];
    response.status = ITMTmuxResponse_Status_Ok;
    handler(response);
}

- (void)apiServerTmuxRequest:(ITMTmuxRequest *)request handler:(void (^)(ITMTmuxResponse *))handler {
    switch (request.payloadOneOfCase) {
        case ITMTmuxRequest_Payload_OneOfCase_SendCommand:
            [self handleTmuxSendCommand:request.sendCommand handler:handler];
            return;
        case ITMTmuxRequest_Payload_OneOfCase_ListConnections:
            [self handleTmuxListConnections:request.listConnections handler:handler];
            return;
        case ITMTmuxRequest_Payload_OneOfCase_SetWindowVisible:
            [self handleTmuxSetWindowVisible:request.setWindowVisible handler:handler];
            return;
        case ITMTmuxRequest_Payload_OneOfCase_CreateWindow:
            [self handleTmuxCreateWindow:request.createWindow handler:handler];
            return;
        case ITMTmuxRequest_Payload_OneOfCase_GPBUnsetOneOfCase:
            break;
    }
    ITMTmuxResponse *response = [[ITMTmuxResponse alloc] init];
    response.status = ITMTmuxResponse_Status_InvalidRequest;
    handler(response);
}

- (ITMReorderTabsResponse_Status)validateReorderTabsRequest:(ITMReorderTabsRequest *)request {
    NSMutableSet<NSString *> *windowIds = [NSMutableSet set];
    NSMutableSet<NSString *> *tabIds = [NSMutableSet set];
    for (ITMReorderTabsRequest_Assignment *assignment in request.assignmentsArray) {
        if ([windowIds containsObject:assignment.windowId]) {
            return ITMReorderTabsResponse_Status_InvalidAssignment;
        }
        PseudoTerminal *term = [[iTermController sharedInstance] terminalWithGuid:assignment.windowId];
        if (!term) {
            return ITMReorderTabsResponse_Status_InvalidWindowId;
        }
        [windowIds addObject:assignment.windowId];
        
        for (NSString *tabid in assignment.tabIdsArray) {
            PTYTab *tab = [self tabWithID:tabid];
            if (!tab) {
                return ITMReorderTabsResponse_Status_InvalidTabId;
            }
            if ([tabIds containsObject:tabid]) {
                return ITMReorderTabsResponse_Status_InvalidAssignment;
            }
            [tabIds addObject:tabid];
        }
    }
    
    return ITMReorderTabsResponse_Status_Ok;
}

- (void)performReorderAssignment:(ITMReorderTabsRequest_Assignment *)assignment {
    PseudoTerminal *destination = [[iTermController sharedInstance] terminalWithGuid:assignment.windowId];
    assert(destination);
    
    NSInteger index = 0;
    for (NSString *tabId in assignment.tabIdsArray) {
        PTYTab *tab = [self tabWithID:tabId];
        assert(tab);

        PseudoTerminal *source = (PseudoTerminal *)tab.realParentWindow;
        if (source == destination) {
            NSInteger sourceIndex = [source.tabs indexOfObject:tab];
            assert(sourceIndex != NSNotFound);
            [source moveTabAtIndex:sourceIndex toIndex:index];
        } else {
            for (PTYSession *aSession in tab.sessions) {
                [aSession setIgnoreResizeNotifications:YES];
            }
            [source.tabView removeTabViewItem:tab.tabViewItem];
            
            [destination insertTab:tab atIndex:index];
            [source didDonateTab:tab toWindowController:destination];
            if (source.tabs.count == 0) {
                [source.window close];
            }
        }
        index++;
    }
}

- (void)apiServerReorderTabsRequest:(ITMReorderTabsRequest *)request handler:(void (^)(ITMReorderTabsResponse *))handler {
    ITMReorderTabsResponse *response = [[ITMReorderTabsResponse alloc] init];
    response.status = [self validateReorderTabsRequest:request];
    if (response.status != ITMReorderTabsResponse_Status_Ok) {
        handler(response);
        return;
    }
    for (ITMReorderTabsRequest_Assignment *assignment in request.assignmentsArray) {
        [self performReorderAssignment:assignment];
    }
    handler(response);
}

- (void)apiServerPreferencesRequest:(ITMPreferencesRequest *)request handler:(void (^)(ITMPreferencesResponse *))handler {
    ITMPreferencesResponse *response = [[ITMPreferencesResponse alloc] init];

    [request.requestsArray enumerateObjectsUsingBlock:^(ITMPreferencesRequest_Request * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        ITMPreferencesResponse_Result *result = [self handlePreferencesRequest:obj];
        [response.resultsArray addObject:result];
    }];

    handler(response);
}

- (ITMPreferencesResponse_Result *)handlePreferencesRequest:(ITMPreferencesRequest_Request *)request {
    ITMPreferencesResponse_Result *result = [[ITMPreferencesResponse_Result alloc] init];
    switch (request.requestOneOfCase) {
        case ITMPreferencesRequest_Request_Request_OneOfCase_GetPreferenceRequest:
            result.getPreferenceResult = [self handleGetPreferenceRequestForKey:request.getPreferenceRequest.key];
            break;

        case ITMPreferencesRequest_Request_Request_OneOfCase_GPBUnsetOneOfCase:
            result.unrecognizedRequest = [[ITMPreferencesResponse_Result_UnrecognizedResult alloc] init];
            break;

        case ITMPreferencesRequest_Request_Request_OneOfCase_SetPreferenceRequest:
            result.setPreferenceResult = [self handleSetPreferenceRequestWithKey:request.setPreferenceRequest.key
                                                                       jsonValue:request.setPreferenceRequest.jsonValue];
            break;
        case ITMPreferencesRequest_Request_Request_OneOfCase_SetDefaultProfileRequest:
            result.setDefaultProfileResult = [self handleSetDefaultProfileWithGUID:request.setDefaultProfileRequest.guid];
            break;
    }
    return result;
}

- (ITMPreferencesResponse_Result_GetPreferenceResult *)handleGetPreferenceRequestForKey:(NSString *)key {
    ITMPreferencesResponse_Result_GetPreferenceResult *result = [[ITMPreferencesResponse_Result_GetPreferenceResult alloc] init];
    id obj = [iTermPreferences objectForKey:key];
    NSString *json = [NSJSONSerialization it_jsonStringForObject:obj];
    result.jsonValue = json;
    return result;
}

- (ITMPreferencesResponse_Result_SetPreferenceResult *)handleSetPreferenceRequestWithKey:(NSString *)key
                                                                               jsonValue:(NSString *)jsonValue {
    ITMPreferencesResponse_Result_SetPreferenceResult *result = [[ITMPreferencesResponse_Result_SetPreferenceResult alloc] init];
    NSError *error = nil;
    id obj = [NSJSONSerialization it_objectForJsonString:jsonValue error:&error];
    if (error) {
        result.status = ITMPreferencesResponse_Result_SetPreferenceResult_Status_BadJson;
        return result;
    }
    if (![obj it_isSafeForPlist]) {
        result.status = ITMPreferencesResponse_Result_SetPreferenceResult_Status_InvalidValue;
        return result;
    }
    if (!obj) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    } else {
        [[NSUserDefaults standardUserDefaults] setObject:obj forKey:key];
    }
    result.status = ITMPreferencesResponse_Result_SetPreferenceResult_Status_Ok;

    return result;
}

- (ITMPreferencesResponse_Result_SetDefaultProfileResult *)handleSetDefaultProfileWithGUID:(NSString *)guid {
    ITMPreferencesResponse_Result_SetDefaultProfileResult *result = [[ITMPreferencesResponse_Result_SetDefaultProfileResult alloc] init];
    Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    if (!profile) {
        result.status = ITMPreferencesResponse_Result_SetDefaultProfileResult_Status_BadGuid;
        return result;
    }
    [[ProfileModel sharedInstance] setDefaultByGuid:guid];
    result.status = ITMPreferencesResponse_Result_SetDefaultProfileResult_Status_Ok;
    return result;
}

- (void)apiServerColorPresetRequest:(ITMColorPresetRequest *)request handler:(void (^)(ITMColorPresetResponse *))response {
    switch (request.requestOneOfCase) {
        case ITMColorPresetRequest_Request_OneOfCase_GetPreset:
            [self handleGetPreset:request.getPreset completion:response];
            return;

        case ITMColorPresetRequest_Request_OneOfCase_ListPresets:
            [self handleListPresets:request.listPresets completion:response];
            return;

        case ITMColorPresetRequest_Request_OneOfCase_GPBUnsetOneOfCase:
            break;
    }
    ITMColorPresetResponse *message = [[ITMColorPresetResponse alloc] init];
    message.status = ITMColorPresetResponse_Status_RequestMalformed;
    response(message);
}

- (void)handleGetPreset:(ITMColorPresetRequest_GetPreset *)request completion:(void (^)(ITMColorPresetResponse *))completion {
    ITMColorPresetResponse *message = [[ITMColorPresetResponse alloc] init];
    iTermColorPreset *preset = [iTermColorPresets presetWithName:request.name];
    if (!preset) {
        message.status = ITMColorPresetResponse_Status_PresetNotFound;
        completion(message);
        return;
    }

    for (NSString *key in preset) {
        ITMColorPresetResponse_GetPreset_ColorSetting *colorSetting = [self colorSettingForDictionary:preset[key] key:key];
        [message.getPreset.colorSettingsArray addObject:colorSetting];
    }
    message.status = ITMColorPresetResponse_Status_Ok;
    completion(message);
}

- (ITMColorPresetResponse_GetPreset_ColorSetting *)colorSettingForDictionary:(iTermColorDictionary *)dict key:(NSString *)key {
    ITMColorPresetResponse_GetPreset_ColorSetting *setting = [[ITMColorPresetResponse_GetPreset_ColorSetting alloc] init];
    setting.key = key;
    NSNumber *obj;
    obj = dict[kEncodedColorDictionaryRedComponent];
    if (obj) {
        setting.red = [obj doubleValue];
    }
    obj = dict[kEncodedColorDictionaryGreenComponent];
    if (obj) {
        setting.green = [obj doubleValue];
    }
    obj = dict[kEncodedColorDictionaryBlueComponent];
    if (obj) {
        setting.blue = [obj doubleValue];
    }
    obj = dict[kEncodedColorDictionaryAlphaComponent] ?: @([NSDictionary defaultAlphaForColorPresetKey:key]);
    setting.alpha = [obj doubleValue];

    NSString *colorSpace = dict[kEncodedColorDictionaryColorSpace] ?: kEncodedColorDictionaryCalibratedColorSpace;
    setting.colorSpace = colorSpace;
    
    return setting;
}

- (void)handleListPresets:(ITMColorPresetRequest_ListPresets *)request completion:(void (^)(ITMColorPresetResponse *))completion {
    ITMColorPresetResponse *message = [[ITMColorPresetResponse alloc] init];
    for (NSString *name in [iTermColorPresets allColorPresets]) {
        [message.listPresets.nameArray addObject:name];
    }
    message.status = ITMColorPresetResponse_Status_Ok;
    completion(message);
}

- (void)apiServerSelectionRequest:(ITMSelectionRequest *)request handler:(void (^)(ITMSelectionResponse *))completion {
    switch (request.requestOneOfCase) {
        case ITMSelectionRequest_Request_OneOfCase_GetSelectionRequest:
            [self handleGetSelectionRequest:request.getSelectionRequest completion:completion];
            return;

        case ITMSelectionRequest_Request_OneOfCase_SetSelectionRequest:
            [self handleSetSelectionRequest:request.setSelectionRequest completion:completion];
            return;

        case ITMSelectionRequest_Request_OneOfCase_GPBUnsetOneOfCase:
            break;
    }

    ITMSelectionResponse *response = [[ITMSelectionResponse alloc] init];
    response.status = ITMSelectionResponse_Status_RequestMalformed;
    completion(response);
}

- (void)handleGetSelectionRequest:(ITMSelectionRequest_GetSelectionRequest *)request
                       completion:(void (^)(ITMSelectionResponse *))completion {
    PTYSession *session = [self sessionForAPIIdentifier:request.sessionId includeBuriedSessions:YES];
    ITMSelectionResponse *response = [[ITMSelectionResponse alloc] init];
    if (!session) {
        response.status = ITMSelectionResponse_Status_RequestMalformed;
        completion(response);
        return;
    }

    iTermSelection *selection = session.textview.selection;
    const NSInteger absoluteOffset = session.screen.totalScrollbackOverflow;
    for (iTermSubSelection *sub in selection.allSubSelections) {
        ITMSubSelection *subProto = [[ITMSubSelection alloc] init];
        subProto.windowedCoordRange.coordRange.start.x = sub.range.coordRange.start.x;
        subProto.windowedCoordRange.coordRange.start.y = absoluteOffset + sub.range.coordRange.start.y;
        subProto.windowedCoordRange.coordRange.end.x = sub.range.coordRange.end.x;
        subProto.windowedCoordRange.coordRange.end.y = absoluteOffset + sub.range.coordRange.end.y;
        subProto.connected = sub.connected;
        if (sub.range.columnWindow.length > 0) {
            subProto.windowedCoordRange.columns.location = sub.range.columnWindow.location;
            subProto.windowedCoordRange.columns.length = sub.range.columnWindow.length;
        }
        switch (sub.selectionMode) {
            case kiTermSelectionModeWholeLine:
                subProto.selectionMode = ITMSelectionMode_WholeLine;
                break;
            case kiTermSelectionModeCharacter:
                subProto.selectionMode = ITMSelectionMode_Character;
                break;
            case kiTermSelectionModeSmart:
                subProto.selectionMode = ITMSelectionMode_Smart;
                break;
            case kiTermSelectionModeWord:
                subProto.selectionMode = ITMSelectionMode_Word;
                break;
            case kiTermSelectionModeLine:
                subProto.selectionMode = ITMSelectionMode_Line;
                break;
            case kiTermSelectionModeBox:
                subProto.selectionMode = ITMSelectionMode_Box;
                break;
        }
        [response.getSelectionResponse.selection.subSelectionsArray addObject:subProto];
    }
    response.status = ITMSelectionResponse_Status_Ok;
    completion(response);
}

- (void)handleSetSelectionRequest:(ITMSelectionRequest_SetSelectionRequest *)request
                       completion:(void (^)(ITMSelectionResponse *))completion {
    PTYSession *session = [self sessionForAPIIdentifier:request.sessionId includeBuriedSessions:YES];
    ITMSelectionResponse *response = [[ITMSelectionResponse alloc] init];
    if (!session) {
        response.status = ITMSelectionResponse_Status_RequestMalformed;
        completion(response);
        return;
    }

    const NSInteger absoluteOffset = session.screen.totalScrollbackOverflow;
    const NSInteger width = session.screen.width;
    NSArray<iTermSubSelection *> *subSelections = [request.selection.subSelectionsArray mapWithBlock:^id(ITMSubSelection *subProto) {
        if (subProto.windowedCoordRange.coordRange.end.x > width ||
            subProto.windowedCoordRange.columns.length < 0 ||
            subProto.windowedCoordRange.columns.location + subProto.windowedCoordRange.columns.length > width ||
            subProto.windowedCoordRange.coordRange.start.x < 0 ||
            subProto.windowedCoordRange.columns.location < 0 ||
            subProto.windowedCoordRange.coordRange.start.y < 0 ||
            subProto.windowedCoordRange.coordRange.end.y < 0) {
            return nil;
        }
        VT100GridCoordRange coordRange = VT100GridCoordRangeMake(subProto.windowedCoordRange.coordRange.start.x,
                                                                 MAX(0, subProto.windowedCoordRange.coordRange.start.y - absoluteOffset),
                                                                 subProto.windowedCoordRange.coordRange.end.x,
                                                                 MAX(0, subProto.windowedCoordRange.coordRange.end.y - absoluteOffset));
        VT100GridWindowedRange range = VT100GridWindowedRangeMake(coordRange,
                                                                  subProto.windowedCoordRange.columns.location,
                                                                  subProto.windowedCoordRange.columns.length);
        iTermSelectionMode mode = NSNotFound;
        switch (subProto.selectionMode) {
            case ITMSelectionMode_Box:
                mode = kiTermSelectionModeBox;
                break;
            case ITMSelectionMode_Line:
                mode = kiTermSelectionModeLine;
                break;
            case ITMSelectionMode_Word:
                mode = kiTermSelectionModeWord;
                break;
            case ITMSelectionMode_Smart:
                mode = kiTermSelectionModeSmart;
                break;
            case ITMSelectionMode_Character:
                mode = kiTermSelectionModeCharacter;
                break;
            case ITMSelectionMode_WholeLine:
                mode = kiTermSelectionModeWholeLine;
                break;
        }
        if (mode == NSNotFound) {
            return nil;
        }
        iTermSubSelection *sub = [iTermSubSelection subSelectionWithRange:range mode:mode width:width];
        return sub;
    }];

    if (subSelections.count < request.selection.subSelectionsArray.count) {
        response.status = ITMSelectionResponse_Status_RequestMalformed;
        completion(response);
        return;
    }

    [session.textview.selection endLiveSelection];
    [session.textview.selection clearSelection];
    [session.textview.selection addSubSelections:subSelections];

    response.status = ITMSelectionResponse_Status_Ok;
    completion(response);
}

- (void)apiServerStatusBarComponentRequest:(ITMStatusBarComponentRequest *)request
                                   handler:(void (^)(ITMStatusBarComponentResponse *))completion {
    switch (request.requestOneOfCase) {
        case ITMStatusBarComponentRequest_Request_OneOfCase_OpenPopover:
            [self handleOpenStatusBarPopoverRequest:request.openPopover
                                         identifier:request.identifier
                                         completion:completion];
            return;
        case ITMStatusBarComponentRequest_Request_OneOfCase_GPBUnsetOneOfCase:
            break;
    }
    ITMStatusBarComponentResponse *response = [[ITMStatusBarComponentResponse alloc] init];
    response.status = ITMStatusBarComponentResponse_Status_RequestMalformed;
    completion(response);
}

- (void)handleOpenStatusBarPopoverRequest:(ITMStatusBarComponentRequest_OpenPopover *)request
                               identifier:(NSString *)identifier
                               completion:(void (^)(ITMStatusBarComponentResponse *))completion {
    ITMStatusBarComponentResponse *response = [[ITMStatusBarComponentResponse alloc] init];
    PTYSession *session = [self sessionForAPIIdentifier:request.sessionId includeBuriedSessions:YES];
    if (!session) {
        response.status = ITMStatusBarComponentResponse_Status_SessionNotFound;
        completion(response);
        return;
    }

    id<iTermStatusBarComponent> component = [session.statusBarViewController componentWithIdentifier:identifier];
    if (!component) {
        response.status = ITMStatusBarComponentResponse_Status_InvalidIdentifier;
        completion(response);
        return;
    }
    [component statusBarComponentOpenPopoverWithHTML:request.html ofSize:NSMakeSize(request.size.width, request.size.height)];

    response.status = ITMStatusBarComponentResponse_Status_Ok;
    completion(response);
    return;
}

- (void)apiServerSetBroadcastDomainsRequest:(ITMSetBroadcastDomainsRequest *)request handler:(void (^)(ITMSetBroadcastDomainsResponse *))completion {
    ITMSetBroadcastDomainsResponse *response = [self handleSetBroadcastDomains:request];
    completion(response);
}

- (ITMSetBroadcastDomainsResponse *)handleSetBroadcastDomains:(ITMSetBroadcastDomainsRequest *)request {
    ITMSetBroadcastDomainsResponse *response = [[ITMSetBroadcastDomainsResponse alloc] init];

    // Check validity
    NSMutableSet<NSString *> *sessionIDs = [NSMutableSet set];
    NSMutableArray<NSArray<PTYSession *> *> *sessionGroups = [NSMutableArray array];
    NSMutableArray *windowControllers = [NSMutableArray array];
    for (ITMBroadcastDomain *domain in request.broadcastDomainsArray) {
        NSMutableArray<PTYSession *> *sessions = [NSMutableArray array];
        id<iTermWindowController> windowController = nil;
        for (NSString *sessionID in domain.sessionIdsArray) {
            if ([sessionIDs containsObject:sessionID]) {
                response.status = ITMSetBroadcastDomainsResponse_Status_BroadcastDomainsNotDisjoint;
                return response;
            }
            PTYSession *session = [self sessionForAPIIdentifier:sessionID includeBuriedSessions:YES];
            if (!session) {
                response.status = ITMSetBroadcastDomainsResponse_Status_SessionNotFound;
                return response;
            }
            id<iTermWindowController> thisWindowController = [session.delegate realParentWindow];
            if (!windowController) {
                windowController = thisWindowController;
            } else if (windowController != thisWindowController) {
                response.status = ITMSetBroadcastDomainsResponse_Status_SessionsNotInSameWindow;
                return response;
            }
            [sessions addObject:session];
        }
        if (sessions.count) {
            [sessionGroups addObject:sessions];
            [windowControllers addObject:sessions.firstObject.delegate.realParentWindow];
        }
    }

    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        if (![windowControllers containsObject:term]) {
            [term setBroadcastingSessions:@[]];
            continue;
        }
        for (NSArray<PTYSession *> *sessions in sessionGroups) {
            PseudoTerminal *windowController = [PseudoTerminal castFrom:[sessions.firstObject.delegate realParentWindow]];
            [windowController setBroadcastingSessions:sessions];
        }
    }
    response.status = ITMSetBroadcastDomainsResponse_Status_Ok;
    return response;
}

- (void)apiServerCloseRequest:(ITMCloseRequest *)request handler:(void (^)(ITMCloseResponse *))completion {
    ITMCloseResponse *response = [[ITMCloseResponse alloc] init];
    for (NSString *windowID in request.windows.windowIdsArray) {
        PseudoTerminal *term = [[iTermController sharedInstance] terminalWithGuid:windowID];
        if (!term) {
            [response.statusesArray addValue:ITMCloseResponse_Status_NotFound];
            continue;
        }
        if (request.force) {
            [term.window close];
            [response.statusesArray addValue:ITMCloseResponse_Status_Ok];
            continue;
        }
        if (![term windowShouldClose:term.window]) {
            [response.statusesArray addValue:ITMCloseResponse_Status_UserDeclined];
            continue;
        }

        [term.window close];
        [response.statusesArray addValue:ITMCloseResponse_Status_Ok];
    }
    for (NSString *tabID in request.tabs.tabIdsArray) {
        PTYTab *tab = [self tabWithID:tabID];
        if (!tab) {
            [response.statusesArray addValue:ITMCloseResponse_Status_NotFound];
            continue;
        }
        PseudoTerminal *term = [PseudoTerminal castFrom:tab.realParentWindow];
        if (!term) {
            DLog(@"Strange, the tab's window is not a PseudoTerminal");
            [response.statusesArray addValue:ITMCloseResponse_Status_NotFound];
            continue;
        }
        if (request.force) {
            [term removeTab:tab];
            [response.statusesArray addValue:ITMCloseResponse_Status_Ok];
            continue;
        }
        if ([term closeTabIfConfirmed:tab]) {
            [response.statusesArray addValue:ITMCloseResponse_Status_Ok];
        } else {
            [response.statusesArray addValue:ITMCloseResponse_Status_UserDeclined];
        }
    }
    for (NSString *sessionID in request.sessions.sessionIdsArray) {
        PTYSession *session = [self sessionForAPIIdentifier:sessionID includeBuriedSessions:YES];
        if (!session) {
            [response.statusesArray addValue:ITMCloseResponse_Status_NotFound];
            continue;
        }
        if ([[[iTermBuriedSessions sharedInstance] buriedSessions] containsObject:session]) {
            [[iTermBuriedSessions sharedInstance] restoreSession:session];
        }
        PseudoTerminal *term = [[iTermController sharedInstance] terminalWithSession:session];
        if (request.force) {
            [term closeSessionWithoutConfirmation:session];
            [response.statusesArray addValue:ITMCloseResponse_Status_Ok];
            continue;
        }
        if (![term closeSessionWithConfirmation:session]) {
            [response.statusesArray addValue:ITMCloseResponse_Status_UserDeclined];
            continue;
        }
        [response.statusesArray addValue:ITMCloseResponse_Status_Ok];
    }
    completion(response);
}

- (void)apiServerInvokeFunctionRequest:(ITMInvokeFunctionRequest *)request handler:(void (^)(ITMInvokeFunctionResponse *))completion {

    switch (request.contextOneOfCase) {
        case ITMInvokeFunctionRequest_Context_OneOfCase_App:
            [self invokeFunction:request.invocation inAppContextWithCompletion:completion timeout:request.timeout];
            return;
        case ITMInvokeFunctionRequest_Context_OneOfCase_Tab:
            [self invokeFunction:request.invocation inTabWithID:request.tab.tabId completion:completion timeout:request.timeout];
            return;
        case ITMInvokeFunctionRequest_Context_OneOfCase_Window:
            [self invokeFunction:request.invocation inWindowWithID:request.window.windowId completion:completion timeout:request.timeout];
            return;
        case ITMInvokeFunctionRequest_Context_OneOfCase_Session:
            [self invokeFunction:request.invocation inSessionWithID:request.session.sessionId completion:completion timeout:request.timeout];
            return;

        case ITMInvokeFunctionRequest_Context_OneOfCase_GPBUnsetOneOfCase:
            break;
    }

    ITMInvokeFunctionResponse *response = [[ITMInvokeFunctionResponse alloc] init];
    response.error.status = ITMInvokeFunctionResponse_Status_RequestMalformed;
    response.error.errorReason = @"Invalid context";
    completion(response);
}

- (void)invokeFunction:(NSString *)invocation inAppContextWithCompletion:(void (^)(ITMInvokeFunctionResponse *))completion timeout:(NSTimeInterval)timeout {
    [iTermScriptFunctionCall callFunction:invocation
                                  timeout:timeout >= 0 ? timeout : 30
                                    scope:[iTermVariableScope globalsScope]
                               completion:^(id object, NSError *error, NSSet<NSString *> *missing) {
                                   [self functionInvocationDidCompleteWithObject:object error:error completion:completion];
                               }];
}

- (void)invokeFunction:(NSString *)invocation inTabWithID:(NSString *)tabId completion:(void (^)(ITMInvokeFunctionResponse *))completion timeout:(NSTimeInterval)timeout {
    PTYTab *tab = [self tabWithID:tabId];
    if (!tab) {
        ITMInvokeFunctionResponse *response = [[ITMInvokeFunctionResponse alloc] init];
        response.error.status = ITMInvokeFunctionResponse_Status_InvalidId;
        response.error.errorReason = @"No such tab";
        completion(response);
        return;
    }
    [iTermScriptFunctionCall callFunction:invocation
                                  timeout:timeout >= 0 ? timeout : 30
                                    scope:tab.variablesScope
                               completion:^(id object, NSError *error, NSSet<NSString *> *missing) {
                                   [self functionInvocationDidCompleteWithObject:object error:error completion:completion];
                               }];
}

- (void)invokeFunction:(NSString *)invocation inWindowWithID:(NSString *)windowId completion:(void (^)(ITMInvokeFunctionResponse *))completion timeout:(NSTimeInterval)timeout {
    PseudoTerminal *term = [self windowControllerWithID:windowId];
    if (!term) {
        ITMInvokeFunctionResponse *response = [[ITMInvokeFunctionResponse alloc] init];
        response.error.status = ITMInvokeFunctionResponse_Status_InvalidId;
        response.error.errorReason = @"No such window";
        completion(response);
        return;
    }
    [iTermScriptFunctionCall callFunction:invocation
                                  timeout:timeout >= 0 ? timeout : 30
                                    scope:term.scope
                               completion:^(id object, NSError *error, NSSet<NSString *> *missing) {
                                   [self functionInvocationDidCompleteWithObject:object error:error completion:completion];
                               }];
}

- (void)invokeFunction:(NSString *)invocation inSessionWithID:(NSString *)sessionId completion:(void (^)(ITMInvokeFunctionResponse *))completion timeout:(NSTimeInterval)timeout {
    PTYSession *session = [self sessionForAPIIdentifier:sessionId includeBuriedSessions:YES];
    if (!session) {
        ITMInvokeFunctionResponse *response = [[ITMInvokeFunctionResponse alloc] init];
        response.error.status = ITMInvokeFunctionResponse_Status_InvalidId;
        response.error.errorReason = @"No such session";
        completion(response);
        return;
    }
    [iTermScriptFunctionCall callFunction:invocation
                                  timeout:timeout >= 0 ? timeout : 30
                                    scope:session.variablesScope
                               completion:^(id object, NSError *error, NSSet<NSString *> *missing) {
                                   [self functionInvocationDidCompleteWithObject:object error:error completion:completion];
                               }];
}

- (void)functionInvocationDidCompleteWithObject:(id)object
                                          error:(NSError *)error
                                     completion:(void (^)(ITMInvokeFunctionResponse *))completion {
    ITMInvokeFunctionResponse *response = [[ITMInvokeFunctionResponse alloc] init];
    if (error) {
        if ([error.domain isEqualToString:@"com.iterm2.call"] && error.code == 2) {
            response.error.status = ITMRPCRegistrationRequest_FieldNumber_Timeout;
        } else {
            response.error.status = ITMInvokeFunctionResponse_Status_Failed;
            response.error.errorReason = error.localizedDescription;
        }
        completion(response);
        return;
    }

    NSString *json = [NSJSONSerialization it_jsonStringForObject:object];
    response.success.jsonResult = json;
    completion(response);
}

#pragma mark - iTermAPINotificationControllerDelegate

- (void)apiNotificationControllerPostNotification:(ITMNotification *)notification
                                    connectionKey:(NSString *)key {
    [self postAPINotification:notification toConnectionKey:key];
}

- (PTYTab *)apiNotificationControllerTabWithID:(NSString *)tabID {
    return [self tabWithID:tabID];
}

- (PseudoTerminal *)apiNotificationControllerWindowControllerWithID:(NSString *)windowID {
    return [self windowControllerWithID:windowID];
}

- (PTYSession *)apiNotificationControllerSessionForAPIIdentifier:(NSString *)identifier
                                           includeBuriedSessions:(BOOL)includeBuriedSessions {
    return [self sessionForAPIIdentifier:identifier includeBuriedSessions:includeBuriedSessions];
}

- (ITMListSessionsResponse *)apiNotificationControllerListSessionsResponse {
    return [self newListSessionsResponse];
}

- (void)apiNotificationControllerLogToConnectionWithKey:(NSString *)connectionKey
                                                 string:(NSString *)string {
    [self logToConnectionWithKey:connectionKey string:string];
}

- (NSString *)apiNotificationControllerFullPathOfScriptWithConnectionKey:(NSString *)connectionKey {
    NSString *key = connectionKey ? [_apiServer websocketKeyForConnectionKey:connectionKey] : nil;
    iTermScriptHistoryEntry *entry = key ? [[iTermScriptHistory sharedInstance] entryWithIdentifier:key] : nil;
    if (!entry) {
        return nil;
    }
    return entry.fullPath;
}

- (NSArray<PTYSession *> *)apiNotificationControllerAllSessions {
    return [self allSessions];
}

- (void)apiNotificationControllerEnumerateBroadcastDomains:(void (^)(NSArray<PTYSession *> *))addDomain {
    [self enumerateBroadcastDomains:addDomain];
}

@end
