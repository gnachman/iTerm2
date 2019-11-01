//
//  iTermStatusBarRPCProvidedComponentHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/3/19.
//

#import "iTermStatusBarRPCProvidedComponentHelper.h"
#import "iTermStatusBarComponent.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"

#import "iTermAPIHelper.h"

NSString *const iTermStatusBarRPCRegistrationRequestKey = @"registration request";

@implementation ITMRPCRegistrationRequest(StatusBar)

- (NSDictionary *)statusBarConfiguration {
    return @{ iTermStatusBarRPCRegistrationRequestKey: self.data,
              iTermStatusBarComponentConfigurationKeyKnobValues: @{} };
}

- (instancetype)latestStatusBarRequest {
    return [iTermAPIHelper registrationRequestForStatusBarComponentWithUniqueIdentifier:self.statusBarComponentAttributes.uniqueIdentifier] ?: self;
}

@end

@implementation iTermStatusBarRPCProvidedComponentHelper {
    ITMRPCRegistrationRequest *_savedRegistrationRequest;
    NSArray<iTermVariableReference *> *_dependencies;
    NSMutableSet<NSString *> *_missingFunctions;
    NSDate *_dateOfLaunchToFix;
    NSString *_fullPath;
    BOOL _computedIcon;
    NSImage *_icon;
    void (^_evalBlock)(id _Nullable, NSError * _Nullable, NSSet<NSString *> * _Nullable);
    void (^_reloadBlock)(void);
    void (^_updateBlock)(void);
    NSWindow *(^_windowProvider)(void);
    iTermVariableScope *_scope;
    NSDictionary<iTermStatusBarComponentConfigurationKey,id> *_configuration;
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)realScope
                          updateBlock:(void (^)(void))updateBlock
                          reloadBlock:(void (^)(void))reloadBlock
                            evalBlock:(void (^)(id _Nullable, NSError * _Nullable, NSSet<NSString *> * _Nullable))evalBlock
                       windowProvider:(NSWindow *(^)(void))windowProvider {
    NSData *data = configuration[iTermStatusBarRPCRegistrationRequestKey];
    ITMRPCRegistrationRequest *registrationRequest = [[ITMRPCRegistrationRequest alloc] initWithData:data
                                                                                               error:nil];
    if (!registrationRequest) {
        return nil;
    }
    self = [super init];
    if (self) {
        _configuration = configuration;
        _scope = realScope;
        _evalBlock = [evalBlock copy];
        _reloadBlock = [reloadBlock copy];
        _windowProvider = [windowProvider copy];
        _updateBlock = [updateBlock copy];
        _savedRegistrationRequest = [registrationRequest copy];
        iTermVariableRecordingScope *scope = [[iTermVariableRecordingScope alloc] initWithScope:realScope];
        scope.neverReturnNil = YES;
        [iTermScriptFunctionCall callFunction:self.invocation
                                      timeout:0
                                        scope:scope
                                   retainSelf:YES
                                   completion:^(id value, NSError *error, NSSet<NSString *> *missingFunctions) {}];
        _dependencies = [scope recordedReferences];
        [_dependencies enumerateObjectsUsingBlock:^(iTermVariableReference * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            obj.onChangeBlock = ^{
                updateBlock();
            };
        }];
        updateBlock();
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(registeredFunctionsDidChange:)
                                                     name:iTermAPIRegisteredFunctionsDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didRegisterStatusBarComponent:)
                                                     name:iTermAPIDidRegisterStatusBarComponentNotification
                                                   object:nil];
    }
    return self;
}

- (NSString *)identifier {
    return _savedRegistrationRequest.statusBarComponentAttributes.uniqueIdentifier ?: [[NSUUID UUID] UUIDString];
}

- (NSString *)shortDescription {
    return _savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.shortDescription;
}

- (NSString *)detailedDescriptor {
    return _savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.detailedDescription;
}

- (id<iTermStatusBarComponentFactory>)factory {
    return [[iTermStatusBarRPCComponentFactory alloc] initWithRegistrationRequest:_savedRegistrationRequest.latestStatusBarRequest];
}

