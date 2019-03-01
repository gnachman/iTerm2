//
//  iTermStatusBarRPCProvidedTextComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/10/18.
//

#import "iTermStatusBarRPCProvidedTextComponent.h"

#import "DebugLogging.h"
#import "iTermAPIHelper.h"
#import "iTermExpressionParser.h"
#import "iTermAPIScriptLauncher.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermScriptFunctionCall.h"
#import "iTermScriptHistory.h"
#import "iTermScriptsMenuController.h"
#import "iTermStatusBarComponentKnob.h"
#import "iTermVariableScope.h"
#import "iTermVariableReference.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const iTermStatusBarRPCRegistrationRequestKey = @"registration request";

@interface ITMRPCRegistrationRequest(StatusBar)
@property (nonatomic, readonly) NSDictionary *statusBarConfiguration;
- (instancetype)latestStatusBarRequest;
@end

@implementation ITMRPCRegistrationRequest(StatusBar)

- (NSDictionary *)statusBarConfiguration {
    return @{ iTermStatusBarRPCRegistrationRequestKey: self.data,
              iTermStatusBarComponentConfigurationKeyKnobValues: @{} };
}

- (instancetype)latestStatusBarRequest {
    return [iTermAPIHelper registrationRequestForStatusBarComponentWithUniqueIdentifier:self.statusBarComponentAttributes.uniqueIdentifier] ?: self;
}

@end

@implementation iTermStatusBarRPCComponentFactory {
    ITMRPCRegistrationRequest *_savedRegistrationRequest;
    // NOTE: If mutable state is added, change copyWithZone:
}

