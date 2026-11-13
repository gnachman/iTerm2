//
//  iTermBuiltInFunctions.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/8/18.
//

#import "iTermBuiltInFunctions.h"

#import "iTerm2SharedARC-Swift.h"
#import "iTermAlertBuiltInFunction.h"
#import "iTermReflection.h"
#import "iTermSetStatusBarComponentUnreadCountBuiltInFunction.h"
#import "iTermTabGroupBuiltInFunctions.h"
#import "iTermVariableReference.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"

#import <objc/runtime.h>

static NSString *iTermQualifiedFunctionName(NSString *namespace, NSString *name) {
    if (!namespace) {
        return name;
    }
    return [NSString stringWithFormat:@"%@.%@", namespace, name];
}

NSString *iTermFunctionSignatureFromNamespaceAndNameAndArguments(NSString *namespace, NSString *name, NSArray<NSString *> *argumentNames) {
    NSString *combinedArguments = [[argumentNames sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","];
    NSString *tail = [NSString stringWithFormat:@"%@(%@)",
                      name,
                      combinedArguments];
    if (!namespace) {
        return tail;
    }
    return [NSString stringWithFormat:@"%@.%@", namespace, tail];
}

NSString *iTermFunctionNameFromSignature(NSString *signature) {
    NSInteger index = [signature rangeOfString:@"("].location;
    if (index == NSNotFound || index == 0) {
        return nil;
    }
    return [signature substringWithRange:NSMakeRange(0, index)];
}

NSSet<NSString *> *iTermArgumentNamesFromSignature(NSString *signature) {
    NSInteger index = [signature rangeOfString:@"("].location;
    if (index == NSNotFound || index == 0) {
        return nil;
    }
    NSString *afterParen = [signature substringFromIndex:index + 1];
    if (![afterParen hasSuffix:@")"]) {
        return nil;
    }
    NSString *argList = [afterParen substringToIndex:afterParen.length - 1];
    NSArray<NSString *> *names = [argList componentsSeparatedByString:@","];
    return [NSSet setWithArray:names];
}

NSString *iTermNamespaceFromSignature(NSString *signature) {
    NSString *name = iTermFunctionNameFromSignature(signature);
    NSArray<NSString *> *parts = [name componentsSeparatedByString:@"."];
    if (parts.count != 2) {
        return nil;
    }
    return parts[0];
}

@interface iTermBuiltInFunction()
- (nullable NSError *)typeCheckParameters:(NSDictionary<NSString *, id> *)parameters;
- (BOOL)acceptsArgumentNames:(NSSet<NSString *> *)names;
- (BOOL)couldBeConfusedWith:(iTermBuiltInFunction *)other;
@end

@implementation iTermBuiltInFunction

- (instancetype)initWithName:(NSString *)name
                   arguments:(NSDictionary<NSString *,Class> *)argumentsAndTypes
           optionalArguments:(NSSet<NSString *> *)optionalArguments
               defaultValues:(NSDictionary<NSString *,NSString *> *)defaultValues
                     context:(iTermVariablesSuggestionContext)context
      sideEffectsPlaceholder:(NSString * _Nullable)sideEffectsPlaceholder
                       block:(iTermBuiltInFunctionsExecutionBlock)block {
    self = [super init];
    if (self) {
        _name = [name copy];
        _argumentsAndTypes = [argumentsAndTypes copy];
        _defaultValues = [defaultValues copy];
        _block = [block copy];
        _optionalArguments = [optionalArguments copy];
        _sideEffectsPlaceholder = [sideEffectsPlaceholder copy];
        [defaultValues enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
            [iTermVariableHistory recordUseOfVariableNamed:obj inContext:context];
        }];
    }
    return self;
}

#pragma mark - File Private

- (NSSet<NSString *> *)requiredArguments {
    NSMutableSet<NSString *> *required = [NSMutableSet setWithArray:_argumentsAndTypes.allKeys];
    // Through the accessor: iTermBuiltInMethod keeps its own.
    [required minusSet:self.optionalArguments];
    return required;
}

