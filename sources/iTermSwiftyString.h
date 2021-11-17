//
//  iTermSwiftyString.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/12/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermVariableReference;
@class iTermVariableScope;

// Represents a string with interpolated components like:
//   foo\(f())bar
// Nested interpolation is supported.
// Any variables referenced will be recorded as dependencies and the value will be
// reevaluated when any of them change. The observer is invoked when the evaluated string changes.
//
// If you just need a one-time evaluation (synchronous or async) use
// +[iTermScriptFunctionCall evaluateString:timeout:source:completion:].
@interface iTermSwiftyString : NSObject

@property (nonatomic, copy) NSString *swiftyString;
@property (nonatomic, readonly, copy) id (^source)(NSString *);

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
@property (nonatomic, copy) NSString *(^observer)(NSString * _Nullable, NSError * _Nullable);
@property (nullable, nonatomic, readonly) NSString *evaluatedString;
@property (nonatomic, readonly) NSArray<iTermVariableReference *> *refs;
@property (nonatomic, copy) NSString *destinationPath;

// Variables the string depends on
@property (nonatomic, readonly) NSSet<NSString *> *dependencies;

- (instancetype)initWithString:(NSString *)swiftyString
                         scope:(nullable iTermVariableScope *)scope
                      observer:(NSString *(^ _Nullable)(NSString * _Nullable newValue, NSError * _Nullable error))observer NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithScope:(nullable iTermVariableScope *)scope
                   sourcePath:(NSString *)sourcePath
              destinationPath:(nullable NSString *)destinationPath NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
- (void)invalidate;
- (void)evaluateSynchronously:(BOOL)synchronously
                    withScope:(iTermVariableScope *)scope
                   completion:(void (^)(NSString * _Nullable result,
                                        NSError * _Nullable error,
                                        NSSet<NSString *> *missing))completion;

@end

// Just stores the swifty string and does nothing else. Evaluated string will always be empty.
// Is free of side effects.
@interface iTermSwiftyStringPlaceholder : iTermSwiftyString

- (instancetype)initWithString:(NSString *)swiftyString NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithScope:(nullable iTermVariableScope *)scope
                   sourcePath:(NSString *)sourcePath
              destinationPath:(nullable NSString *)destinationPath NS_UNAVAILABLE;

- (instancetype)initWithString:(NSString *)swiftyString
                         scope:(nullable iTermVariableScope *)scope
                      observer:(NSString *(^ _Nullable)(NSString * _Nullable newValue, NSError * _Nullable error))observer NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
