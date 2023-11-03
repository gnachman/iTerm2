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
#import "iTermBuriedSessions.h"
#import "iTermBuiltInFunctions.h"
#import "iTermColorPresets.h"
#import "iTermController.h"
#import "iTermDisclosableView.h"
#import "iTermLSOF.h"
#import "iTermKeyMappings.h"
#import "iTermMalloc.h"
#import "iTermObject.h"
#import "iTermPreferences.h"
#import "iTermProfileModelJournal.h"
#import "iTermProfilePreferences.h"
#import "iTermPythonArgumentParser.h"
#import "iTermScriptConsole.h"
#import "iTermScriptFunctionCall.h"
#import "iTermScriptHistory.h"
#import "iTermSelection.h"
#import "iTermSessionLauncher.h"
#import "iTermStatusBarComponent.h"
#import "iTermStatusBarViewController.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope+Global.h"
#import "iTermWarning.h"
#import "MovePaneController.h"
#import "NSApplication+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSData+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "PreferencePanel.h"
#import "ProfileModel.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "TmuxController.h"
#import "TmuxControllerRegistry.h"
#import "TmuxGateway.h"
#import "WindowControllerInterface.h"
#import "VT100Parser.h"

NSString *const iTermRemoveAPIServerSubscriptionsNotification = @"iTermRemoveAPIServerSubscriptionsNotification";
NSString *const iTermAPIRegisteredFunctionsDidChangeNotification = @"iTermAPIRegisteredFunctionsDidChangeNotification";
NSString *const iTermAPIDidRegisterSessionTitleFunctionNotification = @"iTermAPIDidRegisterSessionTitleFunctionNotification";
NSString *const iTermAPIDidRegisterStatusBarComponentNotification = @"iTermAPIDidRegisterStatusBarComponentNotification";
NSString *const iTermAPIHelperDidStopNotification = @"iTermAPIHelperDidStopNotification";
static NSString *const iTermAPIHelperEnablePythonAPIWarningIdentifier = @"NoSyncEnableAPIServer";
NSString *const iTermAPIHelperErrorDomain = @"com.iterm2.api";
static NSString *const iTermAPIHelperDisableApplescriptAuthMagic = @"61DF88DC-3423-4823-B725-22570E01C027";
NSString *const iTermAPIHelperDidDetectChangeOfPythonAuthMethodNotification = @"iTermAPIHelperDidDetectChangeOfPythonAuthMethodNotification";

NSString *const iTermAPIHelperFunctionCallErrorUserInfoKeyConnection = @"iTermAPIHelperFunctionCallErrorUserInfoKeyConnection";

static iTermAPIHelper *sAPIHelperInstance;
static BOOL iTermAPIHelperLastApplescriptAuthRequiredSetting;

@interface iTermAllObjectsSubscription : NSObject
@property (nonatomic, strong) ITMNotificationRequest *request;
@property (nonatomic, copy) NSString *connectionKey;
@end

@implementation iTermSessionTitleProvider

- (instancetype)initWithNotificationRequest:(ITMNotificationRequest *)req {
    self = [super init];
    if (self) {
        if (req.rpcRegistrationRequest.role != ITMRPCRegistrationRequest_Role_SessionTitle) {
            return nil;
        }
        _invocation = [self invocationOfRegistrationRequest:req.rpcRegistrationRequest];
        if (!_invocation) {
            return nil;
        }
        _displayName = [req.rpcRegistrationRequest.sessionTitleAttributes.displayName copy];
        if (!_displayName) {
            return nil;
        }
        _uniqueIdentifier = req.rpcRegistrationRequest.sessionTitleAttributes.uniqueIdentifier;
        if (!_uniqueIdentifier) {
            return nil;
        }
    }
    return self;
}

- (NSString *)invocationOfRegistrationRequest:(ITMRPCRegistrationRequest *)req {
    return [iTermAPIHelper invocationWithFullyQualifiedName:req.it_fullyQualifiedName
                                                   defaults:req.defaultsArray];
}

@end

@implementation ITMRPCRegistrationRequest(Extensions)

- (BOOL)it_rpcRegistrationRequestValidWithError:(out NSError **)error {
    NSCharacterSet *ascii = [NSCharacterSet characterSetWithRange:NSMakeRange(0, 128)];
    NSMutableCharacterSet *invalidIdentifierCharacterSet = [NSMutableCharacterSet alphanumericCharacterSet];
    [invalidIdentifierCharacterSet addCharactersInString:@"_"];
    [invalidIdentifierCharacterSet formIntersectionWithCharacterSet:ascii];
    [invalidIdentifierCharacterSet invert];

    NSError *(^newErrorWithReason)(NSString *) = ^NSError *(NSString *reason) {
        NSDictionary *userinfo = @{ NSLocalizedDescriptionKey: reason };
        return [NSError errorWithDomain:iTermAPIHelperErrorDomain
                                   code:iTermAPIHelperErrorCodeRegistrationFailed
                               userInfo:userinfo];
    };
    if (self.name.length == 0) {
        if (error) {
            *error = newErrorWithReason(@"Name has length 0");
        }
        return NO;
    }
    if ([self.name rangeOfCharacterFromSet:invalidIdentifierCharacterSet].location != NSNotFound) {
        if (error) {
            *error = newErrorWithReason([NSString stringWithFormat:@"Function name '%@' contains an invalid character. Must match /[A-Za-z0-9_]/", self.name]);
        }
        return NO;
    }
    NSMutableSet<NSString *> *args = [NSMutableSet set];
    for (ITMRPCRegistrationRequest_RPCArgumentSignature *arg in self.argumentsArray) {
        NSString *name = arg.name;
        if (name.length == 0) {
            if (error) {
                *error = newErrorWithReason(@"Argument has 0-length name");
            }
            return NO;
        }
        if ([name rangeOfCharacterFromSet:invalidIdentifierCharacterSet].location != NSNotFound) {
            if (error) {
                *error = newErrorWithReason([NSString stringWithFormat:@"Argument name '%@' contains an invalid character. Must match /[A-Za-z0-9_]/", name]);
            }
            return NO;
        }
        if ([args containsObject:name]) {
            if (error) {
                *error = newErrorWithReason([NSString stringWithFormat:@"Two arguments share the name '%@'. Argument names must be unique.", name]);
            }
            return NO;
        }
        [args addObject:name];
    }

    return YES;
}

- (NSString *)it_namespace {
    switch (self.roleSpecificAttributesOneOfCase) {
        case ITMRPCRegistrationRequest_RoleSpecificAttributes_OneOfCase_GPBUnsetOneOfCase:
            return nil;
            break;
        case ITMRPCRegistrationRequest_RoleSpecificAttributes_OneOfCase_SessionTitleAttributes:
            return [NSString stringWithFormat:@"title.%@", [self.sessionTitleAttributes.uniqueIdentifier stringByReplacingOccurrencesOfString:@"-" withString:@"_"]];
        case ITMRPCRegistrationRequest_RoleSpecificAttributes_OneOfCase_StatusBarComponentAttributes:
            return [NSString stringWithFormat:@"statusbar.%@", [self.statusBarComponentAttributes.uniqueIdentifier  stringByReplacingOccurrencesOfString:@"-" withString:@"_"]];
        case ITMRPCRegistrationRequest_RoleSpecificAttributes_OneOfCase_ContextMenuAttributes:
            return [NSString stringWithFormat:@"contextMenu.%@", [self.contextMenuAttributes.uniqueIdentifier  stringByReplacingOccurrencesOfString:@"-" withString:@"_"]];
    }
}

- (NSString *)it_stringRepresentation {
    NSArray<NSString *> *argNames = [self.argumentsArray mapWithBlock:^id(ITMRPCRegistrationRequest_RPCArgumentSignature *anObject) {
        return anObject.name;
    }];
    NSString *namespace = self.it_namespace;
    return iTermFunctionSignatureFromNamespaceAndNameAndArguments(namespace, self.name, argNames);
}

- (NSString *)it_fullyQualifiedName {
    NSString *namespace = self.it_namespace;
    if (!namespace) {
        return self.name;
    }
    return [NSString stringWithFormat:@"%@.%@", namespace, self.name];
}

- (NSSet<NSString *> *)it_allArgumentNames {
    return [NSSet setWithArray:[self.argumentsArray mapWithBlock:^id(ITMRPCRegistrationRequest_RPCArgumentSignature *anObject) {
        return anObject.name;
    }]];
}

- (NSSet<NSString *> *)it_argumentsWithDefaultValues {
    return [NSSet setWithArray:[self.defaultsArray mapWithBlock:^id(ITMRPCRegistrationRequest_RPCArgument *anObject) {
        return anObject.name;
    }]];
}

- (NSSet<NSString *> *)it_requiredArguments {
    NSMutableSet *result = [[self it_allArgumentNames] mutableCopy];
    [result minusSet:[self it_argumentsWithDefaultValues]];
    return result;
}

- (BOOL)it_satisfiesExplicitParameters:(NSDictionary<NSString *, id> *)explicitParameters
                                 scope:(iTermVariableScope *)scope
                        fullParameters:(out NSDictionary<NSString *, id> **)fullParameters {
    NSSet<NSString *> *providedArguments = [NSSet setWithArray:explicitParameters.allKeys];
    NSSet<NSString *> *requiredArguments = [self it_requiredArguments];
    if (![requiredArguments isSubsetOfSet:providedArguments]) {
        DLog(@"Does not contain all required arguments. require=%@ have=%@", requiredArguments, providedArguments);
        return NO;
    }

    // Make sure all the arguments with defaults can be satisfied by the scope.
    NSMutableDictionary<NSString *, id> *params = [explicitParameters mutableCopy];
    for (ITMRPCRegistrationRequest_RPCArgument *defaultArgument in self.defaultsArray) {
        NSString *name = defaultArgument.name;
        NSString *path = defaultArgument.path;
        DLog(@"Try default argument %@=%@", name, path);
        BOOL isOptional = NO;
        if ([path hasSuffix:@"?"]) {
            DLog(@"is optional");
            isOptional = YES;
            path = [path substringToIndex:path.length - 1];
        }
        if (params[name]) {
            DLog(@"don't care, there was an explicit value provided");
            // An explicit value was provided, which overrides the default.
            continue;
        }
        id value = [scope valueForVariableName:path];
        DLog(@"value=%@", value);
        if (value) {
            DLog(@"accept value");
            params[name] = value;
            continue;
        }
        if (!isOptional) {
            DLog(@"Fail - missing non-optional value for %@", name);
            return NO;
        }
        DLog(@"accept nil value");
        params[name] = [NSNull null];
    }
    DLog(@"Success. Set fullParameters to %@", params);
    *fullParameters = params;
    return YES;
}

@end

@interface ITMServerOriginatedRPC(Extensions)
- (NSString *)it_stringRepresentationWithNamespace:(NSString *)namespace;
@end

@implementation ITMServerOriginatedRPC(Extensions)

- (NSString *)it_stringRepresentationWithNamespace:(NSString *)namespace {
    NSArray<NSString *> *argNames = [self.argumentsArray mapWithBlock:^id(ITMServerOriginatedRPC_RPCArgument *anObject) {
        return anObject.name;
    }];
    return iTermFunctionSignatureFromNamespaceAndNameAndArguments(namespace, self.name, argNames);
}

@end