// Whether a call passing exactly these argument names is a call to this function: every name is
// one it takes, and every argument it requires is among them.
- (BOOL)acceptsArgumentNames:(NSSet<NSString *> *)names {
    for (NSString *name in names) {
        if (!_argumentsAndTypes[name]) {
            return NO;
        }
    }
    return [self.requiredArguments isSubsetOfSet:names];
}

// Whether some set of argument names is accepted by both, in which case a call with those names
// would not say which function it means. That is so exactly when the smallest set that satisfies
// both, everything either requires, is made of names both take.
- (BOOL)couldBeConfusedWith:(iTermBuiltInFunction *)other {
    NSMutableSet<NSString *> *required = [self.requiredArguments mutableCopy];
    [required unionSet:other.requiredArguments];
    return [self acceptsArgumentNames:required] && [other acceptsArgumentNames:required];
}

- (nullable NSError *)typeCheckParameters:(NSDictionary<NSString *, id> *)parameters {
    for (NSString *name in parameters) {
        Class actual = [parameters[name] class];
        if ([parameters[name] isKindOfClass:[NSNull class]] &&
            [_optionalArguments containsObject:name]) {
            continue;
        }
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
    NSString *reason = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"BuiltInFunction.TypeMismatch", nil, [NSBundle mainBundle], @"Type mismatch for argument %1$@. Expected %2$@ but got %3$@.", @"Error when a function argument has the wrong type; placeholders are argument name, expected type, actual type"),
                        argument,
                        NSStringFromClass(wanted),
                        object ? NSStringFromClass([object class]) : @"(null)" ];
    return [NSError errorWithDomain:@"com.iterm2.bif"
                               code:2
                           userInfo:@{ NSLocalizedFailureReasonErrorKey: reason }];
}

- (NSError *)invalidArgumentError:(NSString *)argument {
    NSString *reason = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"BuiltInFunction.InvalidArgument", nil, [NSBundle mainBundle], @"Invalid argument %1$@ to %2$@", @"Error when a function is passed an unknown argument; placeholders are argument name and function name"),
                        argument, _name];
    return [NSError errorWithDomain:@"com.iterm2.bif"
                               code:4
                           userInfo:@{ NSLocalizedFailureReasonErrorKey: reason }];
}

@end

@implementation iTermBuiltInFunctions {
    // Functions by qualified name (namespace.name; the iTermBuiltInFunction object is ignorant of
    // its namespace). More than one may share a name as long as no call could mean either. A
    // call is matched to a function by its argument names (see -functionWithQualifiedName:
    // argumentNames:), so optional arguments cost nothing to register however many there are.
    // The arrays are immutable so that a saved state is a snapshot.
    NSMutableDictionary<NSString *, NSArray<iTermBuiltInFunction *> *> *_functions;
}

- (id)savedState {
    return [_functions mutableCopy];
}

- (void)restoreState:(id)savedState {
    _functions = [savedState mutableCopy];
}

- (nullable iTermBuiltInFunction *)functionWithQualifiedName:(NSString *)qualifiedName
                                               argumentNames:(NSArray<NSString *> *)argumentNames {
    NSSet<NSString *> *names = [NSSet setWithArray:argumentNames];
    for (iTermBuiltInFunction *function in _functions[qualifiedName]) {
        if ([function acceptsArgumentNames:names]) {
            return function;
        }
    }
    return nil;
}

