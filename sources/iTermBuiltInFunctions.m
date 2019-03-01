//
//  iTermBuiltInFunctions.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/8/18.
//

#import "iTermBuiltInFunctions.h"

#import "iTermAlertBuiltInFunction.h"
#import "iTermVariableReference.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"

NSString *iTermFunctionSignatureFromNameAndArguments(NSString *name, NSArray<NSString *> *argumentNames) {
    NSString *combinedArguments = [[argumentNames sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","];
    return [NSString stringWithFormat:@"%@(%@)",
            name,
            combinedArguments];
}

NSString *iTermFunctionNameFromSignature(NSString *signature) {
    NSInteger index = [signature rangeOfString:@"("].location;
    if (index == NSNotFound || index == 0) {
        return nil;
    }
    return [signature substringWithRange:NSMakeRange(0, index)];
}

@interface iTermBuiltInFunction()
- (nullable NSError *)typeCheckParameters:(NSDictionary<NSString *, id> *)parameters;
@end

@implementation iTermBuiltInFunction

- (instancetype)initWithName:(NSString *)name
                   arguments:(NSDictionary<NSString *,Class> *)argumentsAndTypes
               defaultValues:(NSDictionary<NSString *,NSString *> *)defaultValues
                     context:(iTermVariablesSuggestionContext)context
                       block:(iTermBuiltInFunctionsExecutionBlock)block {
    self = [super init];
    if (self) {
        _name = [name copy];
        _argumentsAndTypes = [argumentsAndTypes copy];
        _defaultValues = [defaultValues copy];
        _block = [block copy];
        [defaultValues enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
            [iTermVariableHistory recordUseOfVariableNamed:obj inContext:context];
        }];
    }
    return self;
}

- (NSString *)signature {
    return iTermFunctionSignatureFromNameAndArguments(_name,
                                                      [self.argumentsAndTypes.allKeys sortedArrayUsingSelector:@selector(compare:)]);
}

#pragma mark - File Private

- (nullable NSError *)typeCheckParameters:(NSDictionary<NSString *, id> *)parameters {
    for (NSString *name in parameters) {
        Class actual = [parameters[name] class];
        Class expected = _argumentsAndTypes[name];
        if (!expected) {
            return [self invalidArgumentError:name];
        }
        if (actual == expected) {
            continue;
        }
        if ([actual isSubclassOfClass:expected]) {
            continue;
        }
        return [self typeMismatchError:name wanted:expected got:actual];
    }
    return nil;
}

#pragma mark - Private

- (NSError *)typeMismatchError:(NSString *)argument wanted:(Class)wanted got:(nullable id)object {
    NSString *reason = [NSString stringWithFormat:@"Type mismatch for argument %@. Expected %@ but got %@.",
                        argument,
                        NSStringFromClass(wanted),
                        object ? NSStringFromClass([object class]) : @"(null)" ];
    return [NSError errorWithDomain:@"com.iterm2.bif"
                               code:2
                           userInfo:@{ NSLocalizedFailureReasonErrorKey: reason }];
}

- (NSError *)invalidArgumentError:(NSString *)argument {
    NSString *reason = [NSString stringWithFormat:@"Invalid argument %@ to %@",
                        argument, _name];
    return [NSError errorWithDomain:@"com.iterm2.bif"
                               code:4
                           userInfo:@{ NSLocalizedFailureReasonErrorKey: reason }];
}

@end

@implementation iTermBuiltInFunctions {
    // NOTE: The keys include the namespace, but the iTermBuiltInFunction object is ignorant of it.
    NSMutableDictionary<NSString *, iTermBuiltInFunction *> *_functions;
}

- (id)savedState {
    return [_functions mutableCopy];
}

- (void)restoreState:(id)savedState {
    _functions = savedState;
}

+ (void)registerStandardFunctions {
    [iTermArrayCountBuiltInFunction registerBuiltInFunction];
    [iTermAlertBuiltInFunction registerBuiltInFunction];
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _functions = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)registerFunction:(iTermBuiltInFunction *)function namespace:(NSString *)namespace {
    NSString *name = namespace ? [NSString stringWithFormat:@"%@.%@", namespace, function.name] : function.name;
    NSString *signature = iTermFunctionSignatureFromNameAndArguments(name, function.argumentsAndTypes.allKeys);
    _functions[signature] = function;
}