@implementation iTermAllObjectsSubscription
@end

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
    _associatedObjectKey = iTermMalloc(1);
    [owner it_setAssociatedObject:self forKey:_associatedObjectKey];
    _failure = [failure copy];
}

@end

@implementation iTermAPIHelper {
    iTermAPIServer *_apiServer;
    BOOL _layoutChanged;

    // Saves the last one to avoid sending changed notifications when nothing changed.
    ITMBroadcastDomainsChangedNotification *_lastBroadcastChangeNotification;

    // When adding a new dictionary of subscriptions update -removeAllSubscriptionsForConnectionKey: and -stop.
    NSMutableDictionary<id, ITMNotificationRequest *> *_newSessionSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_terminateSessionSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_layoutChangeSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_focusChangeSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_broadcastDomainChangeSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_profileChangeSubscriptions;
    NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *_appVariableSubscriptions;
    NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *_tabVariableSubscriptions;
    NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *_windowVariableSubscriptions;
    NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *_sessionVariableSubscriptions;

    NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *_allSessionVariableSubscriptions; // Will have one entry per session
    NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *_allWindowVariableSubscriptions; // Will have one entry per window
    // signature -> ( connection, request )
    NSMutableDictionary<NSString *, iTermTuple<id, ITMNotificationRequest *> *> *_internalServerOriginatedRPCSubscriptions;
    NSMutableArray<iTermAllObjectsSubscription *> *_allSessionsSubscriptions;  // Has one entry per "all" subscription for sessions
    NSMutableArray<iTermAllObjectsSubscription *> *_allWindowsSubscriptions;  // Has one entry per "all" subscription for windows
    NSMutableDictionary<NSString *, iTermServerOriginatedRPCCompletionBlock> *_serverOriginatedRPCCompletionBlocks;
    // connectionKey -> RPC ID (RPC ID is key in _serverOriginatedRPCCompletionBlocks)
    // WARNING: These can exist after the block has been removed from
    // _serverOriginatedRPCCompletionBlocks if it times out.
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *_outstandingRPCs;
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

+ (instancetype)sharedInstanceIfEnabled {
    if (![NSApp isRunningUnitTests] && ![iTermPreferences boolForKey:kPreferenceKeyEnableAPIServer]) {
        return nil;
    }
    return [self sharedInstance];
}

+ (NSString *)noauthPath {
    return [[[NSFileManager defaultManager] applicationSupportDirectory] stringByAppendingPathComponent:@"disable-automation-auth"];
}

+ (NSString *)noauthMagic {
    return [NSString stringWithFormat:@"%@ %@",
            [[[self noauthPath] dataUsingEncoding:NSUTF8StringEncoding] it_hexEncoded],
            iTermAPIHelperDisableApplescriptAuthMagic];
}

+ (BOOL)requireApplescriptAuth {
    const BOOL result = [self internalRequireApplescriptAuth];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        iTermAPIHelperLastApplescriptAuthRequiredSetting = result;
    });
    const BOOL changed = (result != iTermAPIHelperLastApplescriptAuthRequiredSetting);
    iTermAPIHelperLastApplescriptAuthRequiredSetting = result;
    if (changed) {
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermAPIHelperDidDetectChangeOfPythonAuthMethodNotification object:nil];
    }
    return result;
}

+ (iTermNoAuthStatus)noAuthStatus:(out NSString **)contentsPtr {
    NSError *error = nil;
    NSDictionary<NSFileAttributeKey, id> *attributes =
        [[NSFileManager defaultManager] attributesOfItemAtPath:[self noauthPath]
                                                         error:&error];
    if (!attributes || error) {
        return iTermNoAuthStatusNone;
    }
    if ([attributes[NSFileOwnerAccountID] integerValue] != 0) {
        return iTermNoAuthStatusNone;
    }
    NSString *actualContents = [NSString stringWithContentsOfFile:[self noauthPath] encoding:NSUTF8StringEncoding error:nil];
    if (contentsPtr) {
        *contentsPtr = actualContents;
    }
    const BOOL contentsCorrect = [[self noauthMagic] isEqualToString:actualContents];
    if (contentsCorrect) {
        return iTermNoAuthStatusValid;
    }
    return iTermNoAuthStatusCorrupt;
}

+ (BOOL)internalRequireApplescriptAuth {
    NSString *actualContents = nil;
    switch ([self noAuthStatus:&actualContents]) {
        case iTermNoAuthStatusNone:
            return YES;
        case iTermNoAuthStatusValid:
            return NO;
        case iTermNoAuthStatusCorrupt:
            break;
    }
    static NSString *valueForLastWarning = nil;
    if (valueForLastWarning && [valueForLastWarning isEqualToString:actualContents]) {
        return YES;
    }
    valueForLastWarning = actualContents;

    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:@"The location of your Application Support directory appears to have moved or its contents have changed unexpectedly. As a precaution, the authentication mechanism for Python API scripts for iTerm2 has been reverted to always require Automation permission."
                               actions:@[ @"OK", @"Reveal Preference" ]
                             accessory:nil
                            identifier:@"NoSyncAppSupportMoved"
                           silenceable:kiTermWarningTypePermanentlySilenceable
                               heading:@"Python API Permissions Reset"
                                window:nil];
    if (selection == kiTermWarningSelection1) {
        [[PreferencePanel sharedInstance] openToPreferenceWithKey:kPreferenceKeyAPIAuthentication];
    }

    return YES;
}

+ (BOOL)createNoAuthFile:(NSWindow *)window {
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:@"Do you want to allow all apps running on this machine to use the Python API?\n\nThis will disable the check for Automation permission. If you agree, you’ll be prompted for administrator access to make the change."
                               actions:@[ @"OK", @"Cancel", @"More Info" ]
                             accessory:nil
                            identifier:@"NoSyncRequireApplescriptAuth"
                           silenceable:kiTermWarningTypePersistent
                               heading:@"Disable per-app authentication?"
                                window:window];
    switch (selection) {
        case kiTermWarningSelection0:
            return [self reallyCreateNoAuthFile:window];
        case kiTermWarningSelection1:
            return NO;
        case kiTermWarningSelection2:
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://iterm2.com/python-api-auth.html"]];
            return NO;
        default:
            assert(NO);
    }
    return NO;
}

// Returns YES on success.
+ (BOOL)removeNoAuthFile:(NSWindow *)window {
    NSError *error;
    NSString *path = [self noauthPath];
    const BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
    if (ok) {
        return YES;
    }

    [self setEnabled:NO];
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"Failed to remove the file “%@”: %@\n\nPlease remove this file manually to require Automation permission for the Python API.\n\nThe Python API has been disabled for your security.", path, error.localizedDescription]
                               actions:@[ @"OK", @"Reveal In Finder" ]
                             accessory:nil
                            identifier:@"NoSyncFailedToRemoveNoAuth"
                           silenceable:kiTermWarningTypePersistent
                               heading:@"Error changing API permissions setting"
                                window:window];
    switch (selection) {
        case kiTermWarningSelection0:
            break;
        case kiTermWarningSelection1:
            [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:path] ]];
            break;
        default:
            assert(NO);
    }
    return NO;
}

 + (void)setRequireApplescriptAuth:(BOOL)requireApplescriptAuth
                            window:(NSWindow *)window {
    if (requireApplescriptAuth == [self requireApplescriptAuth]) {
        return;
    }
    if (requireApplescriptAuth) {
        if (![self removeNoAuthFile:window]) {
            return;
        }
    } else {
        if (![self createNoAuthFile:window]) {
            return;
        }
    }
     iTermAPIHelperLastApplescriptAuthRequiredSetting = requireApplescriptAuth;
     // Verify that it changed and issue a warning if not.
     [self requireApplescriptAuth];
}

+ (BOOL)reallyCreateNoAuthFile:(NSWindow *)window {
    // Write to a temp file and then move it. If the destination is a link then it's not safe
    // to write to it.
    NSString *path = [self noauthPath];
    path = [path stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    path = [path stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\\\\\""];
    NSString *sourceCode = [NSString stringWithFormat:@"do shell script \"umask 077; TF=$(mktemp); printf '%%s' '%@' > \\\"$TF\\\" && chmod a+r \\\"$TF\\\" && mv \\\"$TF\\\" \\\"%@\\\" || rm -f \\\"$TF\\\"\" with prompt \"iTerm2 needs to modify a secure setting.\" with administrator privileges",
                            [self noauthMagic],
                            path];
    NSAppleScript *script = [[NSAppleScript alloc] initWithSource:sourceCode];
    NSDictionary<NSString *, id> *dict = nil;
    [script executeAndReturnError:&dict];
    if (!dict) {
        return YES;
    }
    [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"The setting could not be changed: %@", dict[NSAppleScriptErrorBriefMessage]]
                               actions:@[ @"OK" ]
                             accessory:nil
                            identifier:@"NoSyncFailedToCreateNoAuth"
                           silenceable:kiTermWarningTypePersistent
                               heading:@"Failed to make change"
                                window:window];
    return NO;
}

+ (void)reportFunctionCallError:(NSError *)error forInvocation:(NSString *)invocation origin:(NSString *)origin window:(NSWindow *)window {
    NSString *message = [NSString stringWithFormat:@"Error running “%@”:\n%@",
                         invocation, error.localizedDescription];
    NSString *traceback = error.localizedFailureReason;
    NSArray *actions = @[ @"OK" ];
    if (traceback) {
        actions = [actions arrayByAddingObject:@"Reveal in Script Console"];
    }
    NSString *connectionKey = error.userInfo[iTermAPIHelperFunctionCallErrorUserInfoKeyConnection];
    iTermScriptHistoryEntry *entry = [[iTermScriptHistory sharedInstance] entryWithIdentifier:connectionKey];
    [entry addOutput:[NSString stringWithFormat:@"An error occurred while running the function invocation “%@”:\n%@\n\nTraceback:\n%@",
                      invocation,
                      error.localizedDescription,
                      traceback]
          completion:^{}];
    iTermWarningSelection selection = [iTermWarning showWarningWithTitle:message
                                                                 actions:actions
                                                               accessory:nil
                                                              identifier:@"NoSyncFunctionCallError"
                                                             silenceable:kiTermWarningTypeTemporarilySilenceable
                                                                 heading:[NSString stringWithFormat:@"%@ Function Call Failed", origin]
                                                                  window:window];
    if (selection == kiTermWarningSelection1) {
        [[iTermScriptConsole sharedInstance] revealTailOfHistoryEntry:entry];
    }
}

- (NSDictionary<NSString *, iTermTuple<id, ITMNotificationRequest *> *> *)serverOriginatedRPCSubscriptions {
    return _internalServerOriginatedRPCSubscriptions;
}

- (void)setServerOriginatedRPCSubscriptionWithSignature:(NSString *)signatureString
                                          connectionKey:(NSString *)connectionKey
                                                request:(ITMNotificationRequest *)request {
    _internalServerOriginatedRPCSubscriptions[signatureString] = [iTermTuple tupleWithObject:connectionKey
                                                                                   andObject:request];
}

- (void)removeServerOriginatedRPCSubscriptionWithSignature:(NSString *)signatureString {
    [_internalServerOriginatedRPCSubscriptions removeObjectForKey:signatureString];
}

- (NSInteger)removeServerOriginatedRPCSubscriptionsPasstingTest:(BOOL (^)(NSString *signature,
                                                                          iTermTuple<id, ITMNotificationRequest *> *tuple))block {
    return [_internalServerOriginatedRPCSubscriptions removeObjectsPassingTest:block];
}

