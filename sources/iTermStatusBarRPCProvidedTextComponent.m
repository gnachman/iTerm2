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
#import "iTermObject.h"
#import "iTermScriptFunctionCall.h"
#import "iTermScriptHistory.h"
#import "iTermScriptsMenuController.h"
#import "iTermStatusBarComponentKnob.h"
#import "iTermVariableScope.h"
#import "iTermVariableReference.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSAttributedString+PSM.h"
#import "NSData+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const iTermStatusBarRPCRegistrationRequestKey_Deprecated = @"registration request";  // legacy, NSData value which cannot be JSON encoded for profile export or Python API
static NSString *const iTermStatusBarRPCRegistrationRequestV2Key = @"registration request v2";  // use this instead, has a base64-encoded string

@class iTermStatusBarRPCProvidedTextComponentCommon;

@protocol iTermStatusBarRPCProvidedTextComponent
- (iTermStatusBarRPCProvidedTextComponentCommon *)commonImplementation;
@end

@interface ITMRPCRegistrationRequest(StatusBar)
@property (nonatomic, readonly) NSDictionary *statusBarConfiguration;
- (instancetype)latestStatusBarRequest;
@end

@implementation ITMRPCRegistrationRequest(StatusBar)

- (NSDictionary *)statusBarConfiguration {
    return @{ iTermStatusBarRPCRegistrationRequestV2Key: [self.data base64EncodedStringWithOptions:0],
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

+ (BOOL)supportsSecureCoding {
    return YES;
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
                                               scope:(nullable iTermVariableScope *)scope {
    ITMRPCRegistrationRequest *request = _savedRegistrationRequest.latestStatusBarRequest;
    switch (request.statusBarComponentAttributes.format) {
        case ITMRPCRegistrationRequest_StatusBarComponentAttributes_Format_PlainText:
            return [[iTermStatusBarRPCProvidedTextComponent alloc] initWithRegistrationRequest:request
                                                                                         scope:scope
                                                                                         knobs:knobs];
        case ITMRPCRegistrationRequest_StatusBarComponentAttributes_Format_Html:
            return [[iTermStatusBarRPCProvidedAttributedTextComponent alloc] initWithRegistrationRequest:request
                                                                                                   scope:scope
                                                                                                   knobs:knobs];
    }
    return nil;
}

@end

@protocol iTermStatusBarRPCProvidedTextComponentCommonDelegate<NSObject>
@property(nonatomic, readonly) NSTextField *textField;
@property(nonatomic, readonly) iTermVariableScope *scope;
- (void)updateTextFieldIfNeeded;
@end

@interface iTermStatusBarRPCProvidedTextComponentCommon: NSObject<iTermObject>
@property(nonatomic, weak) id<iTermStatusBarRPCProvidedTextComponentCommonDelegate> delegate;
@property(nonatomic, copy) NSDictionary<iTermStatusBarComponentConfigurationKey,id> *configuration;
@end

@implementation iTermStatusBarRPCProvidedTextComponentCommon {
    ITMRPCRegistrationRequest *_savedRegistrationRequest;
    NSArray<NSString *> *_variants;
    NSArray<iTermVariableReference *> *_dependencies;
    NSMutableSet<NSString *> *_missingFunctions;
    NSString *_errorMessage;  // Nil if the last evaluation was successful.
    NSDate *_dateOfLaunchToFix;
    NSString *_fullPath;
    BOOL _computedIcon;
    NSImage *_icon;
}

- (instancetype)initWithRegistrationRequest:(ITMRPCRegistrationRequest *)registrationRequest
                                      scope:(iTermVariableScope *)scope
                                      knobs:(NSDictionary *)knobs {
    return [self initWithConfiguration:@{ iTermStatusBarRPCRegistrationRequestV2Key: [registrationRequest.data base64EncodedStringWithOptions:0],
                                          iTermStatusBarComponentConfigurationKeyKnobValues: knobs }
                                 scope:scope];
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)realScope {
    NSData *data = configuration[iTermStatusBarRPCRegistrationRequestKey_Deprecated];
    if (!data) {
        NSString *b64 = [NSString castFrom:configuration[iTermStatusBarRPCRegistrationRequestV2Key]];
        data = [NSData dataWithBase64EncodedString:b64];
    }
    ITMRPCRegistrationRequest *registrationRequest = [[ITMRPCRegistrationRequest alloc] initWithData:data
                                                                                               error:nil];
    if (!registrationRequest) {
        return nil;
    }
    self = [super init];
    if (self) {
        _savedRegistrationRequest = registrationRequest;
        _configuration = [configuration copy];
    }
    return self;
}

- (BOOL)isEqual:(id)other {
    if (![other isKindOfClass:[iTermStatusBarRPCProvidedTextComponentCommon class]]) {
        return NO;
    }
    iTermStatusBarRPCProvidedTextComponentCommon *rhs = other;
    return [NSObject object:_savedRegistrationRequest.statusBarComponentAttributes.uniqueIdentifier
            isEqualToObject:rhs->_savedRegistrationRequest.statusBarComponentAttributes.uniqueIdentifier];
}

- (void)finishInitialization {
    iTermVariableRecordingScope *scope = [[iTermVariableRecordingScope alloc] initWithScope:self.delegate.scope];
    scope.neverReturnNil = YES;
    [iTermScriptFunctionCall callFunction:self.invocation
                                  timeout:0
                                    scope:scope
                               retainSelf:YES
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

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSString *)invocation {
    NSArray<ITMRPCRegistrationRequest_RPCArgument *> *defaults = _savedRegistrationRequest.latestStatusBarRequest.defaultsArray ?: @[];
    ITMRPCRegistrationRequest_RPCArgument *knobs = [[ITMRPCRegistrationRequest_RPCArgument alloc] init];
    knobs.name = @"knobs";
    knobs.path = @"__knobs";
    return [iTermAPIHelper invocationWithFullyQualifiedName:_savedRegistrationRequest.latestStatusBarRequest.it_fullyQualifiedName
                                                   defaults:[defaults arrayByAddingObject:knobs]];
}

- (NSString *)statusBarComponentIdentifier {
    // Old (prerelease) ones did not have a unique identifier so assign one to prevent disaster.
    return _savedRegistrationRequest.statusBarComponentAttributes.uniqueIdentifier ?: [[NSUUID UUID] UUIDString];
}

- (void)initializeTextField:(NSTextField *)textField {
    NSClickGestureRecognizer *recognizer = [[NSClickGestureRecognizer alloc] init];
    recognizer.buttonMask = 1;
    recognizer.numberOfClicksRequired = 1;
    recognizer.target = self;
    recognizer.action = @selector(onClick:);
    [textField addGestureRecognizer:recognizer];
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

- (nullable NSImage *)statusBarComponentIcon {
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

- (NSArray<iTermStatusBarComponentKnob *> *)amendedStatusBarComponentKnobs:(NSArray<iTermStatusBarComponentKnob *> *)superKnobs {
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

- (BOOL)statusBarComponentIsEmpty {
    return _variants.count == 0 || [_variants allWithBlock:^BOOL(NSString *anObject) {
        return anObject.length == 0;
    }];
}

- (void)updateWithKnobValues:(NSDictionary<NSString *, id> *)knobValues {
    __weak __typeof(self) weakSelf = self;
    iTermVariableScope *scope = [self.delegate.scope copy];
    if (!scope) {
        // This happens in the setup UI because the component is not attached to a real session. To
        // avoid spurious errors, do not actually evaluate the invocation.
        return;
    }
    DLog(@"Update status bar component %@ instance %p for session %@\n%@",
         _savedRegistrationRequest.statusBarComponentAttributes.uniqueIdentifier,
         self,
         [scope valueForVariableName:iTermVariableKeySessionID],
         [NSThread callStackSymbols]);
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

- (void)maybeOfferToMoveScriptToAutoLaunch {
    if (-[_dateOfLaunchToFix timeIntervalSinceNow] >= 1) {
        return;
    }
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
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
                                    window:self.delegate.textField.window] == kiTermWarningSelection0) {
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
    [self.delegate updateTextFieldIfNeeded];
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
    [self.delegate updateTextFieldIfNeeded];
}

// Call super after this.
- (void)statusBarComponentSetKnobValues:(NSDictionary *)knobValues {
    [self updateWithKnobValues:knobValues];
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
    [menuController launchScriptWithAbsolutePath:fullPath arguments:@[] explicitUserAction:YES];
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
        warning.window = self.delegate.textField.window;
        [warning runModal];
        return;
    }
    NSString *sessionId = [self.delegate.scope valueForVariableName:iTermVariableKeySessionID];
    NSString *identifier = [[self.statusBarComponentIdentifier stringByReplacingOccurrencesOfString:@"." withString:@"_"] stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
    NSString *func = [NSString stringWithFormat:@"__%@__on_click(session_id: \"%@\")", identifier, sessionId];
    [iTermScriptFunctionCall callFunction:func
                                  timeout:30
                                    scope:self.delegate.scope
                               retainSelf:YES
                               completion:^(id result, NSError *error, NSSet<NSString *> *mutations) {
                                   if (error) {
                                       NSString *message = [NSString stringWithFormat:@"Error in onclick handler: %@\n%@", error.localizedDescription, error.localizedFailureReason];
                                       [[iTermScriptHistoryEntry globalEntry] addOutput:message
                                                                             completion:^{}];
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

@interface iTermStatusBarRPCProvidedTextComponent()<iTermObject, iTermStatusBarRPCProvidedTextComponentCommonDelegate, iTermStatusBarRPCProvidedTextComponent>
@end

@implementation iTermStatusBarRPCProvidedTextComponent {
    iTermStatusBarRPCProvidedTextComponentCommon *_common;
}

- (instancetype)initWithRegistrationRequest:(ITMRPCRegistrationRequest *)registrationRequest
                                      scope:(iTermVariableScope *)scope
                                      knobs:(NSDictionary *)knobs {
    return [self initWithConfiguration:@{ iTermStatusBarRPCRegistrationRequestV2Key: [registrationRequest.data base64EncodedStringWithOptions:0],
                                          iTermStatusBarComponentConfigurationKeyKnobValues: knobs }
                                 scope:scope];
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)realScope {
    iTermStatusBarRPCProvidedTextComponentCommon *common = [[iTermStatusBarRPCProvidedTextComponentCommon alloc] initWithConfiguration:configuration scope:realScope];
    if (!common) {
        return nil;
    }
    self = [super initWithConfiguration:configuration scope:realScope];
    common.delegate = self;
    if (self) {
        [common finishInitialization];
        _common = common;
    }
    return self;
}

- (NSString *)statusBarComponentIdentifier {
    return [_common statusBarComponentIdentifier];
}

- (NSTextField *)newTextField {
    NSTextField *textField = [super newTextField];
    [_common initializeTextField:textField];
    return textField;
}

- (id<iTermStatusBarComponentFactory>)statusBarComponentFactory {
    return [_common statusBarComponentFactory];
}

- (NSString *)statusBarComponentShortDescription {
    return [_common statusBarComponentShortDescription];
}

- (NSString *)statusBarComponentDetailedDescription {
    return [_common statusBarComponentDetailedDescription];
}

- (void)statusBarComponentUpdate {
    [_common statusBarComponentUpdate];
}

- (nullable NSImage *)statusBarComponentIcon {
    return [_common statusBarComponentIcon];
}

- (iTermStatusBarComponentKnobType)knobTypeFromDescriptorType:(ITMRPCRegistrationRequest_StatusBarComponentAttributes_Knob_Type)type {
    return [_common knobTypeFromDescriptorType:type];
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    return [_common amendedStatusBarComponentKnobs:[super statusBarComponentKnobs]];
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return [_common statusBarComponentExemplarWithBackgroundColor:backgroundColor textColor:textColor];
}

- (BOOL)statusBarComponentCanStretch {
    return [_common statusBarComponentCanStretch];
}

- (nullable NSArray<NSString *> *)stringVariants {
    return [_common stringVariants];
}

- (void)statusBarComponentSetKnobValues:(NSDictionary *)knobValues {
    [_common statusBarComponentSetKnobValues:knobValues];
    [super statusBarComponentSetKnobValues:knobValues];
}

- (NSTimeInterval)statusBarComponentUpdateCadence {
    return [_common statusBarComponentUpdateCadence];
}

- (void)itermWebViewJavascriptError:(NSString *)errorText {
    [_common itermWebViewJavascriptError:errorText];
}

- (void)itermWebViewWillExecuteJavascript:(NSString *)javascript {
    [_common itermWebViewWillExecuteJavascript:javascript];
}

- (BOOL)isEqualToComponentIgnoringConfiguration:(id<iTermStatusBarComponent>)component {
    if (![component conformsToProtocol:@protocol(iTermStatusBarRPCProvidedTextComponent)]) {
        return NO;
    }
    id<iTermStatusBarRPCProvidedTextComponent> other = (id)component;
    return [_common isEqualTo:other.commonImplementation];
}

#pragma mark - iTermObject

- (nullable iTermBuiltInFunctions *)objectMethodRegistry {
    return [_common objectMethodRegistry];
}

- (nullable iTermVariableScope *)objectScope {
    return [_common objectScope];
}

#pragma mark - iTermStatusBarRPCProvidedTextComponent

- (iTermStatusBarRPCProvidedTextComponentCommon *)commonImplementation {
    return _common;
}

@end

@interface iTermStatusBarRPCProvidedAttributedTextComponent()<iTermObject, iTermStatusBarRPCProvidedTextComponentCommonDelegate, iTermStatusBarRPCProvidedTextComponent>
@end

@implementation iTermStatusBarRPCProvidedAttributedTextComponent {
    iTermStatusBarRPCProvidedTextComponentCommon *_common;
}

- (instancetype)initWithRegistrationRequest:(ITMRPCRegistrationRequest *)registrationRequest
                                      scope:(iTermVariableScope *)scope
                                      knobs:(NSDictionary *)knobs {
    return [self initWithConfiguration:@{ iTermStatusBarRPCRegistrationRequestV2Key: [registrationRequest.data base64EncodedStringWithOptions:0],
                                          iTermStatusBarComponentConfigurationKeyKnobValues: knobs }
                                 scope:scope];
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)realScope {
    iTermStatusBarRPCProvidedTextComponentCommon *common = [[iTermStatusBarRPCProvidedTextComponentCommon alloc] initWithConfiguration:configuration scope:realScope];
    if (!common) {
        return nil;
    }
    self = [super initWithConfiguration:configuration scope:realScope];
    common.delegate = self;
    if (self) {
        [common finishInitialization];
        _common = common;
    }
    return self;
}

- (NSString *)statusBarComponentIdentifier {
    return [_common statusBarComponentIdentifier];
}

- (NSTextField *)newTextField {
    NSTextField *textField = [super newTextField];
    [_common initializeTextField:textField];
    return textField;
}

- (id<iTermStatusBarComponentFactory>)statusBarComponentFactory {
    return [_common statusBarComponentFactory];
}

- (NSString *)statusBarComponentShortDescription {
    return [_common statusBarComponentShortDescription];
}

- (NSString *)statusBarComponentDetailedDescription {
    return [_common statusBarComponentDetailedDescription];
}

- (void)statusBarComponentUpdate {
    [_common statusBarComponentUpdate];
}

- (nullable NSImage *)statusBarComponentIcon {
    return [_common statusBarComponentIcon];
}

- (iTermStatusBarComponentKnobType)knobTypeFromDescriptorType:(ITMRPCRegistrationRequest_StatusBarComponentAttributes_Knob_Type)type {
    return [_common knobTypeFromDescriptorType:type];
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    return [_common amendedStatusBarComponentKnobs:[super statusBarComponentKnobs]];
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return [_common statusBarComponentExemplarWithBackgroundColor:backgroundColor textColor:textColor];
}

- (BOOL)statusBarComponentCanStretch {
    return [_common statusBarComponentCanStretch];
}

- (NSArray<NSAttributedString *> *)attributedStringVariants {
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentNatural;
    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *attributes = @{ NSFontAttributeName: self.font,
                                  NSForegroundColorAttributeName: [NSColor textColor],
                                  NSParagraphStyleAttributeName: paragraphStyle };

    return [[_common stringVariants] mapWithBlock:^id(NSString *string) {
        return [NSAttributedString newAttributedStringWithHTML:string attributes:attributes];
    }];
}

- (void)statusBarComponentSetKnobValues:(NSDictionary *)knobValues {
    [_common statusBarComponentSetKnobValues:knobValues];
    [super statusBarComponentSetKnobValues:knobValues];
}

- (NSTimeInterval)statusBarComponentUpdateCadence {
    return [_common statusBarComponentUpdateCadence];
}

- (void)itermWebViewJavascriptError:(NSString *)errorText {
    [_common itermWebViewJavascriptError:errorText];
}

- (void)itermWebViewWillExecuteJavascript:(NSString *)javascript {
    [_common itermWebViewWillExecuteJavascript:javascript];
}

- (BOOL)isEqualToComponentIgnoringConfiguration:(id<iTermStatusBarComponent>)component {
    if (![component conformsToProtocol:@protocol(iTermStatusBarRPCProvidedTextComponent)]) {
        return NO;
    }
    id<iTermStatusBarRPCProvidedTextComponent> other = (id)component;
    return [_common isEqualTo:other.commonImplementation];
}

#pragma mark - iTermObject

- (nullable iTermBuiltInFunctions *)objectMethodRegistry {
    return [_common objectMethodRegistry];
}

- (nullable iTermVariableScope *)objectScope {
    return [_common objectScope];
}

#pragma mark - iTermStatusBarRPCProvidedTextComponent

- (iTermStatusBarRPCProvidedTextComponentCommon *)commonImplementation {
    return _common;
}

@end

NS_ASSUME_NONNULL_END