- (instancetype)initWithRegistrationRequest:(ITMRPCRegistrationRequest *)registrationRequest {
    self = [super init];
    if (self) {
        _savedRegistrationRequest = registrationRequest;
   }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {
        NSData *data = [aDecoder decodeObjectOfClass:[NSData class] forKey:@"registrationRequest"];
        if (!data) {
            return nil;
        }
        _savedRegistrationRequest = [[ITMRPCRegistrationRequest alloc] initWithData:data error:nil];
        if (!_savedRegistrationRequest) {
            return nil;
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_savedRegistrationRequest.data forKey:@"registrationRequest"];
}

- (NSString *)componentDescription {
    return _savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.shortDescription;
}

- (nonnull id)copyWithZone:(nullable NSZone *)zone {
    return self;
}

- (NSDictionary *)defaultKnobs {
    NSMutableDictionary *knobs = [NSMutableDictionary dictionary];
    [_savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.knobsArray enumerateObjectsUsingBlock:^(ITMRPCRegistrationRequest_StatusBarComponentAttributes_Knob * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        id value = [NSJSONSerialization it_objectForJsonString:obj.jsonDefaultValue];
        if (value) {
            knobs[obj.key] = value;
        }
    }];
    return [knobs copy];
}

- (id<iTermStatusBarComponent>)newComponentWithKnobs:(NSDictionary *)knobs
                                     layoutAlgorithm:(iTermStatusBarLayoutAlgorithmSetting)layoutAlgorithm
                                               scope:(iTermVariableScope *)scope {
    return [[iTermStatusBarRPCProvidedTextComponent alloc] initWithRegistrationRequest:_savedRegistrationRequest.latestStatusBarRequest
                                                                                 scope:scope
                                                                                 knobs:knobs];
}

@end

@implementation iTermStatusBarRPCProvidedTextComponent {
    ITMRPCRegistrationRequest *_savedRegistrationRequest;
    NSArray<NSString *> *_variants;
    NSArray<iTermVariableReference *> *_dependencies;
    NSMutableSet<NSString *> *_missingFunctions;
    NSString *_errorMessage;  // Nil if the last evaluation was successful.
    NSDate *_dateOfLaunchToFix;
    NSString *_fullPath;
}

- (instancetype)initWithRegistrationRequest:(ITMRPCRegistrationRequest *)registrationRequest
                                      scope:(iTermVariableScope *)scope
                                      knobs:(NSDictionary *)knobs {
    return [self initWithConfiguration:@{ iTermStatusBarRPCRegistrationRequestKey: registrationRequest.data,
                                          iTermStatusBarComponentConfigurationKeyKnobValues: knobs }
                                 scope:scope];
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)realScope {
    NSData *data = configuration[iTermStatusBarRPCRegistrationRequestKey];;
    ITMRPCRegistrationRequest *registrationRequest = [[ITMRPCRegistrationRequest alloc] initWithData:data
                                                                                               error:nil];
    if (!registrationRequest) {
        return nil;
    }
    self = [super initWithConfiguration:configuration scope:realScope];
    if (self) {
        _savedRegistrationRequest = registrationRequest;
        iTermVariableRecordingScope *scope = [[iTermVariableRecordingScope alloc] initWithScope:self.scope];
        scope.neverReturnNil = YES;
        [iTermScriptFunctionCall callFunction:self.invocation
                                      timeout:0
                                        scope:scope
                                   completion:^(id value, NSError *error, NSSet<NSString *> *missingFunctions) {}];
        _dependencies = [scope recordedReferences];
        __weak __typeof(self) weakSelf = self;
        [_dependencies enumerateObjectsUsingBlock:^(iTermVariableReference * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            obj.onChangeBlock = ^{
                [weakSelf updateWithKnobValues:weakSelf.configuration[iTermStatusBarComponentConfigurationKeyKnobValues]];
            };
        }];
        [self updateWithKnobValues:self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues]];
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

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSString *)invocation {
    NSArray<ITMRPCRegistrationRequest_RPCArgument *> *defaults = _savedRegistrationRequest.latestStatusBarRequest.defaultsArray ?: @[];
    ITMRPCRegistrationRequest_RPCArgument *knobs = [[ITMRPCRegistrationRequest_RPCArgument alloc] init];
    knobs.name = @"knobs";
    knobs.path = @"__knobs";
    return [iTermAPIHelper invocationWithName:_savedRegistrationRequest.latestStatusBarRequest.name
                                     defaults:[defaults arrayByAddingObject:knobs]];
}

- (NSString *)statusBarComponentIdentifier {
    // Old (prerelease) ones did not have a unique identifier so assign one to prevent disaster.
    return _savedRegistrationRequest.statusBarComponentAttributes.uniqueIdentifier ?: [[NSUUID UUID] UUIDString];
}

- (NSTextField *)newTextField {
    NSTextField *textField = [super newTextField];
    NSClickGestureRecognizer *recognizer = [[NSClickGestureRecognizer alloc] init];
    recognizer.buttonMask = 1;
    recognizer.numberOfClicksRequired = 1;
    recognizer.target = self;
    recognizer.action = @selector(onClick:);
    [textField addGestureRecognizer:recognizer];
    return textField;
}

- (id<iTermStatusBarComponentFactory>)statusBarComponentFactory {
    return [[iTermStatusBarRPCComponentFactory alloc] initWithRegistrationRequest:_savedRegistrationRequest.latestStatusBarRequest];
}

- (NSString *)statusBarComponentShortDescription {
    return _savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.shortDescription;
}

- (NSString *)statusBarComponentDetailedDescription {
    return _savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.detailedDescription;
}

- (void)statusBarComponentUpdate {
    [self updateWithKnobValues:self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues]];
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

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    NSArray<iTermStatusBarComponentKnob *> *knobs;
    knobs = [_savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.knobsArray mapWithBlock:^id(ITMRPCRegistrationRequest_StatusBarComponentAttributes_Knob *descriptor) {
        return [[iTermStatusBarComponentKnob alloc] initWithLabelText:descriptor.name
                                                                 type:[self knobTypeFromDescriptorType:descriptor.type]
                                                          placeholder:descriptor.hasPlaceholder ? descriptor.placeholder : nil
                                                         defaultValue:descriptor.hasJsonDefaultValue ? [NSJSONSerialization it_objectForJsonString:descriptor.jsonDefaultValue] : nil
                                                                  key:descriptor.key];
    }] ?: @[];
    return [knobs arrayByAddingObjectsFromArray:[super statusBarComponentKnobs]];
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return _savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.exemplar ?: @"";
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (nullable NSArray<NSString *> *)stringVariants {
    return _variants ?: @[ @"" ];
}

- (void)updateWithKnobValues:(NSDictionary<NSString *, id> *)knobValues {
    __weak __typeof(self) weakSelf = self;
    iTermVariableScope *scope = [self.scope copy];
    if (!scope) {
        // This happens in the setup UI because the component is not attached to a real session. To
        // avoid spurious errors, do not actually evaluate the invocation.
        return;
    }
    // Create a temporary frame to shadow __knobs in the scope. This avoids mutating a scope we don't own.
    iTermVariables *variables = [[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextNone
                                                                  owner:self];
    [scope addVariables:variables toScopeNamed:nil];
    NSDictionary *knobsDict = weakSelf.configuration[iTermStatusBarComponentConfigurationKeyKnobValues] ?: @{};
    NSString *jsonKnobs = [NSJSONSerialization it_jsonStringForObject:knobsDict];
    [scope setValue:jsonKnobs forVariableNamed:@"__knobs"];
    [iTermScriptFunctionCall callFunction:self.invocation
                                  timeout:_savedRegistrationRequest.latestStatusBarRequest.timeout ?: [[NSDate distantFuture] timeIntervalSinceNow]
                                    scope:scope
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
                                    window:self.textField.window] == kiTermWarningSelection0) {
        [menuController moveScriptToAutoLaunch:_fullPath];
    }
}

- (void)handleSuccessfulEvaluationWithValue:(id)value {
    // Dispatch async so the user can see that it fixed it.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self maybeOfferToMoveScriptToAutoLaunch];
    });
    NSString *stringValue = [NSString castFrom:value];
    NSArray *arrayValue = [NSArray castFrom:value];
    _errorMessage = nil;
    if (stringValue) {
        _variants = @[ stringValue ];
    } else if ([arrayValue allWithBlock:^BOOL(id anObject) {
        return [anObject isKindOfClass:[NSString class]];
    }]) {
        _variants = arrayValue;
    } else {
        _errorMessage = [NSString stringWithFormat:@"Return value from %@ invalid.\n\nIt should have returned a string or a list of strings.\n\nInstead, it returned:\n\n%@", self.invocation, value];
        [[iTermAPIHelper sharedInstance] logToConnectionHostingFunctionWithSignature:_savedRegistrationRequest.latestStatusBarRequest.it_stringRepresentation
                                                                              string:_errorMessage];
        _variants = @[ @"🐞" ];
    }
    [self updateTextFieldIfNeeded];
}