- (nullable NSImage *)icon {
    if (_savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.iconsArray.count == 0) {
        return nil;
    }
    if (_computedIcon) {
        return _icon;
    }
    _computedIcon = YES;
    __block NSSize sizeInPoints = NSZeroSize;
    NSArray<NSBitmapImageRep *> *reps = [_savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.iconsArray mapWithBlock:^id(ITMRPCRegistrationRequest_StatusBarComponentAttributes_Icon *proto) {
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:proto.data_p];
        if (!rep) {
            return nil;
        }
        if (proto.scale <= 0) {
            return nil;
        }
        if (NSEqualSizes(NSZeroSize, sizeInPoints)) {
            sizeInPoints = rep.size;
            sizeInPoints.width = round(sizeInPoints.width / proto.scale);
            sizeInPoints.height = round(sizeInPoints.height / proto.scale);
        }
        return rep;
    }];
    if (sizeInPoints.width <= 0 || sizeInPoints.height <= 0) {
        return nil;
    }
    NSImage *image = [[NSImage alloc] initWithSize:sizeInPoints];
    for (NSBitmapImageRep *rep in reps) {
        [image addRepresentation:rep];
    }
    _icon = image;
    return _icon;
}

- (iTermStatusBarComponentKnobType)knobTypeFromDescriptorType:(ITMRPCRegistrationRequest_StatusBarComponentAttributes_Knob_Type)type {
    switch (type) {
        case ITMRPCRegistrationRequest_StatusBarComponentAttributes_Knob_Type_Color:
            return iTermStatusBarComponentKnobTypeColor;
        case ITMRPCRegistrationRequest_StatusBarComponentAttributes_Knob_Type_String:
            return iTermStatusBarComponentKnobTypeText;
        case ITMRPCRegistrationRequest_StatusBarComponentAttributes_Knob_Type_Checkbox:
            return iTermStatusBarComponentKnobTypeCheckbox;
        case ITMRPCRegistrationRequest_StatusBarComponentAttributes_Knob_Type_PositiveFloatingPoint:
            return iTermStatusBarComponentKnobTypeDouble;
    }
    return iTermStatusBarComponentKnobTypeText;
}

- (NSArray<iTermStatusBarComponentKnob *> *)knobsWith:(NSArray *)superKnobs {
    NSArray<iTermStatusBarComponentKnob *> *knobs;
    knobs = [_savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.knobsArray mapWithBlock:^id(ITMRPCRegistrationRequest_StatusBarComponentAttributes_Knob *descriptor) {
        return [[iTermStatusBarComponentKnob alloc] initWithLabelText:descriptor.name
                                                                 type:[self knobTypeFromDescriptorType:descriptor.type]
                                                          placeholder:descriptor.hasPlaceholder ? descriptor.placeholder : nil
                                                         defaultValue:descriptor.hasJsonDefaultValue ? [NSJSONSerialization it_objectForJsonString:descriptor.jsonDefaultValue] : nil
                                                                  key:descriptor.key];
    }] ?: @[];
    return [knobs arrayByAddingObjectsFromArray:superKnobs];
}

- (id)exemplarWithBackgroundColor:(NSColor *)backgroundColor
                        textColor:(NSColor *)textColor {
    return _savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.exemplar ?: @"";
}

