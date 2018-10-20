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

@property (nonatomic, readonly) NSString *swiftyString;
@property (nonatomic, readonly, copy) id (^source)(NSString *);
@property (nonatomic, readonly, copy) void (^observer)(NSString *);
@property (nullable, nonatomic, readonly) NSString *evaluatedString;
@property (nonatomic, readonly) NSArray<iTermVariableReference *> *refs;

// Variables the string depends on
@property (nonatomic, readonly) NSSet<NSString *> *dependencies;

- (instancetype)initWithString:(NSString *)swiftyString
                         scope:(nullable iTermVariableScope *)scope
                      observer:(void (^)(NSString *newValue))observer NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)invalidate;

@end

// Just stores the swifty string and does nothing else. Evaluated string will always be empty.
// Is free of side effects.
@interface iTermSwiftyStringPlaceholder : iTermSwiftyString

- (instancetype)initWithString:(NSString *)swiftyString NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithString:(NSString *)swiftyString
                         scope:(nullable iTermVariableScope *)scope
                      observer:(void (^)(NSString *newValue))observer NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
