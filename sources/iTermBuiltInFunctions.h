//
//  iTermBuiltInFunctions.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/8/18.
//

#import <Foundation/Foundation.h>

#import "iTermVariableScope.h"

NS_ASSUME_NONNULL_BEGIN

NSString *iTermFunctionSignatureFromNamespaceAndNameAndArguments(NSString * _Nullable namespace, NSString *name, NSArray<NSString *> *argumentNames);

typedef void (^iTermBuiltInFunctionCompletionBlock)(id _Nullable result, NSError * _Nullable error);
typedef void (^iTermBuiltInFunctionsExecutionBlock)(NSDictionary * _Nonnull parameters, _Nonnull  iTermBuiltInFunctionCompletionBlock completion);

@protocol iTermBuiltInFunction<NSObject>
+ (void)registerBuiltInFunction;
@end

@interface iTermBuiltInFunction : NSObject

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSDictionary<NSString *, Class> *argumentsAndTypes;
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *defaultValues;
@property (nonatomic, readonly) iTermBuiltInFunctionsExecutionBlock block;

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

- (BOOL)matchedBySignature:(NSString *)signature inNamespace:(NSString *)namespace;

@end

@interface iTermBuiltInFunctions : NSObject

+ (instancetype)sharedInstance;
+ (void)registerStandardFunctions;

// for tests to temporarily add functions
- (id)savedState;
- (void)restoreState:(id)savedState;

- (void)registerFunction:(iTermBuiltInFunction *)function
               namespace:(nullable NSString *)namespace;

- (BOOL)haveFunctionWithName:(NSString *)name
                   namespace:(NSString *)namespace
                   arguments:(NSArray<NSString *> *)arguments;

- (void)callFunctionWithName:(NSString *)name
                   namespace:(NSString *)namespace
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
