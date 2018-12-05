//
//  iTermStatusBarRPCProvidedTextComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/10/18.
//

#import "iTermStatusBarRPCProvidedTextComponent.h"

#import "DebugLogging.h"
#import "iTermAPIHelper.h"
#import "iTermScriptFunctionCall.h"
#import "iTermScriptHistory.h"
#import "iTermStatusBarComponentKnob.h"
#import "iTermVariables.h"
#import "iTermVariableReference.h"
#import "NSArray+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const iTermStatusBarRPCRegistrationRequestKey = @"registration request";

@interface ITMRPCRegistrationRequest(StatusBar)
@property (nonatomic, readonly) NSDictionary *statusBarConfiguration;
@end

@implementation ITMRPCRegistrationRequest(StatusBar)

- (NSDictionary *)statusBarConfiguration {
    return @{ iTermStatusBarRPCRegistrationRequestKey: self.data,
              iTermStatusBarComponentConfigurationKeyKnobValues: @{} };
}

@end

@implementation iTermStatusBarRPCComponentFactory {
    ITMRPCRegistrationRequest *_registrationRequest;
    // NOTE: If mutable state is added, change copyWithZone:
}

- (instancetype)initWithRegistrationRequest:(ITMRPCRegistrationRequest *)registrationRequest {
    self = [super init];
    if (self) {
        _registrationRequest = registrationRequest;
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
        _registrationRequest = [[ITMRPCRegistrationRequest alloc] initWithData:data error:nil];
        if (!_registrationRequest) {
            return nil;
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_registrationRequest.data forKey:@"registrationRequest"];
}

- (NSString *)componentDescription {
    return _registrationRequest.statusBarComponentAttributes.shortDescription;
}

- (nonnull id)copyWithZone:(nullable NSZone *)zone {
    return self;
}

- (NSDictionary *)defaultKnobs {
    NSMutableDictionary *knobs = [NSMutableDictionary dictionary];
    [_registrationRequest.statusBarComponentAttributes.knobsArray enumerateObjectsUsingBlock:^(ITMRPCRegistrationRequest_StatusBarComponentAttributes_Knob * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        id value = [NSJSONSerialization it_objectForJsonString:obj.jsonDefaultValue];
        if (value) {
            knobs[obj.key] = obj.jsonDefaultValue;
        }
    }];
    return [knobs copy];
}

- (id<iTermStatusBarComponent>)newComponentWithKnobs:(NSDictionary *)knobs
                                               scope:(iTermVariableScope *)scope {
    return [[iTermStatusBarRPCProvidedTextComponent alloc] initWithRegistrationRequest:_registrationRequest
                                                                                 scope:scope
                                                                                 knobs:knobs];
}

@end

@implementation iTermStatusBarRPCProvidedTextComponent {
    ITMRPCRegistrationRequest *_registrationRequest;
    NSArray<NSString *> *_variants;
    NSArray<iTermVariableReference *> *_dependencies;
    NSMutableSet<NSString *> *_missingFunctions;
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
        _registrationRequest = registrationRequest;
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
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSString *)invocation {
    NSArray<ITMRPCRegistrationRequest_RPCArgument *> *defaults = _registrationRequest.defaultsArray ?: @[];
    ITMRPCRegistrationRequest_RPCArgument *knobs = [[ITMRPCRegistrationRequest_RPCArgument alloc] init];
    knobs.name = @"knobs";
    knobs.path = @"__knobs";
    return [iTermAPIHelper invocationWithName:_registrationRequest.name
                                     defaults:[defaults arrayByAddingObject:knobs]];
}

- (NSString *)statusBarComponentIdentifier {
    // Old (prerelease) ones did not have a unique identifier so assign one to prevent disaster.
    return _registrationRequest.statusBarComponentAttributes.uniqueIdentifier ?: [[NSUUID UUID] UUIDString];
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
    return [[iTermStatusBarRPCComponentFactory alloc] initWithRegistrationRequest:_registrationRequest];
}

- (NSString *)statusBarComponentShortDescription {
    return _registrationRequest.statusBarComponentAttributes.shortDescription;
}

- (NSString *)statusBarComponentDetailedDescription {
    return _registrationRequest.statusBarComponentAttributes.detailedDescription;
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
    knobs = [_registrationRequest.statusBarComponentAttributes.knobsArray mapWithBlock:^id(ITMRPCRegistrationRequest_StatusBarComponentAttributes_Knob *descriptor) {
        return [[iTermStatusBarComponentKnob alloc] initWithLabelText:descriptor.name
                                                                 type:[self knobTypeFromDescriptorType:descriptor.type]
                                                          placeholder:descriptor.hasPlaceholder ? descriptor.placeholder : nil
                                                         defaultValue:descriptor.hasJsonDefaultValue ? [NSJSONSerialization it_objectForJsonString:descriptor.jsonDefaultValue] : nil
                                                                  key:descriptor.key];
    }] ?: @[];
    return [knobs arrayByAddingObjectsFromArray:[super statusBarComponentKnobs]];
}

- (id)statusBarComponentExemplar {
    return _registrationRequest.statusBarComponentAttributes.exemplar ?: @"";
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
    // Create a temporary frame to shadow __knobs in the scope. This avoids mutating a scope we don't own.
    iTermVariables *variables = [[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextNone
                                                                  owner:self];
    [scope addVariables:variables toScopeNamed:nil];
    NSDictionary *knobsDict = weakSelf.configuration[iTermStatusBarComponentConfigurationKeyKnobValues] ?: @{};
    NSString *jsonKnobs = [NSJSONSerialization it_jsonStringForObject:knobsDict];
    [scope setValue:jsonKnobs forVariableNamed:@"__knobs"];
    [iTermScriptFunctionCall callFunction:self.invocation
                                  timeout:_registrationRequest.timeout ?: [[NSDate distantFuture] timeIntervalSinceNow]
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

- (void)handleSuccessfulEvaluationWithValue:(id)value {
    NSString *stringValue = [NSString castFrom:value];
    NSArray *arrayValue = [NSArray castFrom:value];
    if (stringValue) {
        _variants = @[ stringValue ];
    } else if ([arrayValue allWithBlock:^BOOL(id anObject) {
        return [anObject isKindOfClass:[NSString class]];
    }]) {
        _variants = arrayValue;
    } else {
        [[iTermScriptHistoryEntry globalEntry] addOutput:[NSString stringWithFormat:@"Return value from %@ invalid. Return value was: %@", self.invocation, value]];
        _variants = @[ @"🐞" ];
    }
    [self updateTextFieldIfNeeded];
}

- (void)handleEvaluationError:(NSError *)error
             missingFunctions:(NSSet<NSString *> *)missingFunctions {
    NSString *message = [NSString stringWithFormat:@"Error evaluating status bar component function invocation %@: %@\n%@\n",
                         self.invocation, error.localizedDescription, error.localizedFailureReason];
    [[iTermScriptHistoryEntry globalEntry] addOutput:message];
    _variants = @[ @"🐞" ];
    _missingFunctions = [missingFunctions mutableCopy];
    [self updateTextFieldIfNeeded];
}

- (void)statusBarComponentSetKnobValues:(NSDictionary *)knobValues {
    [self updateWithKnobValues:knobValues];
    [super statusBarComponentSetKnobValues:knobValues];
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
    if (_registrationRequest.statusBarComponentAttributes.hasUpdateCadence) {
        return _registrationRequest.statusBarComponentAttributes.updateCadence;
    } else {
        return INFINITY;
    }
}

- (void)onClick:(id)sender {
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

@end

NS_ASSUME_NONNULL_END