+ (NSDictionary<NSString *, NSArray<NSString *> *> *)registeredFunctionSignatureDictionary {
    return [sAPIHelperInstance registeredFunctionSignatureDictionary] ?: @{};
}

+ (NSArray<iTermSessionTitleProvider *> *)sessionTitleFunctions {
    return [sAPIHelperInstance sessionTitleFunctions] ?: @[];
}

+ (NSArray<ITMRPCRegistrationRequest *> *)statusBarComponentProviderRegistrationRequests {
    return [sAPIHelperInstance statusBarComponentProviderRegistrationRequests] ?: @[];
}

+ (NSArray<ITMRPCRegistrationRequest *> *)contextMenuProviderRegistrationRequests {
    return [sAPIHelperInstance contextMenuProviderRegistrationRequests] ?: @[];
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
    if (showing) {
        // This can happen because the call to -runModal below starts a runloop and a delayed perform can then call this.
        DLog(@"Reentrancy detected\n%@", [NSThread callStackSymbols]);
        return NO;
    }
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

        _serverOriginatedRPCCompletionBlocks = [NSMutableDictionary dictionary];
        _outstandingRPCs = [NSMutableDictionary dictionary];
        _allSessionsSubscriptions = [NSMutableArray array];
        _allWindowsSubscriptions = [NSMutableArray array];

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

        // Begin layoutChanged:
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
                                                 selector:@selector(layoutChanged:)
                                                     name:iTermSessionBuriedStateChangeTabNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(layoutChanged:)
                                                     name:iTermWindowDidCloseNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(layoutChanged:)
                                                     name:iTermTabDidCloseNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(layoutChanged:)
                                                     name:iTermSessionWillTerminateNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(layoutChanged:)
                                                     name:iTermDidCreateTerminalWindowNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(layoutChanged:)
                                                     name:NSWindowDidEndLiveResizeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(layoutChanged:)
                                                     name:@"iTermWindowDidResize"
                                                   object:nil];
        // End layoutChanged:

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didCreateTerminalWindow:)
                                                     name:iTermDidCreateTerminalWindowNotification
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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(broadcastDomainsDidChange:)
                                                     name:iTermBroadcastDomainsDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(profileDidChange:)
                                                     name:kReloadAddressBookNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(sessionDidResize:)
                                                     name:PTYSessionDidResizeNotification
                                                   object:nil];
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
    [_newSessionSubscriptions removeAllObjects];
    [_terminateSessionSubscriptions removeAllObjects];
    [_layoutChangeSubscriptions removeAllObjects];
    [_focusChangeSubscriptions removeAllObjects];
    [_broadcastDomainChangeSubscriptions removeAllObjects];
    [_profileChangeSubscriptions removeAllObjects];
    [_appVariableSubscriptions removeAllObjects];
    [_tabVariableSubscriptions removeAllObjects];
    [_windowVariableSubscriptions removeAllObjects];
    [_sessionVariableSubscriptions removeAllObjects];

    [_allSessionVariableSubscriptions removeAllObjects];
    [_allWindowVariableSubscriptions removeAllObjects];

    [_internalServerOriginatedRPCSubscriptions removeAllObjects];

    [_allSessionsSubscriptions removeAllObjects];
    [_allWindowsSubscriptions removeAllObjects];

    [_serverOriginatedRPCCompletionBlocks removeAllObjects];
    [_outstandingRPCs removeAllObjects];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermAPIHelperDidStopNotification object:nil];
}

- (void)postAPINotification:(ITMNotification *)notification toConnectionKey:(NSString *)connectionKey {
    [_apiServer postAPINotification:notification toConnectionKey:connectionKey];
}

- (void)didCreateTerminalWindow:(NSNotification *)notification {
    PseudoTerminal *term = notification.object;
    for (iTermAllObjectsSubscription *sub in _allWindowsSubscriptions) {
        if (sub.request.notificationType == ITMNotificationType_NotifyOnVariableChange) {
            [self monitorVariableChangesForConnectionKey:sub.connectionKey
                                              identifier:term.subscribableIdentifier
                                                 request:sub.request
                                                   scope:term.scope
                                    mutableVariablesDict:_allWindowVariableSubscriptions];
            continue;
        }
        [term handleAPINotificationRequest:sub.request
                             connectionKey:sub.connectionKey];
    }
}

- (void)sessionCreated:(NSNotification *)notification {
    PTYSession *session = notification.object;
    for (iTermAllObjectsSubscription *sub in _allSessionsSubscriptions) {
        if (sub.request.notificationType == ITMNotificationType_NotifyOnVariableChange) {
            [self monitorVariableChangesForConnectionKey:sub.connectionKey
                                              identifier:session.guid
                                                 request:sub.request
                                                   scope:session.variablesScope
                                    mutableVariablesDict:_allSessionVariableSubscriptions];
             continue;
        }
        [session handleAPINotificationRequest:sub.request
                                connectionKey:sub.connectionKey];
    }
    [_newSessionSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        ITMNotification *notification = [[ITMNotification alloc] init];
        notification.newSessionNotification = [[ITMNewSessionNotification alloc] init];
        notification.newSessionNotification.sessionId = session.guid;
        [self postAPINotification:notification toConnectionKey:key];
    }];
}

- (void)sessionDidTerminate:(NSNotification *)notification {
    PTYSession *session = notification.object;
    [_terminateSessionSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        ITMNotification *notification = [[ITMNotification alloc] init];
        notification.terminateSessionNotification = [[ITMTerminateSessionNotification alloc] init];
        notification.terminateSessionNotification.sessionId = session.guid;
        [self postAPINotification:notification toConnectionKey:key];
    }];
}

- (void)sessionDidResize:(NSNotification *)notification {
    PTYSession *session = notification.object;
    DLog(@"%@", session);
    if (![session isKindOfClass:[PTYSession class]]) {
        DLog(@"Not a session");
        return;
    }
    NSWindow *window = session.delegate.realParentWindow.window;
    if (!window) {
        DLog(@"No window");
        return;
    }
    if (window.inLiveResize) {
        DLog(@"In live resize");
        return;
    }
    if (session.delegate.sessionBelongsToTabWhoseSplitsAreBeingDragged) {
        DLog(@"Splits being dragged");
        return;
    }
    DLog(@"Calling layoutChanged:");
    [self layoutChanged:nil];
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
        [self postAPINotification:notification toConnectionKey:key];
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

- (void)broadcastDomainsDidChange:(NSNotification *)notification {
    [self handleBroadcastChange];
}

- (void)profileDidChange:(NSNotification *)notification {
    NSArray<BookmarkJournalEntry *> *entries = notification.userInfo[@"array"];
    NSSet<NSString *> *guids = [NSSet setWithArray:[entries mapWithBlock:^id(BookmarkJournalEntry *entry) {
        return entry.guid;
    }]];
    for (NSString *guid in guids) {
        [_profileChangeSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull request, BOOL * _Nonnull stop) {
            ITMNotification *notification = [[ITMNotification alloc] init];
            notification.profileChangedNotification = [[ITMProfileChangedNotification alloc] init];
            notification.profileChangedNotification.guid = guid;
            [self postAPINotification:notification toConnectionKey:key];
        }];
    }
}

- (void)handleFocusChange:(ITMFocusChangedNotification *)notif {
    void (^handle)(void) = ^{
        [self->_focusChangeSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
            ITMNotification *notification = [[ITMNotification alloc] init];
            notification.focusChangedNotification = notif;
            [self postAPINotification:notification toConnectionKey:key];
        }];
    };
    if (_layoutChanged) {
        // Let the layout change go through first so the app state can be up-to-date when processing
        // the focus change notification.
        dispatch_async(dispatch_get_main_queue(), handle);
    } else {
        handle();
    }
}

- (void)handleBroadcastChange {
    ITMBroadcastDomainsChangedNotification *broadcastSubNotification = [[ITMBroadcastDomainsChangedNotification alloc] init];
    [self enumerateBroadcastDomains:^(NSArray<PTYSession *> *sessions) {
        ITMBroadcastDomain *domain = [[ITMBroadcastDomain alloc] init];
        for (PTYSession *session in sessions) {
            [domain.sessionIdsArray addObject:session.guid];
        }
        [broadcastSubNotification.broadcastDomainsArray addObject:domain];
    }];
    ITMNotification *notification = [[ITMNotification alloc] init];
    notification.broadcastDomainsChanged = broadcastSubNotification;
    if ([NSObject object:broadcastSubNotification isEqualToObject:_lastBroadcastChangeNotification]) {
        return;
    }
    _lastBroadcastChangeNotification = broadcastSubNotification;
    [_broadcastDomainChangeSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        [self postAPINotification:notification toConnectionKey:key];
    }];
}

- (NSString *)connectionKeyForRPCWithSignature:(NSString *)signature {
    return self.serverOriginatedRPCSubscriptions[signature].firstObject;
}

- (NSString *)connectionKeyForRPCWithName:(NSString *)name
                       explicitParameters:(NSDictionary<NSString *, id> *)explicitParameters
                                    scope:(iTermVariableScope *)scope
                           fullParameters:(out NSDictionary<NSString *, id> **)fullParameters {
    DLog(@"Looking for connection key for rpc. name=%@ params=%@", name, explicitParameters);
    if ([name hasPrefix:@"iterm2."]) {
        DLog(@"Private namespace - reject");
        *fullParameters = explicitParameters;
        return nil;
    }
    DLog(@"All RPC subscriptions:\n%@", self.serverOriginatedRPCSubscriptions);
    for (NSString *signature in self.serverOriginatedRPCSubscriptions) {
        DLog(@"Consider %@", signature);
        iTermTuple<id, ITMNotificationRequest *> *tuple = self.serverOriginatedRPCSubscriptions[signature];
        ITMNotificationRequest *request = tuple.secondObject;
        if (![request.rpcRegistrationRequest.it_fullyQualifiedName isEqualToString:name]) {
            DLog(@"%@ does not match %@, reject", request.rpcRegistrationRequest.it_fullyQualifiedName, name);
            continue;
        }
        if ([request.rpcRegistrationRequest it_satisfiesExplicitParameters:explicitParameters
                                                                     scope:scope
                                                            fullParameters:fullParameters]) {
            DLog(@"Accept it");
            return tuple.firstObject;
        }
        DLog(@"Does not satisfy explicit parameters, reject");
    }
    *fullParameters = explicitParameters;
    return nil;
}

- (void)splitFullyQualifiedRPCName:(NSString *)fqName
                         namespace:(out NSString **)namespacePtr
                      relativeName:(out NSString **)relativeNamePtr {
    iTermFunctionCallSplitFullyQualifiedName(fqName, namespacePtr, relativeNamePtr);
}

