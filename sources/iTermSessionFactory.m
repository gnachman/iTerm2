//
//  iTermSessionFactory.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/3/18.
//

#import "iTermSessionFactory.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermController.h"
#import "iTermInitialDirectory.h"
#import "iTermProfilePreferences.h"
#import "iTermParameterPanelWindowController.h"
#import "iTermScriptFunctionCall.h"
#import "iTermVariableScope.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "PTYSession.h"
#import "PseudoTerminal.h"

NS_ASSUME_NONNULL_BEGIN

@protocol iTermSessionAttachOrLaunchRequestDelegate<NSObject>
- (nullable NSString *)attachOrLaunchRequest:(iTermSessionAttachOrLaunchRequest *)request
                          promptForParameter:(NSString *)name
                           promptingDisabled:(BOOL)promptingDisabled
                                    inWindow:(nonnull NSWindow *)window;
@end

@interface iTermSessionAttachOrLaunchRequest()
@property (nonatomic, weak) id<iTermSessionAttachOrLaunchRequestDelegate> delegate;
@property (nonatomic, readonly) Profile *profileForComputingCommand;
@property (nonatomic, readonly) Profile *profile;
@property (nonatomic, readonly, copy) NSString *computedCommand;
@property (nullable, nonatomic, readonly) NSString *name;
@property (nullable, nonatomic, readonly) NSString *workingDirectory;
@end

@implementation iTermSessionAttachOrLaunchRequest

+ (instancetype)launchRequestWithSession:(PTYSession *)aSession
                               canPrompt:(BOOL)canPrompt
                              objectType:(iTermObjectType)objectType
                        hasServerConnection:(BOOL)hasServerConnection
                        serverConnection:(iTermGeneralServerConnection)serverConnection
                               urlString:(nullable NSString *)urlString
                            allowURLSubs:(BOOL)allowURLSubs
                             environment:(nullable NSDictionary *)environment
                             customShell:(nullable NSString *)customShell
                                  oldCWD:(nullable NSString *)oldCWD
                          forceUseOldCWD:(BOOL)forceUseOldCWD
                                 command:(nullable NSString *)command
                                  isUTF8:(nullable NSNumber *)isUTF8Number
                           substitutions:(nullable NSDictionary *)substitutions
                        windowController:(PseudoTerminal * _Nonnull)windowController
                                   ready:(void (^ _Nullable)(BOOL ok))ready
                              completion:(void (^ _Nullable)(PTYSession * _Nullable, BOOL))completion {
    iTermSessionAttachOrLaunchRequest *request = [[self alloc] init];
    request.session = aSession;
    request.canPrompt = canPrompt;
    request.objectType = objectType;
    request.hasServerConnection = hasServerConnection;
    request.xx_serverConnection = serverConnection;
    request.urlString = urlString;
    request.allowURLSubs = allowURLSubs;
    request.environment = environment;
    request.oldCWD = oldCWD;
    request.forceUseOldCWD = forceUseOldCWD;
    request.command = command;
    request.completion = completion;
    if (isUTF8Number) {
        request.isUTF8 = isUTF8Number.boolValue;
    } else {
        const NSUInteger profileEncoding =
            [iTermProfilePreferences unsignedIntegerForKey:KEY_CHARACTER_ENCODING
                                                 inProfile:aSession.profile];
        request.isUTF8 = (profileEncoding == NSUTF8StringEncoding);
    }
    request.substitutions = substitutions;
    request.windowController = windowController;
    request.ready = ready;

    request->_profile = [aSession.profile copy];
    if (forceUseOldCWD) {
        request->_profileForComputingCommand = [request->_profile dictionaryBySettingObject:kProfilePreferenceInitialDirectoryCustomValue forKey:KEY_CUSTOM_DIRECTORY];
    } else {
        request->_profileForComputingCommand = request->_profile;
    }
    request.customShell = customShell ?: [ITAddressBookMgr customShellForProfile:request.profileForComputingCommand];
    request->_name = [request.profile[KEY_NAME] copy];

    return request;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p session=%@ canPrompt=%@ objectType=%@ serverConnection=%@ urlString=%@ allowURLSubs=%@ environment=%@ customShell=%@ oldCWD=%@ forceUseOldCWD=%@ command=%@ isUTF8=%@ substitutions=%@ windowController=%@>",
            NSStringFromClass(self.class),
            self,
            self.session,
            @(self.canPrompt),
            @(self.objectType),
            self.hasServerConnection ? @(self.xx_serverConnection.type) : @"none",
            self.urlString,
            @(self.allowURLSubs),
            self.environment,
            self.customShell,
            self.oldCWD,
            @(self.forceUseOldCWD),
            self.command,
            @(self.isUTF8),
            self.substitutions,
            self.windowController];
}

- (void)realizeWithCompletion:(void (^)(BOOL realized))completion {
    [self computeCommandWithCompletion:^{
        const BOOL ok = [self didComputeCommandWithCompletion:completion];
        if (self.ready) {
            self.ready(ok);
        }
    }];
}

#pragma mark - Private

