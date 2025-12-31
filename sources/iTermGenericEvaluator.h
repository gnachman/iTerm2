//
//  iTermGenericEvaluator.h
//  iTerm2
//
//  Created by George Nachman on 12/31/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermExpressionEvaluator;
@class iTermVariableReference;
@class iTermVariableScope;

// Represents a scripting object that can be evaluated (an interpolated string or an expression).
//
// Any variables referenced will be recorded as dependencies and the value will be
// reevaluated when any of them change. The observer is invoked when the evaluated string changes.
//
// If you just need a one-time evaluation (synchronous or async) use
// +[iTermScriptFunctionCall evaluateString:timeout:source:completion:].
@interface iTermGenericEvaluator : NSObject

@property (nonatomic, copy) NSString *stringToEvaluate;

// To perform evaluation in a different scope than the one that owns the sourcePath and destinationPath set this.
@property (nullable, nonatomic, copy) iTermVariableScope *(^contextProvider)(void);

// Gives the evaluation scope, using `contextProvider` if set.
@property (nullable, nonatomic, readonly) iTermVariableScope *scope;

// NOTE: The observer returns a replacement value. If it differs from the passed-in value then
// it will be called again with the replacement and nil error. It only gets once chance to
// provide a replacement. This is useful for error handling. If your observer gets called
// an error, it can return a string that is treated as the result of evaluation. When there is
// a destination path, it will get updated before the observer is called a second time. This
// is useful because observers often depend on the fact that the destination path is updated
// before they are called, since they'll use that to produce a user-visible value. Be careful
// with side-effects when handling errors because the second call has a nil error.
@property (nonatomic, copy, nullable) id(^observer)(id _Nullable, NSError * _Nullable);
@property (nullable, nonatomic, readonly) id evaluationResult;
@property (nonatomic, readonly) NSArray<iTermVariableReference *> *refs;
@property (nonatomic, copy) NSString *destinationPath;

- (instancetype)initWithString:(NSString *)stringToEvaluate
                         scope:(nullable iTermVariableScope *)scope
            sideEffectsAllowed:(BOOL)sideEffectsAllowed
                      observer:(id(^ _Nullable)(id _Nullable newValue,
                                                NSError * _Nullable error))observer NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithScope:(nullable iTermVariableScope *)scope
                   sourcePath:(NSString *)sourcePath
              destinationPath:(nullable NSString *)destinationPath
           sideEffectsAllowed:(BOOL)sideEffectsAllowed NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
- (void)invalidate;
- (void)evaluateSynchronously:(BOOL)synchronously
           sideEffectsAllowed:(BOOL)sideEffectsAllowed
                    withScope:(iTermVariableScope *)scope
                   completion:(void (^)(id _Nullable result,
                                        NSError * _Nullable error,
                                        NSSet<NSString *> *missing))completion;

// Subclasses must implement this.
- (iTermExpressionEvaluator *)expressionEvaluator;

@end

NS_ASSUME_NONNULL_END
