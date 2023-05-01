//
//  iTermBuiltInFunctions.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/8/18.
//

#import <Foundation/Foundation.h>

#import "iTermVariableScope.h"

NS_ASSUME_NONNULL_BEGIN

NSString *iTermFunctionSignatureFromNamespaceAndNameAndArguments(NSString * _Nullable namespace_, NSString *name, NSArray<NSString *> *argumentNames);

// Returns all combinations of valid arguments. Of size pow(2,optionalArguments.count).
NSArray<NSString *> *
iTermAllFunctionSignaturesFromNamespaceAndNameAndArguments(NSString *namespace,
                                                           NSString *name,
                                                           NSArray<NSString *> *argumentNames,
                                                           NSSet<NSString *> *optionalArguments);

typedef void (^iTermBuiltInFunctionCompletionBlock)(id _Nullable result, NSError * _Nullable error);
typedef void (^iTermBuiltInFunctionsExecutionBlock)(NSDictionary * _Nonnull parameters, _Nonnull  iTermBuiltInFunctionCompletionBlock completion);

NS_SWIFT_NAME(iTermBuiltInFunctionProtocol)
@protocol iTermBuiltInFunction<NSObject>
+ (void)registerBuiltInFunction;
@end

@interface iTermBuiltInFunction : NSObject

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSDictionary<NSString *, Class> *argumentsAndTypes;
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *defaultValues;
@property (nonatomic, readonly) iTermBuiltInFunctionsExecutionBlock block;
@property (nonatomic, readonly) NSSet<NSString *> *optionalArguments;

// All arguments must always be passed, even if they are optional.
// Optional arguments may take a value of NSNull but must be specified regardless.
// Default values are paths to variable names, as in iterm2.Reference("id"). These must be omitted at call time and these keys are NOT included in arguments.
- (instancetype)initWithName:(NSString *)name
                   arguments:(NSDictionary<NSString *, Class> *)argumentsAndTypes
           optionalArguments:(NSSet<NSString *> *)optionalArguments
               defaultValues:(NSDictionary<NSString *, NSString *> *)defaultValues  // arg name -> variable name
                     context:(iTermVariablesSuggestionContext)context
                       block:(iTermBuiltInFunctionsExecutionBlock)block NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface iTermBuiltInMethod : iTermBuiltInFunction

- (instancetype)initWithName:(NSString *)name
               defaultValues:(NSDictionary<NSString *, NSString *> *)defaultValues  // arg name -> variable name
                       types:(NSDictionary<NSString *, Class> *)types
           optionalArguments:(NSSet<NSString *> *)optionalArguments
                     context:(iTermVariablesSuggestionContext)context
                      target:(id<iTermObject>)target
                      action:(SEL)action;

- (void)callWithArguments:(NSDictionary<NSString *, id> *)arguments
               completion:(iTermBuiltInFunctionCompletionBlock)block;

- (BOOL)matchedBySignature:(NSString *)signature inNamespace:(NSString *)namespace_;

@end

@interface iTermBuiltInFunctions : NSObject

+ (instancetype)sharedInstance;
+ (void)registerStandardFunctions;

// for tests to temporarily add functions
- (id)savedState;
- (void)restoreState:(id)savedState;

- (void)registerFunction:(iTermBuiltInFunction *)function
               namespace:(nullable NSString *)namespace_;

- (BOOL)haveFunctionWithName:(NSString *)name
                   namespace:(NSString *)namespace_
                   arguments:(NSArray<NSString *> *)arguments;

- (void)callFunctionWithName:(NSString *)name
                   namespace:(NSString *)namespace_
                  parameters:(NSDictionary<NSString *, id> *)parameters
                       scope:(iTermVariableScope *)scope
                  completion:(iTermBuiltInFunctionCompletionBlock)completion;

- (NSError *)undeclaredIdentifierError:(NSString *)identifier;
- (NSError *)invalidReferenceError:(NSString *)reference name:(NSString *)name;
- (NSString *)signatureOfAnyRegisteredFunctionWithName:(NSString *)name;
- (NSDictionary<NSString *, NSArray<NSString *> *> *)registeredFunctionSignatureDictionary;
- (nullable iTermBuiltInMethod *)methodWithSignature:(NSString *)signature;

@end

@interface iTermArrayCountBuiltInFunction : NSObject<iTermBuiltInFunction>
@end

NS_ASSUME_NONNULL_END