+ (void)registerStandardFunctions {
    [iTermAddClippingBuiltInFunction registerBuiltInFunction];
    [iTermArchiveClippingsBuiltInFunction registerBuiltInFunction];
    [iTermDeleteClippingBuiltInFunction registerBuiltInFunction];
    [iTermArrayCountBuiltInFunction registerBuiltInFunction];
    [iTermAlertBuiltInFunction registerBuiltInFunction];
    [iTermGetStringBuiltInFunction registerBuiltInFunction];
    [iTermGetPolyModalAlertBuiltInFunction registerBuiltInFunction];
    [iTermFocusBuiltInFunction registerBuiltInFunction];
    [iTermSetStatusBarComponentUnreadCountBuiltInFunction registerBuiltInFunction];
    [iTermOpenPanelBuiltInFunction registerBuiltInFunction];
    [iTermPasteBuiltInFunction registerBuiltInFunction];
    [iTermSavePanelBuiltInFunction registerBuiltInFunction];
    [iTermGetProfilePropertyBuiltInFunction registerBuiltInFunction];
    [iTermColorAlphaBuiltInFunction registerBuiltInFunction];
    [iTermInterpolateBuiltInFunction registerBuiltInFunction];
    [iTermURLEncodeBuiltInFunction registerBuiltInFunction];
    [iTermTmuxFormatBuiltInFunction registerBuiltInFunction];
    [iTermSetStatusBuiltInFunction registerBuiltInFunction];
    [iTermSendCompanionNotificationBuiltInFunction registerBuiltInFunction];
    [iTermTabGroupBuiltInFunctions registerBuiltInFunction];
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
    NSString *qualifiedName = iTermQualifiedFunctionName(namespace, function.name);
    NSArray<iTermBuiltInFunction *> *existing = _functions[qualifiedName] ?: @[];
    for (iTermBuiltInFunction *other in existing) {
        assert(![function couldBeConfusedWith:other]);
    }
    _functions[qualifiedName] = [existing arrayByAddingObject:function];
}

- (BOOL)haveFunctionWithName:(NSString *)name
                   namespace:(NSString *)namespace
                   arguments:(NSArray<NSString *> *)arguments {
    return [self functionWithQualifiedName:iTermQualifiedFunctionName(namespace, name)
                             argumentNames:arguments] != nil;
}

- (NSString *)signatureOfAnyRegisteredFunctionWithName:(NSString *)name {
    iTermBuiltInFunction *function = _functions[name].firstObject;
    if (!function) {
        return nil;
    }
    return iTermFunctionSignatureFromNamespaceAndNameAndArguments(nil, name, function.argumentsAndTypes.allKeys);
}

- (NSDictionary<NSString *, NSArray<NSString *> *> *)registeredFunctionSignatureDictionary {
    // Convert _functions: (name -> [bif]) to (name -> [arg, arg, ...])
    NSDictionary *nameToArgs = [_functions mapValuesWithBlock:^id(NSString *name, NSArray<iTermBuiltInFunction *> *functions) {
        return functions.lastObject.argumentsAndTypes.allKeys;
    }];
    NSDictionary *publicNameToArgs = [nameToArgs filteredWithBlock:^BOOL(NSString *name, id object) {
        return ![name hasPrefix:@"iterm2.private"];
    }];
    return publicNameToArgs;
}

- (void)callFunctionWithName:(NSString *)name
                   namespace:(NSString *)namespace
                  parameters:(NSDictionary<NSString *, id> *)parameters
                       scope:(iTermVariableScope *)scope
          sideEffectsAllowed:(BOOL)sideEffectsAllowed
                  completion:(nonnull iTermBuiltInFunctionCompletionBlock)completion {
    NSArray<NSString *> *arguments = parameters.allKeys;
    iTermBuiltInFunction *function = [self functionWithQualifiedName:iTermQualifiedFunctionName(namespace, name)
                                                       argumentNames:arguments];
    if (!function) {
        NSString *signature = iTermFunctionSignatureFromNamespaceAndNameAndArguments(namespace, name, arguments);
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

    if (!sideEffectsAllowed && function.sideEffectsPlaceholder) {
        completion(function.sideEffectsPlaceholder, nil);
        return;
    }
    function.block([amendedParameters dictionaryByRemovingNullValues], completion);
}

- (NSError *)undeclaredIdentifierError:(NSString *)identifier {
    NSString *reason = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"BuiltInFunction.UndeclaredIdentifier", nil, [NSBundle mainBundle], @"Undeclared identifier %@", @"Error when a function references an identifier that was not declared; placeholder is the identifier"),
                        identifier];
    return [NSError errorWithDomain:@"com.iterm2.bif"
                               code:1
                           userInfo:@{ NSLocalizedFailureReasonErrorKey: reason }];
}