- (ITMServerOriginatedRPC *)serverOriginatedRPCWithName:(NSString *)fullyQualifiedName
                                              arguments:(NSDictionary *)arguments
                                                  error:(out NSError **)error {

    ITMServerOriginatedRPC *rpc = [[ITMServerOriginatedRPC alloc] init];
    NSString *namespace;
    NSString *relativeName;
    [self splitFullyQualifiedRPCName:fullyQualifiedName namespace:&namespace relativeName:&relativeName];

    rpc.name = relativeName;
    for (NSString *argumentName in [arguments.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        id argumentValue = arguments[argumentName];
        NSString *jsonValue;
        if ([NSNull castFrom:argumentValue]) {
            jsonValue = nil;
        } else {
            jsonValue = [NSJSONSerialization it_jsonStringForObject:argumentValue];
            if (!jsonValue) {
                NSString *reason = [NSString stringWithFormat:@"Could not JSON encode value “%@”", arguments[argumentName]];
                NSString *signature = iTermFunctionSignatureFromNamespaceAndNameAndArguments(namespace,
                                                                                             relativeName,
                                                                                             arguments.allKeys);
                NSString *connectionKey = [self connectionKeyForRPCWithSignature:signature];
                NSDictionary *userinfo = @{ NSLocalizedDescriptionKey: reason };
                if (connectionKey) {
                    userinfo =
                        [userinfo dictionaryBySettingObject:connectionKey
                                                     forKey:iTermAPIHelperFunctionCallErrorUserInfoKeyConnection];
                }
                if (error) {
                    *error = [NSError errorWithDomain:iTermAPIHelperErrorDomain
                                                 code:iTermAPIHelperErrorCodeInvalidJSON
                                             userInfo:userinfo];
                }

                return nil;
            }
        }
        ITMServerOriginatedRPC_RPCArgument *argument = [[ITMServerOriginatedRPC_RPCArgument alloc] init];
        argument.name = argumentName;
        if (jsonValue) {
            argument.jsonValue = jsonValue;
        }

        [rpc.argumentsArray addObject:argument];
    }
    return rpc;
}

// Build a proto buffer and dispatch it.
- (void)dispatchRPCWithName:(NSString *)fullyQualifiedName
                  arguments:(NSDictionary *)arguments
                 completion:(iTermServerOriginatedRPCCompletionBlock)completion {
    NSError *error = nil;
    ITMServerOriginatedRPC *rpc = [self serverOriginatedRPCWithName:fullyQualifiedName arguments:arguments error:&error];
    if (error) {
        completion(nil, error);
    }
    NSString *namespace;
    NSString *relativeName;
    [self splitFullyQualifiedRPCName:fullyQualifiedName namespace:&namespace relativeName:&relativeName];
    [self dispatchServerOriginatedRPC:rpc namespace:namespace completion:completion];
}

- (NSString *)fullyQualifiedNameFromRelativeName:(NSString *)relativeName
                                       namespace:(NSString *)namespace {
    if (!namespace) {
        return relativeName;
    }
    return [NSString stringWithFormat:@"%@.%@", namespace, relativeName];
}

- (NSString *)signatureOfAnyRegisteredFunctionWithName:(NSString *)name
                                             namespace:(NSString *)namespace {
    NSString *fqName = [self fullyQualifiedNameFromRelativeName:name namespace:namespace];
    for (NSString *key in self.serverOriginatedRPCSubscriptions) {
        iTermTuple<id, ITMNotificationRequest *> *sub = self.serverOriginatedRPCSubscriptions[key];
        ITMNotificationRequest *request = sub.secondObject;
        if ([request.rpcRegistrationRequest.it_fullyQualifiedName isEqual:fqName]) {
            return request.rpcRegistrationRequest.it_stringRepresentation;
        }
    }
    return [iTermBuiltInFunctions.sharedInstance signatureOfAnyRegisteredFunctionWithName:fqName];
}

// Dispatches a well-formed proto buffer or gives an error if not connected.
- (void)dispatchServerOriginatedRPC:(ITMServerOriginatedRPC *)rpc
                          namespace:(NSString *)namespace
                         completion:(iTermServerOriginatedRPCCompletionBlock)completion {
    NSString *signature = [rpc it_stringRepresentationWithNamespace:namespace];
    iTermTuple<id, ITMNotificationRequest *> *sub = self.serverOriginatedRPCSubscriptions[signature];

    id connectionKey = sub.firstObject;
    if (!connectionKey) {
        NSString *reason = [NSString stringWithFormat:@"No function registered for invocation “%@”. Ensure the script is running and the function name and argument names are correct.", signature];
        NSString *bestMatch = [self signatureOfAnyRegisteredFunctionWithName:rpc.name
                                                                   namespace:namespace];
        if (bestMatch) {
            reason = [reason stringByAppendingFormat:@" There is a similarly named function available with a different signature: %@", bestMatch];
        }
        completion(nil, [self rpcDispatchError:reason detail:nil unregistered:YES connectionKey:nil]);
        return;
    }

    ITMNotificationRequest *notificationRequest = sub.secondObject;
    [self dispatchRPC:rpc toHandler:notificationRequest connectionKey:connectionKey completion:completion];
}

// Constructs an error with an optional traceback in `detail`.
- (NSError *)rpcDispatchError:(NSString *)reason
                       detail:(NSString *)detail
                 unregistered:(BOOL)unregistered
                connectionKey:(NSString *)connectionKey {
    if (reason == nil) {
        reason = @"Unknown reason";
    }
    NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: reason };
    if (detail) {
        userInfo = [userInfo dictionaryBySettingObject:detail forKey:NSLocalizedFailureReasonErrorKey];
    }
    if (connectionKey) {
        userInfo = [userInfo dictionaryBySettingObject:connectionKey
                                                forKey:iTermAPIHelperFunctionCallErrorUserInfoKeyConnection];
    }
    return [NSError errorWithDomain:iTermAPIHelperErrorDomain
                               code:unregistered ? iTermAPIHelperErrorCodeUnregisteredFunction : iTermAPIHelperErrorCodeFunctionCallFailed
                           userInfo:userInfo];
}

// Dispatches an RPC, assuming connected. Registers a timeout.
- (void)dispatchRPC:(ITMServerOriginatedRPC *)rpc
          toHandler:(ITMNotificationRequest * _Nonnull)handler
      connectionKey:(NSString *)connectionKey
         completion:(iTermServerOriginatedRPCCompletionBlock)completion {
    ITMNotification *notification = [[ITMNotification alloc] init];
    notification.serverOriginatedRpcNotification.requestId = [self nextServerOriginatedRPCRequestIDWithCompletion:completion];
    NSMutableSet *outstanding = _outstandingRPCs[connectionKey];
    if (!outstanding) {
        outstanding = [NSMutableSet set];
        _outstandingRPCs[connectionKey] = outstanding;
    }
    [outstanding addObject:notification.serverOriginatedRpcNotification.requestId];
    notification.serverOriginatedRpcNotification.rpc = rpc;
    [self postAPINotification:notification toConnectionKey:connectionKey];

    __weak __typeof(self) weakSelf = self;
    const NSTimeInterval timeoutSeconds = handler.rpcRegistrationRequest.hasTimeout ? handler.rpcRegistrationRequest.timeout : 5;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeoutSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf checkForRPCTimeout:notification.serverOriginatedRpcNotification.requestId
                       connectionKey:connectionKey];
    });
}

// Calls the completion block if RPC timed out.
- (void)checkForRPCTimeout:(NSString *)requestID
             connectionKey:(NSString *)connectionKey {
    iTermServerOriginatedRPCCompletionBlock completion = _serverOriginatedRPCCompletionBlocks[requestID];
    if (!completion) {
        return;
    }

    [_serverOriginatedRPCCompletionBlocks removeObjectForKey:requestID];
    completion(nil, [self rpcDispatchError:@"Timeout"
                                    detail:nil
                              unregistered:NO
                             connectionKey:connectionKey]);
}

- (NSString *)nextServerOriginatedRPCRequestIDWithCompletion:(iTermServerOriginatedRPCCompletionBlock)completion {
    static NSInteger nextID;
    NSString *requestID = [NSString stringWithFormat:@"rpc-%@", @(nextID)];
    nextID++;
    if (completion) {
        _serverOriginatedRPCCompletionBlocks[requestID] = [completion copy];
    }
    return requestID;
}

- (NSDictionary<NSString *, NSArray<NSString *> *> *)registeredFunctionSignatureDictionary {
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *result = [NSMutableDictionary dictionary];
    for (NSString *stringSignature in self.serverOriginatedRPCSubscriptions.allKeys) {
        ITMNotificationRequest *req = self.serverOriginatedRPCSubscriptions[stringSignature].secondObject;
        if (!req) {
            continue;
        }
        ITMRPCRegistrationRequest *sig = req.rpcRegistrationRequest;
        NSString *functionName = [sig it_fullyQualifiedName];
        NSArray<NSString *> *args = [sig.argumentsArray mapWithBlock:^id(ITMRPCRegistrationRequest_RPCArgumentSignature *anObject) {
            return anObject.name;
        }];
        result[functionName] = args;
    }
    return result;
}

+ (NSString *)invocationWithFullyQualifiedName:(NSString *)fullyQualifiedName
                                      defaults:(NSArray<ITMRPCRegistrationRequest_RPCArgument*> *)defaultsArray {
    NSArray<ITMRPCRegistrationRequest_RPCArgument*> *sortedDefaults =
        [defaultsArray sortedArrayUsingComparator:^NSComparisonResult(ITMRPCRegistrationRequest_RPCArgument * _Nonnull obj1,
                                                                      ITMRPCRegistrationRequest_RPCArgument * _Nonnull obj2) {
            return [obj1.name compare:obj2.name];
        }];
    NSArray<NSString *> *defaults = [sortedDefaults mapWithBlock:^id(ITMRPCRegistrationRequest_RPCArgument *def) {
        return [NSString stringWithFormat:@"%@:%@", def.name, def.path];
    }];
    defaults = [defaults sortedArrayUsingSelector:@selector(compare:)];
    return [NSString stringWithFormat:@"%@(%@)", fullyQualifiedName, [defaults componentsJoinedByString:@","]];
}

+ (NSString *)userDefaultsKeyForNameOfScriptVendingStatusBarComponentWithID:(NSString *)uniqueID {
    return [NSString stringWithFormat:@"NoSyncScriptNameForStatusBarComponent_%@", uniqueID];
}

+ (NSString *)nameOfScriptVendingStatusBarComponentWithUniqueIdentifier:(NSString *)uniqueID {
    return [[NSUserDefaults standardUserDefaults] objectForKey:[self userDefaultsKeyForNameOfScriptVendingStatusBarComponentWithID:uniqueID]];
}

- (NSArray<iTermSessionTitleProvider *> *)sessionTitleFunctions {
    return [self.serverOriginatedRPCSubscriptions.allKeys mapWithBlock:^id(NSString *signature) {
        ITMNotificationRequest *req = self.serverOriginatedRPCSubscriptions[signature].secondObject;
        if (!req) {
            return nil;
        }
        return [[iTermSessionTitleProvider alloc] initWithNotificationRequest:req];
    }];
}

- (NSArray<ITMRPCRegistrationRequest *> *)statusBarComponentProviderRegistrationRequests {
    return [self.serverOriginatedRPCSubscriptions.allKeys mapWithBlock:^id(NSString *signature) {
        ITMNotificationRequest *req = self.serverOriginatedRPCSubscriptions[signature].secondObject;
        if (!req) {
            return nil;
        }
        if (req.rpcRegistrationRequest.role != ITMRPCRegistrationRequest_Role_StatusBarComponent) {
            return nil;
        }
        return req.rpcRegistrationRequest;
    }];
}

