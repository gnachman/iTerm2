//
//  iTermBuiltInFunctions.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/8/18.
//

#import "iTermBuiltInFunctions.h"

#import "iTermVariableReference.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"

NSString *iTermFunctionSignatureFromNameAndArguments(NSString *name, NSArray<NSString *> *argumentNames) {
    NSString *combinedArguments = [[argumentNames sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","];
    return [NSString stringWithFormat:@"%@(%@)",
            name,
            combinedArguments];
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
    NSString *reason = [NSString stringWithFormat:@"Type mismatch for argument %@. Got %@, expected %@.",
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
    NSMutableDictionary<NSString *, iTermBuiltInFunction *> *_functions;
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
    NSString *name = [NSString stringWithFormat:@"%@.%@", namespace, function.name];
    NSString *signature = iTermFunctionSignatureFromNameAndArguments(name, function.argumentsAndTypes.allKeys);
    _functions[signature] = function;
}

- (BOOL)haveFunctionWithName:(NSString *)name arguments:(NSArray<NSString *> *)arguments {
    NSString *signature = iTermFunctionSignatureFromNameAndArguments(name, arguments);
    return _functions[signature] != nil;
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