- (NSError *)invalidReferenceError:(NSString *)reference name:(NSString *)name {
    NSString *reason = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"BuiltInFunction.InvalidReference", nil, [NSBundle mainBundle], @"Invalid reference “%1$@” to %2$@", @"Error when a reference is invalid; placeholders are the reference and the name"),
                        reference, name];
    return [NSError errorWithDomain:@"com.iterm2.bif"
                               code:3
                           userInfo:@{ NSLocalizedFailureReasonErrorKey: reason }];
}

- (iTermBuiltInMethod *)methodWithSignature:(NSString *)signature {
    NSString *qualifiedName = iTermFunctionNameFromSignature(signature);
    NSSet<NSString *> *signatureArguments = iTermArgumentNamesFromSignature(signature);
    if (!qualifiedName || !signatureArguments) {
        return nil;
    }
    // "f()" parses as one argument with an empty name.
    NSArray<NSString *> *argumentNames = [signatureArguments.allObjects filteredArrayUsingBlock:^BOOL(NSString *name) {
        return name.length > 0;
    }];
    return [iTermBuiltInMethod castFrom:[self functionWithQualifiedName:qualifiedName
                                                          argumentNames:argumentNames]];
}

@end

@implementation iTermArrayCountBuiltInFunction

+ (void)registerBuiltInFunction {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *const array = @"array";
        iTermBuiltInFunction *func =
        [[iTermBuiltInFunction alloc] initWithName:@"count"
                                         arguments:@{ array: [NSArray class] }
                                 optionalArguments:[NSSet set]
                                     defaultValues:@{}
                                           context:iTermVariablesSuggestionContextNone
                            sideEffectsPlaceholder:nil
                                             block:
         ^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock  _Nonnull completion) {
             [self countOfObject:parameters[array] completion:completion];
         }];
        [[iTermBuiltInFunctions sharedInstance] registerFunction:func
                                                       namespace:@"iterm2"];
    });
}

+ (void)countOfObject:(id)value completion:(iTermBuiltInFunctionCompletionBlock)completion {
    if (!value) {
        NSError *error = [NSError errorWithDomain:@"com.iterm2.array-count"
                                             code:1
                                         userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedStringWithDefaultValue(@"ArrayCount.ArgumentMustBeNonNull", nil, [NSBundle mainBundle], @"Array argument must be non-null", @"Error when the array argument to count() is null") }];
        completion(nil, error);
        return;
    }

    NSArray *array = [NSArray castFrom:value];
    if (!array) {
        NSError *error = [NSError errorWithDomain:@"com.iterm2.array-count"
                                             code:2
                                         userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ArrayCount.ArgumentMustBeArray", nil, [NSBundle mainBundle], @"Argument must be an array (was %@)", @"Error when the argument to count() is not an array; placeholder is the actual class"), [value class]] }];
        completion(nil, error);
        return;
    }

    completion(@(array.count), nil);
}

@end

@implementation iTermURLEncodeBuiltInFunction

+ (void)registerBuiltInFunction {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *const string = @"string";
        iTermBuiltInFunction *func =
        [[iTermBuiltInFunction alloc] initWithName:@"urlEncode"
                                         arguments:@{ string: [NSString class] }
                                 optionalArguments:[NSSet set]
                                     defaultValues:@{}
                                           context:iTermVariablesSuggestionContextNone
                            sideEffectsPlaceholder:nil
                                             block:
         ^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock  _Nonnull completion) {
            [self urlEncoded:parameters[string] completion:completion];
        }];
        [[iTermBuiltInFunctions sharedInstance] registerFunction:func
                                                       namespace:@"iterm2"];
    });
}