- (void)handleEvaluationError:(NSError *)error
             missingFunctions:(NSSet<NSString *> *)missingFunctions {
    _errorMessage = [NSString stringWithFormat:@"Status bar component “%@” (%@) failed.\n\nThis function call had an error:\n\n%@\n\nThe error was:\n\n%@\n\n%@",
                     _savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.shortDescription,
                     _savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.uniqueIdentifier,
                     self.invocation,
                     error.localizedDescription,
                     error.localizedFailureReason ? [@"\n\n" stringByAppendingString:error.localizedFailureReason] : @""];
    [[iTermAPIHelper sharedInstance] logToConnectionHostingFunctionWithSignature:_savedRegistrationRequest.latestStatusBarRequest.it_stringRepresentation
                                                                          string:_errorMessage];
    _variants = @[ @"🐞" ];
    _missingFunctions = [missingFunctions mutableCopy];
    [self updateTextFieldIfNeeded];
}

- (void)statusBarComponentSetKnobValues:(NSDictionary *)knobValues {
    [self updateWithKnobValues:knobValues];
    [super statusBarComponentSetKnobValues:knobValues];
}

- (void)didRegisterStatusBarComponent:(NSNotification *)notification {
    if (![notification.object isEqual:_savedRegistrationRequest.statusBarComponentAttributes.uniqueIdentifier]) {
        return;
    }
    [_missingFunctions removeAllObjects];
    [self statusBarComponentUpdate];
}

- (void)registeredFunctionsDidChange:(NSNotification *)notification {
    NSArray<NSString *> *registered = [_missingFunctions.allObjects filteredArrayUsingBlock:^BOOL(NSString *signature) {
        return [[iTermAPIHelper sharedInstance] haveRegisteredFunctionWithSignature:signature];
    }];
    if (!registered.count) {
        return;
    }
    [_missingFunctions minusSet:[NSSet setWithArray:registered]];
    [self updateWithKnobValues:self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues]];
}

- (NSTimeInterval)statusBarComponentUpdateCadence {
    if (_savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.hasUpdateCadence) {
        return _savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.updateCadence;
    } else {
        return INFINITY;
    }
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
        warning.window = self.textField.window;
        [warning runModal];
        return;
    }
    NSString *sessionId = [self.scope valueForVariableName:iTermVariableKeySessionID];
    NSString *identifier = [[self.statusBarComponentIdentifier stringByReplacingOccurrencesOfString:@"." withString:@"_"] stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
    NSString *func = [NSString stringWithFormat:@"__%@__on_click(session_id: \"%@\")", identifier, sessionId];
    [iTermScriptFunctionCall callFunction:func
                                  timeout:30
                                    scope:self.scope
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

@end

NS_ASSUME_NONNULL_END