- (void)updateWithKnobValues:(NSDictionary<NSString *, id> *)knobValues {
    __weak __typeof(self) weakSelf = self;
    iTermVariableScope *scope = [_scope copy];
    if (!scope) {
        // This happens in the setup UI because the component is not attached to a real session. To
        // avoid spurious errors, do not actually evaluate the invocation.
        return;
    }
    // Create a temporary frame to shadow __knobs in the scope. This avoids mutating a scope we don't own.
    iTermVariables *variables = [[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextNone
                                                                  owner:self];
    [scope addVariables:variables toScopeNamed:nil];
    NSDictionary *knobsDict = _configuration[iTermStatusBarComponentConfigurationKeyKnobValues] ?: @{};
    NSString *jsonKnobs = [NSJSONSerialization it_jsonStringForObject:knobsDict];
    [scope setValue:jsonKnobs forVariableNamed:@"__knobs"];
    [iTermScriptFunctionCall callFunction:self.invocation
                                  timeout:_savedRegistrationRequest.latestStatusBarRequest.timeout ?: [[NSDate distantFuture] timeIntervalSinceNow]
                                    scope:scope
                               retainSelf:YES
                               completion:
     ^(id value, NSError *error, NSSet<NSString *> *missingFunctions) {
         DLog(@"evaluation of %@ completed with value %@ error %@", self.invocation, value, error);
         if (error) {
             [weakSelf handleEvaluationError:error missingFunctions:missingFunctions];
             return;
         }
         [weakSelf handleSuccessfulEvaluationWithValue:value];
     }];
}

- (void)handleEvaluationError:(NSError *)error
             missingFunctions:(NSSet<NSString *> *)missingFunctions {
    _missingFunctions = [missingFunctions mutableCopy];
    self.errorMessage = [NSString stringWithFormat:@"Status bar component “%@” (%@) failed.\n\nThis function call had an error:\n\n%@\n\nThe error was:\n\n%@\n\n%@",
                         _savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.shortDescription,
                         _savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.uniqueIdentifier,
                         self.invocation,
                         error.localizedDescription,
                         error.localizedFailureReason ? [@"\n\n" stringByAppendingString:error.localizedFailureReason] : @""];
    [[iTermAPIHelper sharedInstance] logToConnectionHostingFunctionWithSignature:_savedRegistrationRequest.latestStatusBarRequest.it_stringRepresentation
                                                                          string:_errorMessage];
    _evalBlock(nil, error, missingFunctions);
}

- (void)maybeOfferToMoveScriptToAutoLaunch {
    if (-[_dateOfLaunchToFix timeIntervalSinceNow] >= 1) {
        return;
    }
    iTermScriptsMenuController *menuController = [[[iTermApplication sharedApplication] delegate] scriptsMenuController];
    if ([menuController scriptShouldAutoLaunchWithFullPath:_fullPath]) {
        return;
    }
    if (![menuController couldMoveScriptToAutoLaunch:_fullPath]) {
        return;
    }

    if ([iTermWarning showWarningWithTitle:@"This will move the script into the AutoLaunch folder."
                                   actions:@[ @"OK", @"Cancel" ]
                                 accessory:nil
                                identifier:[NSString stringWithFormat:@"NoSyncAutoLaunchScript_%@", _fullPath]
                               silenceable:kiTermWarningTypePermanentlySilenceable
                                   heading:@"Always launch this script when iTerm2 starts?"
                                    window:_windowProvider()] == kiTermWarningSelection0) {
        [menuController moveScriptToAutoLaunch:_fullPath];
    }
}

- (void)logInvalidValue:(NSString *)message {
    self.errorMessage = message;
    [[iTermAPIHelper sharedInstance] logToConnectionHostingFunctionWithSignature:_savedRegistrationRequest.latestStatusBarRequest.it_stringRepresentation
                                                                          string:message];
}

- (NSString *)invocation {
    NSArray<ITMRPCRegistrationRequest_RPCArgument *> *defaults = _savedRegistrationRequest.latestStatusBarRequest.defaultsArray ?: @[];
    ITMRPCRegistrationRequest_RPCArgument *knobs = [[ITMRPCRegistrationRequest_RPCArgument alloc] init];
    knobs.name = @"knobs";
    knobs.path = @"__knobs";
    return [iTermAPIHelper invocationWithName:_savedRegistrationRequest.latestStatusBarRequest.name
                                     defaults:[defaults arrayByAddingObject:knobs]];
}

- (void)handleSuccessfulEvaluationWithValue:(id)value {
    // Dispatch async so the user can see that it fixed it.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self maybeOfferToMoveScriptToAutoLaunch];
    });
    _evalBlock(value, nil, nil);
}

- (void)didRegisterStatusBarComponent:(NSNotification *)notification {
    if (![notification.object isEqual:_savedRegistrationRequest.statusBarComponentAttributes.uniqueIdentifier]) {
        return;
    }
    [_missingFunctions removeAllObjects];
    _reloadBlock();
}

- (void)registeredFunctionsDidChange:(NSNotification *)notification {
    NSArray<NSString *> *registered = [_missingFunctions.allObjects filteredArrayUsingBlock:^BOOL(NSString *signature) {
        return [[iTermAPIHelper sharedInstance] haveRegisteredFunctionWithSignature:signature];
    }];
    if (!registered.count) {
        return;
    }
    [_missingFunctions minusSet:[NSSet setWithArray:registered]];
    _updateBlock();
}

- (NSTimeInterval)cadence {
    if (_savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.hasUpdateCadence) {
        return _savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.updateCadence;
    } else {
        return INFINITY;
    }
}

- (nullable NSString *)fullPathOfScript {
    if (!_savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.uniqueIdentifier) {
        return nil;
    }
    return [iTermAPIHelper nameOfScriptVendingStatusBarComponentWithUniqueIdentifier:_savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.uniqueIdentifier];
}

- (void)launchScript {
    if (!_savedRegistrationRequest.statusBarComponentAttributes.uniqueIdentifier) {
        return;
    }
    NSString *fullPath = [self fullPathOfScript];
    if (!fullPath) {
        return;
    }
    iTermScriptsMenuController *menuController = [[[iTermApplication sharedApplication] delegate] scriptsMenuController];
    [menuController launchScriptWithAbsolutePath:fullPath explicitUserAction:YES];
    _dateOfLaunchToFix = [NSDate date];
    _fullPath = [fullPath copy];
}