- (NSArray<ITMRPCRegistrationRequest *> *)contextMenuProviderRegistrationRequests {
    return [self.serverOriginatedRPCSubscriptions.allKeys mapWithBlock:^id(NSString *signature) {
        ITMNotificationRequest *req = self.serverOriginatedRPCSubscriptions[signature].secondObject;
        if (!req) {
            return nil;
        }
        if (req.rpcRegistrationRequest.role != ITMRPCRegistrationRequest_Role_ContextMenu) {
            return nil;
        }
        return req.rpcRegistrationRequest;
    }];
}

+ (ITMRPCRegistrationRequest *)registrationRequestForStatusBarComponentWithUniqueIdentifier:(NSString *)uniqueIdentifier {
    return [[[self sharedInstance] statusBarComponentProviderRegistrationRequests] objectPassingTest:^BOOL(ITMRPCRegistrationRequest *request, NSUInteger index, BOOL *stop) {
        return [request.statusBarComponentAttributes.uniqueIdentifier isEqualToString:uniqueIdentifier];
    }];
}

- (BOOL)haveRegisteredFunctionWithName:(NSString *)name
                             namespace:(NSString *)namespace
                             arguments:(NSArray<NSString *> *)arguments {
    NSString *stringSignature = iTermFunctionSignatureFromNamespaceAndNameAndArguments(namespace, name, arguments);
    return [self haveRegisteredFunctionWithSignature:stringSignature];
}

- (BOOL)haveRegisteredFunctionWithSignature:(NSString *)stringSignature {
    return self.serverOriginatedRPCSubscriptions[stringSignature].secondObject != nil;
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

- (void)logToConnectionHostingFunctionWithSignature:(NSString *)signatureString
                                             format:(NSString *)format, ... {
    va_list arguments;
    va_start(arguments, format);
    NSString *string = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    NSString *connectionKey = [self.serverOriginatedRPCSubscriptions[signatureString] firstObject];
    [self logToConnectionWithKey:connectionKey string:string];
}

- (void)logToConnectionHostingFunctionWithSignature:(NSString *)signatureString
                                             string:(NSString *)string {
    NSString *connectionKey = [self.serverOriginatedRPCSubscriptions[signatureString] firstObject];
    [self logToConnectionWithKey:connectionKey string:string];
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

    [entry addOutput:@"❗️ " completion:^{}];
    [entry addOutput:string completion:^{}];
    [entry addOutput:@"\n" completion:^{}];
    XLog(@"%@", string);
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

- (BOOL)apiServerAuthorizeProcesses:(NSArray<NSNumber *> *)pids
                      preauthorized:(BOOL)preauthorized
                      disableAuthUI:(BOOL)disableAuthUI
                       advisoryName:(NSString *)advisoryName
                             reason:(out NSString *__autoreleasing *)reason
                        displayName:(out NSString *__autoreleasing *)displayName {
    *displayName = advisoryName ? [@"≈" stringByAppendingString:advisoryName] : @"Unknown";

    if (preauthorized) {
        *reason = @"Script launched by user action";
        return YES;
    }
    if (![iTermAPIHelper requireApplescriptAuth]) {
        *reason = @"All apps are allowed to use the API, per “Prefs > General > Magic > Allow all apps to connect”.";
        return YES;
    }
    if (disableAuthUI) {
        *reason = @"UI authorization disabled and no valid cookie was presented.";
        return NO;
    }

    NSString *message =
        @"Another process is trying to use the iTerm2 API. The API allows a script to control iTerm2 and view and modify its contents. Allow the connection?";

    if ([iTermAdvancedSettingsModel setCookie]) {
        message = [NSString stringWithFormat:@"%@\n\nAlthough you have chosen to allow connections automatically, this script has not presented a valid cookie.", message];
    }

    NSArray<NSString *> *actions = @[ @"OK", @"Cancel", @"More Info" ];
    if (![iTermAdvancedSettingsModel setCookie]) {
        actions = [actions arrayByAddingObject:@"Always"];
    }
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:message
                               actions:actions
                             accessory:nil
                            identifier:@"NoSyncAllowPythonAPI"
                           silenceable:kiTermWarningTypePersistent
                               heading:@"Allow Python API Usage?"
                                window:nil];
    switch (selection) {
        case kiTermWarningSelection0:
            *reason = @"Allowed by user";
            return YES;
        case kiTermWarningSelection1:
            *reason = @"Denied by user";
            return NO;
        case kiTermWarningSelection2:
            *reason = @"Denied by user";
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://iterm2.com/python-api-security-model"]];
            return NO;
        case kiTermWarningSelection3:
            if ([iTermWarning showWarningWithTitle:@"New sessions will contain an environment variable that allows scripts to run without confirmation. Are you sure you want to enable this?"
                                           actions:@[ @"OK", @"Cancel" ]
                                         accessory:nil
                                        identifier:@"NoSyncConfirmAlways"
                                       silenceable:kiTermWarningTypePersistent
                                           heading:@"Confirm"
                                            window:nil] == kiTermWarningSelection0) {
                [iTermAdvancedSettingsModel setSetCookie:YES];
                *reason = @"Allowed by user";
                return YES;
            }
            *reason = @"Denied by user";
            return NO;
        default:
            *reason = @"Internal error";
            return NO;
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
        [session handleGetPromptRequest:request completion:handler];
    }
}

- (void)apiServerListPrompts:(ITMListPromptsRequest *)request
                     handler:(void (^)(ITMListPromptsResponse *))handler {
    PTYSession *session = [self sessionForAPIIdentifier:request.session includeBuriedSessions:YES];
    if (!session) {
        ITMListPromptsResponse *response = [[ITMListPromptsResponse alloc] init];
        response.status = ITMListPromptsResponse_Status_SessionNotFound;
        handler(response);
    } else {
        [session handleListPromptsRequest:request completion:handler];
    }
}

- (BOOL)rpcNotificationRequestIsValid:(ITMNotificationRequest *)request
                        connectionKey:(NSString *)connectionKey {
    if (request.argumentsOneOfCase != ITMNotificationRequest_Arguments_OneOfCase_RpcRegistrationRequest) {
        [self logToConnectionWithKey:connectionKey format:@"Expected an RPC registration request, but got:\n%@", request];
        return NO;
    }
    NSError *error = nil;
    if (![request.rpcRegistrationRequest it_rpcRegistrationRequestValidWithError:&error]) {
        [self logToConnectionWithKey:connectionKey format:@"Malformed RPC function signature: %@", error.localizedDescription];

        return NO;
    }

    return YES;
}

- (void)createSubscriptionDictionariesIfNeeded {
    if (!_newSessionSubscriptions) {
        _newSessionSubscriptions = [[NSMutableDictionary alloc] init];
        _terminateSessionSubscriptions = [[NSMutableDictionary alloc] init];
        _layoutChangeSubscriptions = [[NSMutableDictionary alloc] init];
        _focusChangeSubscriptions = [[NSMutableDictionary alloc] init];
        _internalServerOriginatedRPCSubscriptions = [[NSMutableDictionary alloc] init];
        _broadcastDomainChangeSubscriptions = [[NSMutableDictionary alloc] init];
        _appVariableSubscriptions = [[NSMutableDictionary alloc] init];
        _tabVariableSubscriptions = [[NSMutableDictionary alloc] init];
        _windowVariableSubscriptions = [[NSMutableDictionary alloc] init];
        _sessionVariableSubscriptions = [[NSMutableDictionary alloc] init];
        _allSessionVariableSubscriptions = [[NSMutableDictionary alloc] init];
        _allWindowVariableSubscriptions = [[NSMutableDictionary alloc] init];
        _profileChangeSubscriptions = [[NSMutableDictionary alloc] init];
    }
}

- (NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *)subscriptionsForVariableChangeScope:(ITMVariableScope)scope {
    [self createSubscriptionDictionariesIfNeeded];
    switch (scope) {
        case ITMVariableScope_App:
            return _appVariableSubscriptions;
        case ITMVariableScope_Tab:
            return _tabVariableSubscriptions;
        case ITMVariableScope_Window:
            return _windowVariableSubscriptions;
        case ITMVariableScope_Session:
            return _sessionVariableSubscriptions;
    }
    return nil;
}

- (iTermVariableScope *)scopeForCategory:(ITMVariableScope)category identifier:(NSString *)identifier {
    switch (category) {
        case ITMVariableScope_App:
            return [iTermVariableScope globalsScope];
        case ITMVariableScope_Tab:
            return [[self tabWithID:identifier] variablesScope];
        case ITMVariableScope_Window:
            return [[self windowControllerWithID:identifier] scope];
        case ITMVariableScope_Session:
            return [[self sessionForAPIIdentifier:identifier includeBuriedSessions:YES] variablesScope];
    }

    return nil;
}

- (void)monitorVariableChangesForConnectionKey:(NSString *)connectionKey
                                    identifier:(NSString *)identifier
                                       request:(ITMNotificationRequest *)request
                                         scope:(iTermVariableScope *)scope
                          mutableVariablesDict:(NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *)dict {
    NSString *name = request.variableMonitorRequest.name;
    iTermVariableReference *ref = [[iTermVariableReference alloc] initWithPath:name
                                                                        vendor:scope];
    __weak __typeof(ref) weakRef = ref;
    __weak __typeof(self) weakSelf = self;
    ref.onChangeBlock = ^{
        ITMNotification *notification = [weakSelf variableChangeNotificationWithScope:request.variableMonitorRequest.scope
                                                                           identifier:identifier
                                                                                 name:name
                                                                             newValue:weakRef.value];
        if (notification) {
            [weakSelf postAPINotification:notification toConnectionKey:connectionKey];
        }
    };
    [dict it_addObject:[iTermTuple tupleWithObject:request andObject:ref] toMutableArrayForKey:connectionKey];
}

- (BOOL)monitorVariableChangesForConnectionKey:(NSString *)connectionKey
                                    identifier:(NSString *)identifier
                                       request:(ITMNotificationRequest *)request
                          mutableVariablesDict:(NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *)dict {
    iTermVariableScope *scope = [self scopeForCategory:request.variableMonitorRequest.scope identifier:identifier];
    if (scope == nil) {
        return NO;
    }
    [self monitorVariableChangesForConnectionKey:connectionKey
                                      identifier:identifier
                                         request:request
                                           scope:scope
                            mutableVariablesDict:dict];
    return YES;
}

- (ITMNotificationResponse *)handleVariableChangeNotificationRequest:(ITMNotificationRequest *)request
                                                       connectionKey:(NSString *)connectionKey {
    ITMNotificationResponse *response = [[ITMNotificationResponse alloc] init];
    if (!request.hasSubscribe) {
        response.status = ITMNotificationResponse_Status_RequestMalformed;
        return response;
    }

    // Handle the special case of (un)subscribing to "all" sessions.
    NSString *identifier = request.variableMonitorRequest.identifier;
    if ([identifier isEqualToString:@"all"]) {
        switch (request.variableMonitorRequest.scope) {
            case ITMVariableScope_Session:
                return [self handleSubscriptionRequestForAllSessionsFromConnectionKey:connectionKey
                                                                              request:request];
            case ITMVariableScope_Window:
                return [self handleSubscriptionRequestForAllWindowsFromConnectionKey:connectionKey
                                                                             request:request];
            case ITMVariableScope_App:
            case ITMVariableScope_Tab:
                // TODO
                response.status = ITMNotificationResponse_Status_InvalidIdentifier;
                return response;
        }
    }

    NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *subscriptions =
        [self subscriptionsForVariableChangeScope:request.variableMonitorRequest.scope];
    NSMutableArray *array = subscriptions[connectionKey];
    const NSInteger index = [array indexOfObjectPassingTest:^BOOL(iTermTuple<ITMNotificationRequest *, iTermVariableReference *> * _Nonnull tuple,
                                                                  NSUInteger idx,
                                                                  BOOL * _Nonnull stop) {
        return ([NSObject object:tuple.firstObject.variableMonitorRequest isEqualToObject:request.variableMonitorRequest]);
    }];
    if (request.subscribe) {
        if (array != nil && index != NSNotFound) {
            response.status = ITMNotificationResponse_Status_AlreadySubscribed;
            return response;
        }
        BOOL ok = [self monitorVariableChangesForConnectionKey:connectionKey
                                                    identifier:identifier
                                                       request:request
                                          mutableVariablesDict:subscriptions];
        if (ok) {
            response.status = ITMNotificationResponse_Status_Ok;
        } else {
            response.status = ITMNotificationResponse_Status_InvalidIdentifier;
        }
        return response;
    } else {
        if (index == NSNotFound) {
            response.status = ITMNotificationResponse_Status_NotSubscribed;
            return response;
        }
        iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *tuple = array[index];
        [tuple.secondObject removeAllLinks];
        [array removeObjectAtIndex:index];
        response.status = ITMNotificationResponse_Status_Ok;
        return response;
    }
}

- (ITMNotification *)variableChangeNotificationWithScope:(ITMVariableScope)scope
                                              identifier:(NSString *)identifier
                                                    name:(NSString *)variableName
                                                newValue:(id)newValue {
    ITMNotification *notification = [[ITMNotification alloc] init];
    notification.variableChangedNotification.scope = scope;
    if (identifier != nil) {
        notification.variableChangedNotification.identifier = identifier;
    }
    notification.variableChangedNotification.name = variableName;
    notification.variableChangedNotification.jsonNewValue = [NSJSONSerialization it_jsonStringForObject:newValue];
    return notification;
}

- (void)didRegisterStatusBarComponent:(ITMRPCRegistrationRequest_StatusBarComponentAttributes *)attributes
                         onConnection:(NSString *)connectionKey {
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermAPIDidRegisterStatusBarComponentNotification
                                                        object:attributes.uniqueIdentifier];
    NSString *key = connectionKey ? [_apiServer websocketKeyForConnectionKey:connectionKey] : nil;
    iTermScriptHistoryEntry *entry = key ? [[iTermScriptHistory sharedInstance] entryWithIdentifier:key] : nil;
    if (!entry) {
        return;
    }
    NSString *fullPath = entry.fullPath;
    if (!fullPath) {
        return;
    }
    NSString *uniqueID = attributes.uniqueIdentifier;
    return [[NSUserDefaults standardUserDefaults] setObject:fullPath
                                                     forKey:[self.class userDefaultsKeyForNameOfScriptVendingStatusBarComponentWithID:uniqueID]];
}