+ (void)urlEncoded:(id)value completion:(iTermBuiltInFunctionCompletionBlock)completion {
    if (!value) {
        NSError *error = [NSError errorWithDomain:@"com.iterm2.url-encode"
                                             code:1
                                         userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedStringWithDefaultValue(@"URLEncode.StringArgumentMustBeNonNull", nil, [NSBundle mainBundle], @"string argument must be non-null", @"Error when the string argument to urlEncode() is null") }];
        completion(nil, error);
        return;
    }

    NSString *string = [NSString castFrom:value];
    if (!string) {
        NSError *error = [NSError errorWithDomain:@"com.iterm2.url-encode"
                                             code:2
                                         userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"URLEncode.ArgumentMustBeString", nil, [NSBundle mainBundle], @"Argument must be a string (was %@)", @"Error when the argument to urlEncode() is not a string; placeholder is the actual class"), [value class]] }];
        completion(nil, error);
        return;
    }

    completion([string stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]],
               nil);
}

@end

@implementation iTermBuiltInMethod {
    NSArray<iTermReflectionMethodArgument *> *_args;
    __weak id<iTermObject> _target;
    SEL _action;
    NSDictionary<NSString *, Class> *_types;
    NSSet<NSString *> *_optionalArguments;
}

+ (NSArray<iTermReflectionMethodArgument *> *)argumentsFromTarget:(id<iTermObject>)target
                                                           action:(SEL)action {
    iTermReflection *reflection = [[iTermReflection alloc] initWithClass:[(NSObject *)target class] selector:action];
    return reflection.arguments;
}

+ (NSDictionary<NSString *, Class> *)argumentDictionaryFromArray:(NSArray<iTermReflectionMethodArgument *> *)arguments {
    __block BOOL foundCompletion = NO;
    NSMutableDictionary<NSString *, Class> *result = [NSMutableDictionary dictionary];
    for (iTermReflectionMethodArgument *obj in arguments) {
        assert(result[obj.argumentName] == nil);
        
        switch (obj.type) {
            case iTermReflectionMethodArgumentTypeObject:
                result[obj.argumentName] = NSClassFromString(obj.className);
                break;
            case iTermReflectionMethodArgumentTypeBlock:
                if ([obj.argumentName hasSuffix:@"WithCompletion"]) {
                    foundCompletion = YES;
                    break;
                } else {
                    return nil;
                }
            case iTermReflectionMethodArgumentTypeUnknown:
            case iTermReflectionMethodArgumentTypeVoid:
            case iTermReflectionMethodArgumentTypeArray:
            case iTermReflectionMethodArgumentTypeClass:
            case iTermReflectionMethodArgumentTypeUnion:
            case iTermReflectionMethodArgumentTypeScalar:
            case iTermReflectionMethodArgumentTypeStruct:
            case iTermReflectionMethodArgumentTypePointer:
            case iTermReflectionMethodArgumentTypeBitField:
            case iTermReflectionMethodArgumentTypeSelector:
                // Not legal for built-in methods. They must take only objects and one block named completion.
                return nil;
        }
    }
    if (!foundCompletion) {
        return nil;
    }
    return result;
}

