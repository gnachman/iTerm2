//
//  iTermSwiftyString.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/12/18.
//

#import <Foundation/Foundation.h>
#import "iTermGenericEvaluator.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermVariableReference;
@class iTermVariableScope;

// Represents a string with interpolated components like:
//   foo\(f())bar
// Nested interpolation is supported.
@interface iTermSwiftyString : iTermGenericEvaluator

@property (nonatomic, copy) NSString *swiftyString;
@property (nullable, nonatomic, readonly) NSString *evaluatedString;

- (void)evaluateSynchronously:(BOOL)synchronously
           sideEffectsAllowed:(BOOL)sideEffectsAllowed
                   withScope:(iTermVariableScope *)scope
                   completion:(void (^)(NSString * _Nullable result, NSError * _Nullable error, NSSet<NSString *> * _Nullable missing))completion;

@end

@interface iTermExpressionObserver: iTermGenericEvaluator
@end

// Just stores the swifty string and does nothing else. Evaluated string will always be empty.
// Is free of side effects.
@interface iTermSwiftyStringPlaceholder : iTermSwiftyString

- (instancetype)initWithString:(NSString *)swiftyString NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithScope:(nullable iTermVariableScope *)scope
                   sourcePath:(NSString *)sourcePath
              destinationPath:(nullable NSString *)destinationPath
           sideEffectsAllowed:(BOOL)sideEffectsAllowed NS_UNAVAILABLE;

- (instancetype)initWithString:(NSString *)swiftyString
                         scope:(nullable iTermVariableScope *)scope
            sideEffectsAllowed:(BOOL)sideEffectsAllowed
                      observer:(NSString *(^ _Nullable)(NSString * _Nullable newValue, NSError * _Nullable error))observer NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