- (ITMNotificationResponse *)handleAPINotificationRequest:(ITMNotificationRequest *)request
                                            connectionKey:(NSString *)connectionKey {
    ITMNotificationResponse *response = [[ITMNotificationResponse alloc] init];
    if (!request.hasSubscribe) {
        response.status = ITMNotificationResponse_Status_RequestMalformed;
        return response;
    }
    [self createSubscriptionDictionariesIfNeeded];
    NSMutableDictionary<id, ITMNotificationRequest *> *subscriptions;
    if (request.notificationType == ITMNotificationType_NotifyOnNewSession) {
        subscriptions = _newSessionSubscriptions;
    } else if (request.notificationType == ITMNotificationType_NotifyOnTerminateSession) {
        subscriptions = _terminateSessionSubscriptions;
    } else if (request.notificationType == ITMNotificationType_NotifyOnLayoutChange) {
        subscriptions = _layoutChangeSubscriptions;
    } else if (request.notificationType == ITMNotificationType_NotifyOnFocusChange) {
        subscriptions = _focusChangeSubscriptions;
    } else if (request.notificationType == ITMNotificationType_NotifyOnBroadcastChange) {
        subscriptions = _broadcastDomainChangeSubscriptions;
    } else if (request.notificationType == ITMNotificationType_NotifyOnProfileChange) {
        subscriptions = _profileChangeSubscriptions;
    } else if (request.notificationType == ITMNotificationType_NotifyOnServerOriginatedRpc) {
        if (![self rpcNotificationRequestIsValid:request connectionKey:connectionKey]) {
            XLog(@"RPC notification request invalid: %@", request);
            response.status = ITMNotificationResponse_Status_RequestMalformed;
            return response;
        }

        NSString *signatureString = request.rpcRegistrationRequest.it_stringRepresentation;
        if (request.subscribe) {
            if (self.serverOriginatedRPCSubscriptions[signatureString]) {
                response.status = ITMNotificationResponse_Status_DuplicateServerOriginatedRpc;
                return response;
            }
            [self setServerOriginatedRPCSubscriptionWithSignature:signatureString
                                                    connectionKey:connectionKey
                                                          request:request];
            [[NSNotificationCenter defaultCenter] postNotificationName:iTermAPIRegisteredFunctionsDidChangeNotification
                                                                object:nil];
            switch (request.rpcRegistrationRequest.role) {
                case ITMRPCRegistrationRequest_Role_SessionTitle:
                    [[NSNotificationCenter defaultCenter] postNotificationName:iTermAPIDidRegisterSessionTitleFunctionNotification
                                                                        object:request.rpcRegistrationRequest.name];
                    break;
                case ITMRPCRegistrationRequest_Role_Generic:
                    break;
                case ITMRPCRegistrationRequest_Role_StatusBarComponent:
                    [self didRegisterStatusBarComponent:request.rpcRegistrationRequest.statusBarComponentAttributes
                                           onConnection:connectionKey];
                case ITMRPCRegistrationRequest_Role_ContextMenu:
                    break;
            }
        } else {
            if (!self.serverOriginatedRPCSubscriptions[signatureString] ||
                self.serverOriginatedRPCSubscriptions[signatureString].firstObject != connectionKey) {
                response.status = ITMNotificationResponse_Status_NotSubscribed;
                return response;
            }
            [self removeServerOriginatedRPCSubscriptionWithSignature:signatureString];
        }
        response.status = ITMNotificationResponse_Status_Ok;
        return response;
    } else {
        assert(false);
    }
    if (request.subscribe) {
        if (subscriptions[connectionKey]) {
            response.status = ITMNotificationResponse_Status_AlreadySubscribed;
            return response;
        }
        subscriptions[connectionKey] = request;
    } else {
        if (!subscriptions[connectionKey]) {
            response.status = ITMNotificationResponse_Status_NotSubscribed;
            return response;
        }
        [subscriptions removeObjectForKey:connectionKey];
    }

    response.status = ITMNotificationResponse_Status_Ok;
    return response;
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

- (BOOL)unsubscribeFromVariableChangeNotificationsForAllObjects:(NSArray<id<iTermSubscribable>> *)objects
                                                    mutableSubs:(NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *)subs
                                               forConnectionKey:(NSString *)connectionKey
                                                        request:(ITMNotificationRequest *)request {
    NSMutableArray *array = subs[connectionKey];
    NSIndexSet *indexes = [array indexesOfObjectsPassingTest:^BOOL(iTermTuple<ITMNotificationRequest *, iTermVariableReference *> * _Nonnull tuple,
                                                                   NSUInteger idx,
                                                                   BOOL * _Nonnull stop) {
        return ([NSObject object:tuple.firstObject.variableMonitorRequest isEqualToObject:request.variableMonitorRequest]);
    }];

    [indexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL * _Nonnull stop) {
        iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *tuple = array[index];
        [tuple.secondObject removeAllLinks];
    }];
    [array removeObjectsAtIndexes:indexes];

    return indexes.count > 0;
}

- (void)subscribeToVariableChangeNotificationsForAllObjects:(NSArray<id<iTermSubscribable>> *)objects
                                       mutableVariablesDict:(NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *)dict
                                           forConnectionKey:(NSString *)connectionKey
                                                    request:(ITMNotificationRequest *)request {
    for (id<iTermSubscribable> object in objects) {
        [self monitorVariableChangesForConnectionKey:connectionKey
                                          identifier:object.subscribableIdentifier
                                             request:request
                                mutableVariablesDict:dict];
    }
}

- (ITMNotificationResponse *)handleVariableSubscriptionRequestForAllObjects:(NSArray<id<iTermSubscribable>> *)objects
                                                       mutableVariablesDict:(NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *)dict
                                                              forConnection:(NSString *)connectionKey
                                                                    request:(ITMNotificationRequest *)request {
    [self createSubscriptionDictionariesIfNeeded];
    if (request.subscribe) {
        [self subscribeToVariableChangeNotificationsForAllObjects:objects
                                             mutableVariablesDict:dict
                                                 forConnectionKey:connectionKey
                                                          request:request];
        ITMNotificationResponse *response = [[ITMNotificationResponse alloc] init];
        response.status = ITMNotificationResponse_Status_Ok;
        return response;
    }

    const BOOL wasSubscribed = [self unsubscribeFromVariableChangeNotificationsForAllObjects:objects
                                                                                 mutableSubs:dict
                                                                            forConnectionKey:connectionKey
                                                                                     request:request];
    ITMNotificationResponse *response = [[ITMNotificationResponse alloc] init];
    if (wasSubscribed) {
        response.status = ITMNotificationResponse_Status_Ok;
    } else {
        response.status = ITMNotificationResponse_Status_NotSubscribed;
    }
    return response;
}

- (ITMNotificationResponse *)handleSubscriptionRequestForAllObjects:(NSArray<id<iTermSubscribable>> *)objects
                                                        mutableSubs:(NSMutableArray<iTermAllObjectsSubscription *> *)subscriptions
                                               mutableVariablesDict:(NSMutableDictionary<id, NSMutableArray<iTermTuple<ITMNotificationRequest *, iTermVariableReference *> *> *> *)dict
                                                  fromConnectionKey:(NSString *)connectionKey
                                                            request:(ITMNotificationRequest *)request {
    if (request.notificationType == ITMNotificationType_NotifyOnVariableChange) {
        ITMNotificationResponse *response = [self handleVariableSubscriptionRequestForAllObjects:objects
                                                                            mutableVariablesDict:dict
                                                                                   forConnection:connectionKey
                                                                                         request:request];
        if (response.status != ITMNotificationResponse_Status_Ok) {
            return response;
        }
    } else {
        for (id<iTermSubscribable> object in objects) {
            ITMNotificationResponse *response = [object handleAPINotificationRequest:request
                                                                       connectionKey:connectionKey];
            if (response.status != ITMNotificationResponse_Status_AlreadySubscribed &&
                response.status != ITMNotificationResponse_Status_NotSubscribed &&
                response.status != ITMNotificationResponse_Status_Ok) {
                return response;
            }
        }
    }

    if (request.subscribe) {
        iTermAllObjectsSubscription *sub = [[iTermAllObjectsSubscription alloc] init];
        sub.request = [request copy];
        sub.connectionKey = connectionKey;
        [subscriptions addObject:sub];
    } else {
        ITMNotificationRequest *requestToRemove = [request copy];
        requestToRemove.subscribe = YES;
        const NSInteger countBefore = subscriptions.count;
        [subscriptions removeObjectsPassingTest:^BOOL(iTermAllObjectsSubscription *sub) {
            return [NSObject object:sub.request isEqualToObject:requestToRemove];
        }];
        const NSInteger countAfter = subscriptions.count;
        if (countBefore == countAfter) {
            ITMNotificationResponse *response = [[ITMNotificationResponse alloc] init];
            response.status = ITMNotificationResponse_Status_NotSubscribed;
            return response;
        }
    }
    ITMNotificationResponse *response = [[ITMNotificationResponse alloc] init];
    response.status = ITMNotificationResponse_Status_Ok;
    return response;
}