- (BOOL)haveFunctionWithName:(NSString *)name arguments:(NSArray<NSString *> *)arguments {
    NSString *signature = iTermFunctionSignatureFromNameAndArguments(name, arguments);
    return _functions[signature] != nil;
}

- (NSString *)signatureOfAnyRegisteredFunctionWithName:(NSString *)name {
    return [_functions.allKeys objectPassingTest:^BOOL(NSString *signature, NSUInteger index, BOOL *stop) {
        NSString *signatureName = iTermFunctionNameFromSignature(signature);
        return [signatureName isEqualToString:name];
    }];
}

- (NSDictionary<NSString *, NSArray<NSString *> *> *)registeredFunctionSignatureDictionary {
    // Convert _functions: (signature -> bif) to (name -> [arg, arg, ...])
    NSDictionary *signatureToArgs = [_functions mapValuesWithBlock:^id(NSString *signature, iTermBuiltInFunction *bif) {
        return bif.argumentsAndTypes.allKeys;
    }];
    NSDictionary *nameToArgs = [signatureToArgs mapKeysWithBlock:^id(NSString *signature, id object) {
        return iTermFunctionNameFromSignature(signature);
    }];
    NSDictionary *publicNameToArgs = [nameToArgs filterWithBlock:^BOOL(NSString *name, id object) {
        return ![name hasPrefix:@"iterm2.private"];
    }];
    return publicNameToArgs;
}

- (void)callFunctionWithName:(NSString *)name
                  parameters:(NSDictionary<NSString *, id> *)parameters
                       scope:(iTermVariableScope *)scope
                  completion:(nonnull iTermBuiltInFunctionCompletionBlock)completion {
    NSArray<NSString *> *arguments = parameters.allKeys;
    NSString *signature = iTermFunctionSignatureFromNameAndArguments(name, arguments);
    iTermBuiltInFunction *function = _functions[signature];
    if (!function) {
        NSError *error = [self undeclaredIdentifierError:signature];
        completion(nil, error);
        return;
    }

    NSMutableDictionary<NSString *, id> *amendedParameters = parameters.mutableCopy;
    for (NSString *arg in function.defaultValues) {
        if (parameters[arg]) {
            // Override default value
            continue;
        }

        NSString *path = function.defaultValues[arg];
        id value = [scope valueForVariableName:path];
        if (value) {
            amendedParameters[arg] = value;
        }
    }
    NSError *typeError = [function typeCheckParameters:parameters];
    if (typeError) {
        completion(nil, typeError);
        return;
    }

    function.block(amendedParameters, completion);
}

- (NSError *)undeclaredIdentifierError:(NSString *)identifier {
    NSString *reason = [NSString stringWithFormat:@"Undeclared identifier %@",
                        identifier];
    return [NSError errorWithDomain:@"com.iterm2.bif"
                               code:1
                           userInfo:@{ NSLocalizedFailureReasonErrorKey: reason }];
}

- (NSError *)invalidReferenceError:(NSString *)reference name:(NSString *)name {
    NSString *reason = [NSString stringWithFormat:@"Invalid reference “%@” to %@",
                        reference, name];
    return [NSError errorWithDomain:@"com.iterm2.bif"
                               code:3
                           userInfo:@{ NSLocalizedFailureReasonErrorKey: reason }];
}

@end

@implementation iTermArrayCountBuiltInFunction

+ (void)registerBuiltInFunction {
    NSString *const array = @"array";
    iTermBuiltInFunction *func =
    [[iTermBuiltInFunction alloc] initWithName:@"count"
                                     arguments:@{ array: [NSArray class] }
                                 defaultValues:@{}
                                       context:iTermVariablesSuggestionContextNone
                                         block:
     ^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock  _Nonnull completion) {
         [self countOfObject:parameters[array] completion:completion];
     }];
    [[iTermBuiltInFunctions sharedInstance] registerFunction:func
                                                   namespace:@"iterm2"];
}

+ (void)countOfObject:(id)value completion:(iTermBuiltInFunctionCompletionBlock)completion {
    if (!value) {
        NSError *error = [NSError errorWithDomain:@"com.iterm2.array-count"
                                             code:1
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Array argument must be non-null" }];
        completion(nil, error);
        return;
    }

    NSArray *array = [NSArray castFrom:value];
    if (!array) {
        NSError *error = [NSError errorWithDomain:@"com.iterm2.array-count"
                                             code:2
                                         userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Argument must be an array (was %@)", [value class]] }];
        completion(nil, error);
        return;
    }

    completion(@(array.count), nil);
}

@end