- (NSString *)unescapeDoubleDollarsInString:(NSString *)string {
    return [string stringByReplacingOccurrencesOfString:@"$$$$" withString:@"$$"];
}

- (void)computeCommandWithCompletion:(void (^)(void))completion {
    if (self.command) {
        self->_computedCommand = [self unescapeDoubleDollarsInString:self.command];
        completion();
        return;
    }
    [ITAddressBookMgr computeCommandForProfile:self.profileForComputingCommand
                                    objectType:self.objectType
                                         scope:self.session.variablesScope
                                    completion:^(NSString *command) {
        self->_computedCommand = [self unescapeDoubleDollarsInString:command];
        completion();
    }];
}

- (void)computeWorkingDirectoryWithCompletion:(void (^)(void))completion {
    if (self.forceUseOldCWD) {
        [self setWorkingDirectory:self.oldCWD];
        completion();
        return;
    }

    if (!self.canPrompt) {
        [self setWorkingDirectory:@""];
        completion();
        return;
    }

    iTermInitialDirectory *initialDirectory = [iTermInitialDirectory initialDirectoryFromProfile:self.profile
                                                                                      objectType:self.objectType];
    // Keep the initial directory alive
    void *key = (void *)"iTermSessionFactory.initialDirectory";
    [self.session it_setAssociatedObject:initialDirectory forKey:key];
    [initialDirectory evaluateWithOldPWD:self.oldCWD
                                   scope:self.session.variablesScope
                              completion:^(NSString *pwd) {
        [self.session it_setAssociatedObject:nil forKey:key];
        [self setWorkingDirectory:pwd];
        completion();
    }];
}

- (BOOL)computeSubstitutions {
    if (self.substitutions) {
        return YES;
    }

    // If the command or name have any $$VARS$$ not accounted for above, prompt the user for
    // substitutions.
    self.substitutions = [self substitutionsAfterPrompting];

    if (self.substitutions) {
        return YES;
    }

    if (self.completion) {
        [self.session didFinishInitialization];
        // Ensure the controller has it before removing it, since this might get called by the controller.
        // TODO: Remove cyclic dependency
        dispatch_async(dispatch_get_main_queue(), ^{
            [[[iTermController sharedInstance] terminalWithSession:self.session] closeSessionWithoutConfirmation:self.session];
        });
        self.completion(nil, NO);
    }
    return NO;
}

- (BOOL)didComputeCommandWithCompletion:(void (^)(BOOL))completion {
    if (![self computeSubstitutions]) {
        completion(NO);
        return NO;
    }
    [self didComputeSubstitutions];
    [self computeWorkingDirectoryWithCompletion:^{
        completion(YES);
    }];
    return YES;
}

- (void)didComputeSubstitutions {
    _name = [self.name stringByPerformingSubstitutions:self.substitutions];
    [self updateVariables];
    [self.windowController setName:self.name ?: @""
                        forSession:self.session];
}

// Returns nil if the user pressed cancel, otherwise returns a dictionary that's a supeset of |substitutions|.
- (nullable NSDictionary *)substitutionsAfterPrompting {
    NSDictionary *baseSubstitutions = self.allowURLSubs ? [self substitutionsForURL:self.urlString] : @{};
    NSSet *cmdVars = [self.computedCommand doubleDollarVariables];
    NSSet *nameVars = [self.name doubleDollarVariables];
    NSMutableSet *allVars = [cmdVars mutableCopy];
    [allVars unionSet:nameVars];
    NSMutableDictionary *allSubstitutions = [baseSubstitutions mutableCopy];
    for (NSString *var in allVars) {
        if (!baseSubstitutions[var]) {
            NSString *value = [self.delegate attachOrLaunchRequest:self
                                                promptForParameter:var
                                                 promptingDisabled:!self.canPrompt
                                                          inWindow:self.windowController.window];
            if (!value) {
                return nil;
            }
            allSubstitutions[var] = value;
        }
    }
    return allSubstitutions;
}

- (NSDictionary *)substitutionsForURL:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    return @{ @"$$URL$$": urlString ?: @"",
              @"$$HOST$$": [url host] ?: @"",
              @"$$USER$$": [url user] ?: @"",
              @"$$PASSWORD$$": [url password] ?: @"",
              @"$$PORT$$": [url port] ? [[url port] stringValue] : @"",
              @"$$PATH$$": [url path] ?: @"",
              @"$$RES$$": [url resourceSpecifier] ?: @"" };
}

- (void)updateVariables {
    NSString *hostSub = self.substitutions[@"$$HOST$$"];
    if (hostSub) {
        [self.session.variablesScope setValue:hostSub forVariableNamed:iTermVariableKeySessionHostname];
    }

    NSString *userSub = self.substitutions[@"$$USER$$"];
    if (userSub) {
        [self.session.variablesScope setValue:userSub forVariableNamed:iTermVariableKeySessionUsername];
    }
}