- (ITMNotificationResponse *)handleSubscriptionRequestForAllSessionsFromConnectionKey:(NSString *)connectionKey
                                                                              request:(ITMNotificationRequest *)request {
    return [self handleSubscriptionRequestForAllObjects:[self allSessions]
                                            mutableSubs:_allSessionsSubscriptions
                                   mutableVariablesDict:_allSessionVariableSubscriptions
                                      fromConnectionKey:connectionKey
                                                request:request];
}

- (ITMNotificationResponse *)handleSubscriptionRequestForAllWindowsFromConnectionKey:(NSString *)connectionKey
                                                                             request:(ITMNotificationRequest *)request {
    return [self handleSubscriptionRequestForAllObjects:[[iTermController sharedInstance] terminals]
                                            mutableSubs:_allWindowsSubscriptions
                                   mutableVariablesDict:_allWindowVariableSubscriptions
                                      fromConnectionKey:connectionKey
                                                request:request];
}

- (void)apiServerNotification:(ITMNotificationRequest *)request
                connectionKey:(NSString *)connectionKey
                      handler:(void (^)(ITMNotificationResponse *))handler {
    if (request.notificationType == ITMNotificationType_NotifyOnVariableChange) {
        handler([self handleVariableChangeNotificationRequest:request
                                                connectionKey:connectionKey]);
        return;
    }
    if (request.notificationType == ITMNotificationType_NotifyOnNewSession ||
        request.notificationType == ITMNotificationType_NotifyOnTerminateSession ||
        request.notificationType == ITMNotificationType_NotifyOnLayoutChange ||
        request.notificationType == ITMNotificationType_NotifyOnFocusChange ||
        request.notificationType == ITMNotificationType_NotifyOnServerOriginatedRpc ||
        request.notificationType == ITMNotificationType_NotifyOnBroadcastChange) {
        handler([self handleAPINotificationRequest:request
                                     connectionKey:connectionKey]);
    } else if ([request.session isEqualToString:@"all"]) {
        ITMNotificationResponse *response = [self handleSubscriptionRequestForAllSessionsFromConnectionKey:connectionKey
                                                                                                   request:request];
        handler(response);
    } else {
        PTYSession *session = [self sessionForAPIIdentifier:request.session includeBuriedSessions:YES];
        if (!session) {
            ITMNotificationResponse *response = [[ITMNotificationResponse alloc] init];
            response.status = ITMNotificationResponse_Status_SessionNotFound;
            handler(response);
        } else {
            handler([session handleAPINotificationRequest:request
                                            connectionKey:connectionKey]);
        }
    }
}

- (void)removeAllSubscriptionsForConnectionKey:(id)connectionKey {
    // Remove all notification subscriptions.
    // RPCs are special.
    NSInteger rpcsRemoved = [self removeServerOriginatedRPCSubscriptionsPasstingTest:
         ^BOOL(NSString *signature,
               iTermTuple<id, ITMNotificationRequest *> *tuple) {
             return [tuple.firstObject isEqual:connectionKey];
         }];
    [_allSessionVariableSubscriptions[connectionKey] enumerateObjectsUsingBlock:^(iTermTuple<ITMNotificationRequest *,iTermVariableReference *> * _Nonnull tuple, NSUInteger idx, BOOL * _Nonnull stop) {
        [tuple.secondObject removeAllLinks];
    }];
    [_allWindowVariableSubscriptions[connectionKey] enumerateObjectsUsingBlock:^(iTermTuple<ITMNotificationRequest *,iTermVariableReference *> * _Nonnull tuple, NSUInteger idx, BOOL * _Nonnull stop) {
        [tuple.secondObject removeAllLinks];
    }];
    NSMutableDictionary *empty = [NSMutableDictionary dictionary];
    NSArray<NSMutableDictionary<id, ITMNotificationRequest *> *> *dicts =
    @[ _newSessionSubscriptions ?: empty,
       _profileChangeSubscriptions ?: empty,
       _terminateSessionSubscriptions  ?: empty,
       _layoutChangeSubscriptions ?: empty,
       _focusChangeSubscriptions ?: empty,
       _broadcastDomainChangeSubscriptions ?: empty,
       _allSessionVariableSubscriptions ?: empty,
       _allWindowVariableSubscriptions ?: empty];
    [dicts enumerateObjectsUsingBlock:^(NSMutableDictionary<id,ITMNotificationRequest *> * _Nonnull dict,
                                        NSUInteger idx,
                                        BOOL * _Nonnull stop) {
        [dict removeObjectForKey:connectionKey];
    }];
    [_allSessionsSubscriptions removeObjectsPassingTest:^BOOL(iTermAllObjectsSubscription *sub) {
        return [sub.connectionKey isEqual:connectionKey];
    }];
    [_allWindowsSubscriptions removeObjectsPassingTest:^BOOL(iTermAllObjectsSubscription *sub) {
        return [sub.connectionKey isEqual:connectionKey];
    }];
    if (rpcsRemoved) {
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermAPIRegisteredFunctionsDidChangeNotification
                                                            object:nil];
    }
}

- (void)apiServerDidCloseConnectionWithKey:(id)connectionKey {
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermRemoveAPIServerSubscriptionsNotification object:connectionKey];

    // Clean up outstanding iterm2->script RPCs.
    NSSet<NSString *> *requestIDs = _outstandingRPCs[connectionKey];
    [_outstandingRPCs removeObjectForKey:connectionKey];
    for (NSString *requestID in requestIDs) {
        iTermServerOriginatedRPCCompletionBlock completion = _serverOriginatedRPCCompletionBlocks[requestID];
        // completion will be nil if it already timed out
        if (completion) {
            [_serverOriginatedRPCCompletionBlocks removeObjectForKey:requestID];
            completion(nil, [self rpcDispatchError:@"Script terminated during function call"
                                            detail:nil
                                      unregistered:YES
                                     connectionKey:connectionKey]);
        }
    }

    [self removeAllSubscriptionsForConnectionKey:connectionKey];
}