- (void)revealInFinder {
    NSString *fullPath = [self fullPathOfScript];
    if (!fullPath) {
        return;
    }
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:fullPath] ]];
}

- (BOOL)scriptIsRunning:(NSString *)fullPath {
    iTermScriptHistoryEntry *entry = [[iTermScriptHistory sharedInstance] runningEntryWithFullPath:fullPath];
    if (!entry) {
        return NO;
    }
    return entry.isRunning;
}

- (BOOL)scriptIsNotRunningButCouldBeLaunched {
    NSString *fullPath = [self fullPathOfScript];
    if (!fullPath) {
        return NO;
    }
    if ([self scriptIsRunning:fullPath]) {
        return NO;
    }
    return [[[[iTermApplication sharedApplication] delegate] scriptsMenuController] couldLaunchScriptWithAbsolutePath:fullPath];
}

- (void)onClick:(id)sender {
    if (_errorMessage) {
        iTermWarning *warning = [[iTermWarning alloc] init];
        warning.title = _errorMessage;
        warning.heading = @"Status Bar Component Problem";
        NSArray *actions = @[ [iTermWarningAction warningActionWithLabel:@"OK" block:nil] ];
        if ([self scriptIsNotRunningButCouldBeLaunched]) {
            iTermWarningAction *launch = [iTermWarningAction warningActionWithLabel:@"Launch Script" block:^(iTermWarningSelection selection) {
                [self launchScript];
            }];
            iTermWarningAction *reveal = [iTermWarningAction warningActionWithLabel:@"Reveal in Finder" block:^(iTermWarningSelection selection) {
                [self revealInFinder];
            }];
            actions = [actions arrayByAddingObjectsFromArray:@[ launch, reveal ]];

            warning.title = [NSString stringWithFormat:@"%@It looks like the script is not running. Launching it might fix the problem.", _errorMessage];
        }
        warning.warningActions = actions;
        warning.warningType = kiTermWarningTypePersistent;
        warning.heading = @"Status Bar Script Error";
        warning.window = _windowProvider();
        [warning runModal];
        return;
    }
    NSString *sessionId = [_scope valueForVariableName:iTermVariableKeySessionID];
    NSString *identifier = [[self.identifier stringByReplacingOccurrencesOfString:@"." withString:@"_"] stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
    NSString *func = [NSString stringWithFormat:@"__%@__on_click(session_id: \"%@\")", identifier, sessionId];
    [iTermScriptFunctionCall callFunction:func
                                  timeout:30
                                    scope:_scope
                               retainSelf:YES
                               completion:^(id result, NSError *error, NSSet<NSString *> *mutations) {
                                   if (error) {
                                       NSString *message = [NSString stringWithFormat:@"Error in onclick handler: %@\n%@", error.localizedDescription, error.localizedFailureReason];
                                       [[iTermScriptHistoryEntry globalEntry] addOutput:message];
                                   }
                               }];
}

- (void)itermWebViewJavascriptError:(NSString *)errorText {
    NSError *error = nil;
    NSString *signature = [iTermExpressionParser signatureForFunctionCallInvocation:self.invocation
                                                                              error:&error];
    if (!signature && error) {
        signature = error.localizedDescription;
    }
    [[iTermAPIHelper sharedInstance] logToConnectionHostingFunctionWithSignature:signature
                                                                          string:errorText];
    [[iTermAPIHelper sharedInstance] logToConnectionHostingFunctionWithSignature:signature
                                                                          string:@"Right-click in the webview and choose Inspect Element to open the Web Inspector."];
}

- (void)itermWebViewWillExecuteJavascript:(NSString *)javascript {
    NSError *error = nil;
    NSString *signature = [iTermExpressionParser signatureForFunctionCallInvocation:self.invocation
                                                                              error:&error];
    if (!signature && error) {
        signature = error.localizedDescription;
    }
    [[iTermAPIHelper sharedInstance] logToConnectionHostingFunctionWithSignature:signature
                                                                          string:[NSString stringWithFormat:@"Execute javascript: %@", javascript]];
}

#pragma mark - iTermObject

- (nullable iTermBuiltInFunctions *)objectMethodRegistry {
    return nil;
}

- (nullable iTermVariableScope *)objectScope {
    return nil;
}

@end