- (void)setWorkingDirectory:(NSString *)suggestion {
    NSString *pwd = suggestion;
    DLog(@"using pwd of %@", pwd);
    if ([pwd length] == 0) {
        if (self.oldCWD) {
            pwd = self.oldCWD;
            DLog(@"pwd was empty. Use oldCWD of %@", pwd);
        } else {
            pwd = NSHomeDirectory();
            DLog(@"pwd was empty. Use home directory of %@", pwd);
        }
    }
    _workingDirectory = [pwd copy];
    _environment = [self.environment ?: @{} dictionaryBySettingObject:_workingDirectory
                                                               forKey:@"PWD"];
}

@end

@interface iTermSessionFactory()<iTermSessionAttachOrLaunchRequestDelegate>
@end

@implementation iTermSessionFactory {
    iTermParameterPanelWindowController *_parameterPanelWindowController;
}

#pragma mark - API

// Allocate a new session and assign it a bookmark.
- (PTYSession *)newSessionWithProfile:(Profile *)profile
                               parent:(nullable PTYSession *)parent {
    assert(profile);
    PTYSession *aSession;

    // Initialize a new session
    aSession = [[PTYSession alloc] initSynthetic:NO];

    [[aSession screen] setUnlimitedScrollback:[profile[KEY_UNLIMITED_SCROLLBACK] boolValue]];
    [[aSession screen] setMaxScrollbackLines:[profile[KEY_SCROLLBACK_LINES] intValue]];

    // set our preferences
    [aSession setProfile:profile];
    if (parent) {
        [aSession setParentScope:parent.variablesScope];
    }
    return aSession;
}

- (void)attachOrLaunchWithRequest:(iTermSessionAttachOrLaunchRequest *)request {
    request.delegate = self;
    DLog(@"attachOrLaunchWithRequest:%@", request);
    [request realizeWithCompletion:^(BOOL realized) {
        if (!realized) {
            return;
        }
        [self handleRealizedRequest:request
                         completion:^(BOOL ok) {
            [self requestDidComplete:request ok:ok];
        }];
    }];
}

#pragma mark - Private

- (void)handleRealizedRequest:(iTermSessionAttachOrLaunchRequest *)request
                   completion:(void (^)(BOOL))completion {
    DLog(@"handleRealizedRequest:%@", request);

    if (request.hasServerConnection) {
        // Attach to running server, if possible.
        assert([iTermAdvancedSettingsModel runJobsInServers]);
        [request.session attachToServer:request.xx_serverConnection completion:^{
            if (completion) {
                completion(YES);
            }
        }];
        return;
    }

    // Fork & exec
    [self startProgramForRequest:request completion:completion];
}

- (void)requestDidComplete:(iTermSessionAttachOrLaunchRequest *)request
                        ok:(BOOL)ok {
    DLog(@"factory completion wrapper starting");
    [request.session didFinishInitialization];
    DLog(@"factory did finish initialization");
    if (request.completion) {
        request.completion(request.session, ok);
    }
}

// Execute the given program and set the window title if it is uninitialized.
- (void)startProgramForRequest:(iTermSessionAttachOrLaunchRequest *)request
                    completion:(void (^)(BOOL))completion {
    [request.session startProgram:request.computedCommand
                      environment:request.environment
                      customShell:request.customShell
                           isUTF8:request.isUTF8
                    substitutions:request.substitutions
                      arrangement:request.arrangementName
                       completion:^(BOOL ok) {
        [request.windowController setWindowTitle];
        if (completion) {
            completion(ok);
        }
    }];
    if ([[[request.windowController window] title] isEqualToString:@"Window"]) {
        [request.windowController setWindowTitle];
    }
}

#pragma mark - iTermSessionAttachOrLaunchRequestDelegate

- (nullable NSString *)attachOrLaunchRequest:(iTermSessionAttachOrLaunchRequest *)request
                          promptForParameter:(NSString *)name
                           promptingDisabled:(BOOL)promptingDisabled
                                    inWindow:(nonnull NSWindow *)window {
    if (promptingDisabled) {
        return @"";
    }
    // Make the name pretty.
    name = [name stringByReplacingOccurrencesOfString:@"$$" withString:@""];
    name = [name stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    name = [name lowercaseString];
    if (name.length) {
        NSString *firstLetter = [name substringWithRange:NSMakeRange(0, 1)];
        NSString *lastLetters = [name substringFromIndex:1];
        name = [[firstLetter uppercaseString] stringByAppendingString:lastLetters];
    }
    _parameterPanelWindowController = [[iTermParameterPanelWindowController alloc] initWithWindowNibName:@"iTermParameterPanelWindowController"];
    [_parameterPanelWindowController window];
    [_parameterPanelWindowController.parameterName setStringValue:[NSString stringWithFormat:@"“%@”:", name]];
    [_parameterPanelWindowController.parameterValue setStringValue:@""];

    [window beginSheet:_parameterPanelWindowController.window completionHandler:nil];

    [NSApp runModalForWindow:_parameterPanelWindowController.window];

    [window endSheet:_parameterPanelWindowController.window];

    [_parameterPanelWindowController.window orderOut:self];

    if (_parameterPanelWindowController.canceled) {
        return nil;
    } else {
        return [_parameterPanelWindowController.parameterValue.stringValue copy];
    }
}

@end

NS_ASSUME_NONNULL_END
