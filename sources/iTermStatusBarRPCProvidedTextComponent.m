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

- (id<iTermStatusBarComponent>)newComponentWithKnobs:(NSDictionary *)knobs {
    return [[iTermStatusBarRPCProvidedTextComponent alloc] initWithRegistrationRequest:_registrationRequest
                                                                                 knobs:knobs];
}

@end

@implementation iTermStatusBarRPCProvidedTextComponent {
    ITMRPCRegistrationRequest *_registrationRequest;
    NSArray<NSString *> *_variants;
    NSSet<NSString *> *_dependencies;
    NSMutableSet<NSString *> *_missingFunctions;
}

- (instancetype)initWithRegistrationRequest:(ITMRPCRegistrationRequest *)registrationRequest
                                      knobs:(NSDictionary *)knobs {
    return [self initWithConfiguration:@{ iTermStatusBarRPCRegistrationRequestKey: registrationRequest.data,
                                          iTermStatusBarComponentConfigurationKeyKnobValues: knobs }];
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration {
    NSData *data = configuration[iTermStatusBarRPCRegistrationRequestKey];;
    ITMRPCRegistrationRequest *registrationRequest = [[ITMRPCRegistrationRequest alloc] initWithData:data
                                                                                               error:nil];
    if (!registrationRequest) {
        return nil;
    }
    self = [super initWithConfiguration:configuration];
    if (self) {
        _registrationRequest = registrationRequest;
        NSMutableSet<NSString *> *dependencies = [NSMutableSet set];
        [iTermScriptFunctionCall callFunction:self.invocation
                                      timeout:0
                                       source:^id(NSString *path) {
                                           if ([path isEqual:@"__knobs"]) {
                                               return @"";
                                           }
                                           [dependencies addObject:path];
                                           return @"";
                                       }
                                   completion:^(id value, NSError *error, NSSet<NSString *> *missingFunctions) {
                                   }];
        _dependencies = dependencies.copy;
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

- (id<iTermStatusBarComponentFactory>)statusBarComponentFactory {
    return [[iTermStatusBarRPCComponentFactory alloc] initWithRegistrationRequest:_registrationRequest];
}

- (NSString *)statusBarComponentShortDescription {
    return _registrationRequest.statusBarComponentAttributes.shortDescription;
}

- (NSString *)statusBarComponentDetailedDescription {
    return _registrationRequest.statusBarComponentAttributes.detailedDescription;
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

- (NSSet<NSString *> *)statusBarComponentVariableDependencies {
    NSArray *paths = [_registrationRequest.defaultsArray mapWithBlock:^id(ITMRPCRegistrationRequest_RPCArgument *anObject) {
        return anObject.path;
    }];
    return [NSSet setWithArray:paths];
}

- (void)statusBarComponentVariablesDidChange:(NSSet<NSString *> *)variables {
    if (![variables intersectsSet:_dependencies]) {
        return;
    }
    [self updateWithKnobValues:self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues]];
}

- (void)statusBarComponentSetVariableScope:(iTermVariableScope *)scope {
    [super statusBarComponentSetVariableScope:scope];
    [self updateWithKnobValues:self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues]];
}

- (void)statusBarComponentUpdate {
    [self updateWithKnobValues:self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues]];
}

- (nullable NSArray<NSString *> *)stringVariants {
    return _variants ?: @[ @"" ];
}

- (void)updateWithKnobValues:(NSDictionary<NSString *, id> *)knobValues {
    __weak __typeof(self) weakSelf = self;
    [iTermScriptFunctionCall callFunction:self.invocation
                                  timeout:_registrationRequest.timeout ?: [[NSDate distantFuture] timeIntervalSinceNow]
                                   source:
     ^id(NSString *path) {
         if ([path isEqual:@"__knobs"]) {
             NSDictionary *knobs = weakSelf.configuration[iTermStatusBarComponentConfigurationKeyKnobValues] ?: @{};
             return [NSJSONSerialization it_jsonStringForObject:knobs];
         }

         return [self.scope valueForVariableName:path];
     }
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

- (void)registeredFunctionsDidChange:(NSNotification *)notifiation {
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

@end

NS_ASSUME_NONNULL_END
