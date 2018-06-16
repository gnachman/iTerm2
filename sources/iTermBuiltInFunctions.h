//
//  iTermBuiltInFunctions.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/8/18.
//

#import <Foundation/Foundation.h>

#import "iTermVariables.h"

NS_ASSUME_NONNULL_BEGIN

NSString *iTermFunctionSignatureFromNameAndArguments(NSString *name, NSArray<NSString *> *argumentNames);
typedef void (^iTermBuiltInFunctionCompletionBlock)(id _Nullable result, NSError * _Nullable error);
typedef void (^iTermBuiltInFunctionsExecutionBlock)(NSDictionary * _Nonnull parameters, _Nonnull  iTermBuiltInFunctionCompletionBlock completion);

@interface iTermBuiltInFunction : NSObject

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSDictionary<NSString *, Class> *argumentsAndTypes;
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *defaultValues;
@property (nonatomic, readonly) iTermBuiltInFunctionsExecutionBlock block;

- (instancetype)initWithName:(NSString *)name
                   arguments:(NSDictionary<NSString *, Class> *)argumentsAndTypes
               defaultValues:(NSDictionary<NSString *, NSString *> *)defaultValues
                     context:(iTermVariablesSuggestionContext)context
                       block:(iTermBuiltInFunctionsExecutionBlock)block NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface iTermBuiltInFunctions : NSObject

+ (instancetype)sharedInstance;

- (void)registerFunction:(iTermBuiltInFunction *)function
               namespace:(NSString *)namespace;

- (BOOL)haveFunctionWithName:(NSString *)name
                   arguments:(NSArray<NSString *> *)arguments;

- (void)callFunctionWithName:(NSString *)name
                  parameters:(NSDictionary<NSString *, id> *)parameters
                      source:(id (^)(NSString *))source
                  completion:(iTermBuiltInFunctionCompletionBlock)completion;

- (NSError *)undeclaredIdentifierError:(NSString *)identifier;
- (NSError *)invalidReferenceError:(NSString *)reference name:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