- (instancetype)initWithName:(NSString *)name
               defaultValues:(NSDictionary<NSString *, NSString *> *)defaultValues  // arg name -> variable name
                       types:(NSDictionary<NSString *, Class> *)types
           optionalArguments:(NSSet<NSString *> *)optionalArguments
                     context:(iTermVariablesSuggestionContext)context
      sideEffectsPlaceholder:(NSString *)sideEffectsPlaceholder
                      target:(id<iTermObject>)target
                      action:(SEL)action {
    NSArray<iTermReflectionMethodArgument *> *args = [iTermBuiltInMethod argumentsFromTarget:target action:action];
    if (!args) {
        return nil;
    }
    NSDictionary<NSString *, Class> *argDict = [iTermBuiltInMethod argumentDictionaryFromArray:args];
    if (!argDict) {
        return nil;
    }
    // Remove connectionKey and cancellation from the public signature - they're injected
    // internally, not passed by callers
    NSMutableDictionary *publicArgDict = [argDict mutableCopy];
    [publicArgDict removeObjectForKey:@"connectionKey"];
    [publicArgDict removeObjectForKey:@"cancellation"];
    self = [super initWithName:name
                     arguments:publicArgDict
             optionalArguments:[NSSet set]
                 defaultValues:defaultValues
                       context:context
        sideEffectsPlaceholder:sideEffectsPlaceholder
                         block:^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock  _Nonnull completion) {
                             // Use callWithArguments:completion: instead.
                             assert(NO);
                         }];
    if (self) {
        _args = [args copy];
        _action = action;
        _target = target;
        _types = [types copy];
        _optionalArguments = [optionalArguments copy];
    }
    return self;
}

// The optional arguments are kept here and not handed to the superclass, so this is what tells
// the registry which arguments a call may leave out.
- (NSSet<NSString *> *)optionalArguments {
    return _optionalArguments;
}

- (void)callWithArguments:(NSDictionary<NSString *, id> *)parameters
               completion:(iTermBuiltInFunctionCompletionBlock)completion {
    [self callWithArguments:parameters connectionKey:nil completion:completion];
}

- (void)callWithArguments:(NSDictionary<NSString *, id> *)parameters
            connectionKey:(id)connectionKey
               completion:(iTermBuiltInFunctionCompletionBlock)completion {
    [self callWithArguments:parameters
              connectionKey:connectionKey
               cancellation:nil
                 completion:completion];
}

- (void)callWithArguments:(NSDictionary<NSString *, id> *)parameters
            connectionKey:(id)connectionKey
             cancellation:(iTermScriptCallCancellation *)cancellation
               completion:(iTermBuiltInFunctionCompletionBlock)completion {
    NSMethodSignature *signature = [[(NSObject *)_target class] instanceMethodSignatureForSelector:_action];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = _target;
    invocation.selector = _action;
    id temp[_args.count];
    for (NSInteger i = 0; i < _args.count; i++) {
        iTermReflectionMethodArgument *arg = _args[i];
        if ([arg.argumentName hasSuffix:@"WithCompletion"]) {
            temp[i] = [completion copy];
        } else if ([arg.argumentName isEqualToString:@"connectionKey"]) {
            // Special handling for connectionKey - injected by the caller, not from parameters
            temp[i] = connectionKey;
        } else if ([arg.argumentName isEqualToString:@"cancellation"]) {
            // Injected like connectionKey.
            temp[i] = cancellation;
        } else {
            if (!parameters[arg.argumentName]) {
                assert([_optionalArguments containsObject:arg.argumentName]);
            }
            temp[i] = [parameters[arg.argumentName] nilIfNull];
        }
        Class requiredClass = _types[arg.argumentName];
        if (requiredClass) {
            const BOOL isNull = [parameters[arg.argumentName] isKindOfClass:[NSNull class]];
            if (isNull &&
                ![_optionalArguments containsObject:arg.argumentName]) {
                completion(nil, [self typeMismatchError:arg.argumentName
                                                 wanted:requiredClass
                                                    got:nil]);
                return;
            }
            if (!isNull &&
                ![parameters[arg.argumentName] isKindOfClass:requiredClass] &&
                ![_optionalArguments containsObject:arg.argumentName]) {
                Class actualClass = [parameters[arg.argumentName] class];
                completion(nil, [self typeMismatchError:arg.argumentName
                                                 wanted:requiredClass
                                                    got:actualClass]);
                return;
            }
        }
        [invocation setArgument:&temp[i] atIndex:i + 2];
    }
    [invocation invoke];
}

@end