- (void)apiServerRegisterTool:(ITMRegisterToolRequest *)request
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
    ITMSetProfilePropertyResponse_Status (^setter)(id object, NSArray<iTermTuple<NSString *, id> *> *assignments) = nil;
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
            setter = ^ITMSetProfilePropertyResponse_Status(id object, NSArray<iTermTuple<NSString *, id> *> *assignments) {
                Profile *profile = object;
                for (iTermTuple<NSString *, id> *assignment in assignments) {
                    [iTermProfilePreferences setObject:assignment.secondObject
                                                forKey:assignment.firstObject
                                             inProfile:profile
                                                 model:[ProfileModel sharedInstance]];
                    if ([assignment.firstObject isEqualToString:KEY_KEYBOARD_MAP]) {
                        [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification object:nil];
                    }
                }
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
            setter = ^ITMSetProfilePropertyResponse_Status(id object, NSArray<iTermTuple<NSString *, id> *> *assignments) {
                return [(PTYSession *)object handleSetProfilePropertyForAssignments:assignments
                                                                 scriptHistoryEntry:entry];
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

    NSArray<iTermTuple<NSString *, id> *> *assignments;
    if (request.hasKey && request.hasJsonValue) {
        // DEPRECATED CODE PATH - REMOVE THIS AFTER ENSURING EVERYONE HAS BEEN FORCED TO UPGRADE TO 0.69
        assignments = @[ [iTermTuple tupleWithObject:request.key andObject:request.jsonValue] ];
    } else {
        assignments = [request.assignmentsArray mapWithBlock:^id(ITMSetProfilePropertyRequest_Assignment *assignment) {
            return [iTermTuple tupleWithObject:assignment.key andObject:assignment.jsonValue];
        }];
    }

    __block NSError *error = nil;
    assignments = [assignments mapWithBlock:^id(iTermTuple<NSString *,id> *tuple) {
        if (error) {
            return nil;
        }
        id value = [NSJSONSerialization JSONObjectWithData:[tuple.secondObject dataUsingEncoding:NSUTF8StringEncoding]
                                                   options:NSJSONReadingAllowFragments
                                                     error:&error];
        if (!value || error) {
            XLog(@"JSON parsing error %@ for value in request %@", error, request);
            error = error ?: [NSError errorWithDomain:iTermAPIHelperErrorDomain
                                                 code:iTermAPIHelperErrorCodeInvalidJSON
                                             userInfo:nil];
            return nil;
        }
        return [iTermTuple tupleWithObject:tuple.firstObject andObject:value];
    }];

    if (error) {
        ITMSetProfilePropertyResponse *response = [[ITMSetProfilePropertyResponse alloc] init];
        response.status = ITMSetProfilePropertyResponse_Status_RequestMalformed;
        handler(response);
        return;
    }

    for (id object in objects) {
        response.status = setter(object, assignments);
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
            if (tab.isMaximized) {
                for (PTYSession *session in [tab minimizedSessions]) {
                    ITMSessionSummary *sessionSummary = [[ITMSessionSummary alloc] init];
                    sessionSummary.uniqueIdentifier = session.guid;
                    sessionSummary.title = session.name;
                    [tabMessage.minimizedSessionsArray addObject:sessionSummary];
                }
            }
            tabMessage.tmuxWindowId = [@(tab.tmuxWindow) stringValue];
            if (tab.tmuxController) {
                tabMessage.tmuxConnectionId = tab.tmuxController.clientName;
            }
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

    iTermSessionLauncher *launcher = [[iTermSessionLauncher alloc] initWithProfile:profile windowController:term];
    launcher.canActivate = NO;
    launcher.makeSession = ^(NSDictionary * _Nonnull profile, PseudoTerminal * _Nonnull term, void (^ _Nonnull didMakeSession)(PTYSession * _Nullable)) {
        profile = [self profileByCustomizing:profile withProperties:request.customProfilePropertiesArray];
        [term asyncCreateTabWithProfile:profile
                            withCommand:nil
                            environment:nil
                               tabIndex:nil
                         didMakeSession:^(PTYSession *session) { didMakeSession(session); }
                             completion:nil];
    };
    __weak __typeof(self) weakSelf = self;
    [launcher launchWithCompletion:^(PTYSession *session, BOOL ok) {
        [weakSelf didCreateSession:ok ? session : nil forRequest:request handler:handler];
    }];
}

- (void)didCreateSession:(PTYSession *)session
              forRequest:(ITMCreateTabRequest *)request
                 handler:(void (^)(ITMCreateTabResponse *))handler {
    if (!session) {
        ITMCreateTabResponse *response = [[ITMCreateTabResponse alloc] init];
        response.status = ITMCreateTabResponse_Status_MissingSubstitution;
        handler(response);
        return;
    }

    PseudoTerminal *term = [[iTermController sharedInstance] terminalWithSession:session];
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
        if (!session) {
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
    dispatch_group_t group = dispatch_group_create();
    for (PTYSession *session in sessions) {
        PseudoTerminal *term = [[iTermController sharedInstance] terminalWithSession:session];
        const BOOL vertical = request.splitDirection == ITMSplitPaneRequest_SplitDirection_Vertical;
        dispatch_group_enter(group);
        [term asyncSplitVertically:vertical
                            before:request.before
                           profile:profile
                     targetSession:session
                   completion:^(PTYSession *newSession, BOOL ok) {
            if (newSession && newSession.guid) {  // The test for newSession.guid is just to quiet the analyzer
                [response.sessionIdArray addObject:newSession.guid];
            } else if (newSession == nil && !session.isTmuxClient) {
                response.status = ITMSplitPaneResponse_Status_CannotSplit;
            }
            dispatch_group_leave(group);
        }
                             ready:nil];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        handler(response);
    });
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

    if (request.orderWindowFront) {
        if (!windowController) {
            response.status = ITMActivateResponse_Status_InvalidOption;
            handler(response);
            return;
        }
        [windowController.window makeKeyAndOrderFront:nil];
    }

    if (request.selectTab) {
        if (!tab) {
            response.status = ITMActivateResponse_Status_InvalidOption;
            handler(response);
            return;
        }
        [windowController.tabView selectTabViewItemWithIdentifier:tab];
    }

    if (request.selectSession) {
        if (!session) {
            response.status = ITMActivateResponse_Status_InvalidOption;
            handler(response);
            return;
        }
        if (tab.isMaximized && tab.activeSession != session) {
            [tab unmaximize];
            [tab setActiveSession:session];
            [tab maximize];
        } else {
            [tab setActiveSession:session];
        }
    }

    response.status = ITMActivateResponse_Status_Ok;
    handler(response);
}

- (void)apiServerVariable:(ITMVariableRequest *)request handler:(void (^)(ITMVariableResponse *))handler {
    NSString *userPrefix = @"user.";
    const BOOL allSetNamesLegal = [request.setArray allWithBlock:^BOOL(ITMVariableRequest_Set *setRequest) {
        return ([setRequest.name hasPrefix:userPrefix] &&
                [[setRequest.name substringFromIndex:userPrefix.length] rangeOfString:@"."].location == NSNotFound);
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

        case ITMVariableRequest_Scope_OneOfCase_WindowId:
            [self handleWindowScopeVariableRequest:request handler:handler];
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
    BOOL ok = [self handleVariableSetsInRequest:request scope:[iTermVariableScope globalsScope]];
    [self handleVariableGetsInRequest:request response:response scope:[iTermVariableScope globalsScope]];
    response.status = ok ? ITMVariableResponse_Status_Ok : ITMVariableResponse_Status_InvalidName;
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

- (void)handleWindowScopeVariableRequest:(ITMVariableRequest *)request
                                 handler:(void (^)(ITMVariableResponse *))handler {
    if ([request.sessionId isEqualToString:@"all"]) {
        NSArray<iTermVariableScope *> *scopes = [[iTermController sharedInstance].terminals mapWithBlock:^id(PseudoTerminal *anObject) {
            return anObject.scope;
        }];
        handler([self handleVariableMultiSetRequest:request scopes:scopes]);
        return;
    }
    
    ITMVariableResponse *response = [[ITMVariableResponse alloc] init];
    PseudoTerminal *windowController = [self windowControllerWithID:request.windowId];
    if (!windowController) {
        response.status = ITMVariableResponse_Status_WindowNotFound;
        handler(response);
        return;
    }
    
    [self handleVariableSetsInRequest:request scope:windowController.scope];
    [self handleVariableGetsInRequest:request response:response scope:windowController.scope];
    
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

- (BOOL)handleVariableSetsInRequest:(ITMVariableRequest *)request scope:(iTermVariableScope *)scope {
    __block BOOL result = YES;
    [request.setArray enumerateObjectsUsingBlock:^(ITMVariableRequest_Set * _Nonnull setRequest, NSUInteger idx, BOOL * _Nonnull stop) {
        id value;
        if ([setRequest.value isEqual:@"null"]) {
            value = nil;
        } else {
            value = [NSJSONSerialization it_objectForJsonString:setRequest.value];
        }
        const BOOL ok = [scope setValue:value forVariableNamed:setRequest.name];
        if (!ok) {
            result = NO;
        }
    }];
    return result;
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

        case ITMSavedArrangementRequest_Action_List:
            [self listSavedArrangementsWithHandler:handler];
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

- (void)listSavedArrangementsWithHandler:(void (^)(ITMSavedArrangementResponse *))handler {
    ITMSavedArrangementResponse *response = [[ITMSavedArrangementResponse alloc] init];
    response.status = ITMSavedArrangementResponse_Status_Ok;
    for (NSString *name in [WindowArrangements allNames]) {
        [response.namesArray addObject:name];
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
    NSString *key = result.requestId;
    if (!key) {
        DLog(@"Bogus key %@", key);
        return;
    }

    iTermServerOriginatedRPCCompletionBlock block = _serverOriginatedRPCCompletionBlocks[key];
    if (!block) {
        // Could be a timeout already occurred.
        DLog(@"Key %@ doesn't match a pending RPC", key);
        return;
    }
    [_serverOriginatedRPCCompletionBlocks removeObjectForKey:key];

    id value = nil;
    NSDictionary *exception = nil;
    NSError *error = nil;

    switch (result.resultOneOfCase) {
        case ITMServerOriginatedRPCResultRequest_Result_OneOfCase_JsonValue:
            value = [NSJSONSerialization JSONObjectWithData:[result.jsonValue dataUsingEncoding:NSUTF8StringEncoding]
                                                    options:NSJSONReadingAllowFragments
                                                      error:&error];
            if (!value || error) {
                value = nil;
                exception = @{ @"reason": [NSString stringWithFormat:@"Undecodable value: %@", error.localizedDescription] };
            }
            break;

        case ITMServerOriginatedRPCResultRequest_Result_OneOfCase_JsonException:
            exception = [NSJSONSerialization JSONObjectWithData:[result.jsonException dataUsingEncoding:NSUTF8StringEncoding]
                                                        options:NSJSONReadingAllowFragments
                                                          error:&error];
            if (error) {
                exception = @{ @"reason": [NSString stringWithFormat:@"Undecodable exception: %@", error.localizedDescription] };
            } else {
                exception = [NSDictionary castFrom:exception] ?: @{ @"reason": @"Malformed exception" };
            }
            break;

        case ITMServerOriginatedRPCResultRequest_Result_OneOfCase_GPBUnsetOneOfCase:
            exception = @{ @"reason": @"Malformed result." };
            break;
    }

    if (exception) {
        block(nil, [self rpcDispatchError:exception[@"reason"]
                                   detail:exception[@"traceback"]
                             unregistered:NO
                            connectionKey:connectionKey]);
    } else {
        if ([NSNull castFrom:value]) {
            value = nil;
        }
        block(value, nil);
    }
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
    response.checked = menuItem.state == NSControlStateValueOn;
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
                                 size:[PTYTab sizeForTmuxWindowWithAffinity:request.hasAffinity ? request.affinity : nil
                                                                 controller:controller]
                     initialDirectory:[iTermInitialDirectory initialDirectoryFromProfile:controller.sharedProfile
                                                                              objectType:iTermWindowObject]
                                index:nil
                                scope:[iTermVariableScope globalsScope]
                           completion:^(int newWindowId) {
        if (newWindowId >= 0) {
            PTYTab *tab = [controller window:newWindowId];
            response.createWindow.tabId = [NSString stringWithFormat:@"%d", tab.uniqueId];
        }
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

        [controller openWindowWithId:[[request windowId] intValue]
                         intentional:YES
                             profile:controller.sharedProfile];
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
        case ITMPreferencesRequest_Request_Request_OneOfCase_GetDefaultProfileRequest:
            result.getDefaultProfileResult = [self handleGetDefaultProfile];
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
    [iTermPreferences setObject:obj forKey:key];
    result.status = ITMPreferencesResponse_Result_SetPreferenceResult_Status_Ok;

    return result;
}

- (ITMPreferencesResponse_Result_GetDefaultProfileResult *)handleGetDefaultProfile {
    ITMPreferencesResponse_Result_GetDefaultProfileResult *result = [[ITMPreferencesResponse_Result_GetDefaultProfileResult alloc] init];
    result.guid = [[[ProfileModel sharedInstance] defaultBookmark] objectForKey:KEY_GUID];
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
        const long long overflow = session.screen.totalScrollbackOverflow;
        const VT100GridWindowedRange relativeRange = VT100GridWindowedRangeFromAbsWindowedRange(sub.absRange, overflow);
        subProto.windowedCoordRange.coordRange.start.x = relativeRange.coordRange.start.x;
        subProto.windowedCoordRange.coordRange.start.y = absoluteOffset + relativeRange.coordRange.start.y;
        subProto.windowedCoordRange.coordRange.end.x = relativeRange.coordRange.end.x;
        subProto.windowedCoordRange.coordRange.end.y = absoluteOffset + relativeRange.coordRange.end.y;
        subProto.connected = sub.connected;
        if (relativeRange.columnWindow.length > 0) {
            subProto.windowedCoordRange.columns.location = relativeRange.columnWindow.location;
            subProto.windowedCoordRange.columns.length = relativeRange.columnWindow.length;
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
        const long long overflow = session.screen.totalScrollbackOverflow;
        VT100GridAbsWindowedRange absRange = VT100GridAbsWindowedRangeFromWindowedRange(range, overflow);
        iTermSubSelection *sub = [iTermSubSelection subSelectionWithAbsRange:absRange mode:mode width:width];
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
        }
    }

    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        NSArray<NSArray<PTYSession *> *> *sessionGroupsForWindow = [sessionGroups filteredArrayUsingBlock:^BOOL(NSArray<PTYSession *> *sessionGroup) {
            return [PseudoTerminal castFrom:sessionGroup.firstObject.delegate.realParentWindow] == term;
        }];
        [term setBroadcastingSessions:sessionGroupsForWindow];
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
        case ITMInvokeFunctionRequest_Context_OneOfCase_Method:
            if (!request.method.hasReceiver) {
                ITMInvokeFunctionResponse *response = [[ITMInvokeFunctionResponse alloc] init];
                response.error.status = ITMInvokeFunctionResponse_Status_RequestMalformed;
                response.error.errorReason = @"No receiver";
                completion(response);
                return;
            }
            [self invokeMethod:request.invocation receiver:request.method.receiver completion:completion timeout:request.timeout];
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
                               retainSelf:YES
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
                               retainSelf:YES
                               completion:^(id object, NSError *error, NSSet<NSString *> *missing) {
                                   [self functionInvocationDidCompleteWithObject:object error:error completion:completion];
                               }];
}

- (void)invokeMethod:(NSString *)invocation
            receiver:(NSString *)receiver
          completion:(void (^)(ITMInvokeFunctionResponse *))completion
             timeout:(NSTimeInterval)timeout {
    [iTermScriptFunctionCall callMethod:invocation
                               receiver:receiver
                                timeout:timeout >= 0 ? timeout : 30
                             retainSelf:YES
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
                               retainSelf:YES
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
                               retainSelf:YES
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
            response.error.status = ITMInvokeFunctionResponse_Status_Timeout;
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

@end
